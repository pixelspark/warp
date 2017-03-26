/* Copyright (c) 2014-2017 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
import Foundation
import WarpCore

private enum JSONFileType {
	case arrayOfObjects(columns: [Column])
	case arrayOfValues(column: Column)
	case singleValue(column: Column)

	init(data: Any) {
		// Is this an array?
		if let d = data as? Array<Any> {
			if d.isEmpty {
				self = .arrayOfObjects(columns: [])
			}
			else {
				// Is the first element an object? Then take its columns
				if let value = d.first as? [String: Any] {
					self = .arrayOfObjects(columns: Array(value.keys).map { Column($0) })
				}
				else {
					self = .arrayOfValues(column: Column("items"))
				}
			}
		}
		else {
			self = .singleValue(column: Column("data"))
		}
	}

	var columns: OrderedSet<Column> {
		switch self {
		case .arrayOfObjects(columns: let c): return OrderedSet(c)
		case .arrayOfValues(column: let c): return [c]
		case .singleValue(column: let c): return [c]
		}
	}

	func rowCount(for data: Any) -> Int? {
		switch self {
		case .arrayOfObjects(columns: let c):
			if let d = data as? Array<Any> {
				return d.count
			}
			return nil

		case .arrayOfValues(column: let c):
			if let d = data as? Array<Any> {
				return d.count
			}
			return nil

		case .singleValue(column: let c):
			return 1
		}
	}

	func sequence(for data: Any) -> AnySequence<Row>? {
		switch self {
		case .singleValue(column: _):
			let a = [Row([Value(jsonObject: data)], columns: self.columns)]
			return AnySequence(a)

		case .arrayOfObjects(columns: _):
			if let d = data as? Array<Any> {
				return AnySequence(d.lazy.map { r in
					let cols = self.columns
					var templateRow = Row(Array(repeating: Value.empty, count: cols.count), columns: cols)
					if let row = r as? [String: Any] {
						for col in cols {
							if let value = row[col.name] {
								templateRow[col] = Value(jsonObject: value)
							}
						}
					}
					return templateRow
				})
			}
		case .arrayOfValues(column: _):
			let cols = self.columns

			if let d = data as? Array<Any> {
				return AnySequence(d.lazy.map { r in
					return Row([Value(jsonObject: r)], columns: cols)
				})
			}
		}

		return nil
	}
}

/** Reads a JSON file. Depending on the top level object type, the stream decides how to convert the data to the tabular
structure expected (see JSONFileType above for the different options).

Currently this reads the whole file at once - not very efficient for very large JSON files.
TODO: switch to a streaming parser (e.g. YAJL). */
public final class JSONStream: WarpCore.Stream {
	let url: URL
	private let stream: Future<Fallible<WarpCore.Stream>>
	private var finished: Bool = false

	private let mutex = Mutex()

	public init(url: URL) {
		self.url = url

		self.stream = Future({ (job, callback) -> () in
			do {
				let data = try Data(contentsOf: url)
				let js = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
				let type = JSONFileType(data: js)
				if let seq = type.sequence(for: js) {
					let wrappedSequence = AnySequence(seq.lazy.map { r in return Fallible.success(r.values) })
					let stream = SequenceStream(wrappedSequence, columns: type.columns, rowCount: type.rowCount(for: js))
					callback(.success(stream))
				}
				else {
					callback(.failure("Unsupported file structure"))
				}
			}
			catch {
				callback(.failure(error.localizedDescription))
			}
		})
	}

	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		self.stream.get(job) { result in
			switch result {
			case .success(let stream):
				stream.columns(job, callback: callback)

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		self.stream.get(job) { result in
			switch result {
			case .success(let stream):
				stream.fetch(job, consumer: consumer)

			case .failure(let e):
				consumer(.failure(e), .finished)
			}
		}
	}

	public func clone() -> WarpCore.Stream {
		return JSONStream(url: url)
	}
}
