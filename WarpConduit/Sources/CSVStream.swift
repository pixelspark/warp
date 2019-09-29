/* Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

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

public final class CSVStream: NSObject, WarpCore.Stream, CHCSVParserDelegate {
	let parser: CHCSVParser
	let url: URL

	private var columns: OrderedSet<Column> = []
	private var finished: Bool = false
	private var templateRow: [String?] = []
	private var row: [String?] = []
	private var rows: [[String?]] = []
	private var queue: DispatchQueue
	private var rowsRead: Int = 0
	private var totalBytes: Int = 0

	let hasHeaders: Bool
	let fieldSeparator: unichar
	let locale: Language?

	#if DEBUG
	private var totalTime: TimeInterval = 0.0
	#endif

	public init(url: URL, fieldSeparator: unichar, hasHeaders: Bool, locale: Language?) {
		self.url = url
		self.hasHeaders = hasHeaders
		self.fieldSeparator = fieldSeparator
		self.locale = locale

		// Get total file size
		let p = url.path
		do {
			let attributes = try FileManager.default.attributesOfItem(atPath: p)
			totalBytes = (attributes[FileAttributeKey.size] as? NSNumber)?.intValue ?? 0
		}
		catch {
			totalBytes = 0
		}

		// Create a queue and initialize the parser
		queue = DispatchQueue(label: "nl.pixelspark.qbe.QBECSVStreamQueue", qos: .userInitiated, attributes: [], target: nil)
		parser = CHCSVParser(contentsOfDelimitedURL: url as NSURL as URL, delimiter: fieldSeparator)
		parser.sanitizesFields = true
		super.init()

		parser.delegate = self
		parser._beginDocument()
		finished = !parser._parseRecord()

		if hasHeaders {
			// Load column names, avoiding duplicate names
			let columns = row.map({Column($0 ?? "")})
			self.columns = []

			for columnName in columns {
				if self.columns.contains(columnName) {
					let count = self.columns.reduce(0, { (n, item) in return n + (item == columnName ? 1 : 0) })
					self.columns.append(Column("\(columnName.name)_\(Column.defaultNameForIndex(count).name)"))
				}
				else {
					self.columns.append(columnName)
				}
			}

			rows.removeAll(keepingCapacity: true)
		}
		else {
			for i in 0..<row.count {
				columns.append(Column.defaultNameForIndex(i))
			}
		}

		templateRow = Array<String?>(repeating: nil, count: columns.count)
	}

	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success(columns))
	}

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		queue.sync {
			job.time("Parse CSV", items: StreamDefaultBatchSize, itemType: "row") {
				#if DEBUG
					let startTime = NSDate.timeIntervalSinceReferenceDate
				#endif
				var fetched = 0
				while !self.finished && (fetched < StreamDefaultBatchSize) && !job.isCancelled {
					self.finished = !self.parser._parseRecord()
					fetched += 1
				}

				// Calculate progress
				self.rowsRead += fetched
				if self.totalBytes > 0 {
					let progress = Double(self.parser.totalBytesRead) / Double(self.totalBytes)
					job.reportProgress(progress, forKey: self.hashValue);
				}
				#if DEBUG
					self.totalTime += (NSDate.timeIntervalSinceReferenceDate - startTime)
				#endif
			}

			let r = Array(self.rows)
			self.rows.removeAll(keepingCapacity: true)

			let finished = self.finished

			job.async {
				/* Convert the read string values to Values. Do this asynchronously because Language.valueForLocalString
				may take a lot of time, and we really want the CSV parser to continue meanwhile */
				let v = r.map { row -> [Value] in
					var values = row.map { field -> Value in
						if let value = field {
							return self.locale != nil ? self.locale!.valueForLocalString(value) : Language.valueForExchangedString(value)
						}
						return Value.empty
					}

					// If the row contains more fields than we want, chop off the last ones
					if values.count > self.columns.count {
						values = Array(values[0..<self.columns.count])
					}
					else {
						// If there are less fields in the row then there are columns, pad with nils
						while values.count < self.columns.count {
							values.append(Value.empty)
						}
					}

					return values
				}

				consumer(.success(v), finished ? .finished : .hasMore)
			}
		}
	}

	#if DEBUG
	deinit {
		if self.totalTime > 0 {
			trace("Read \(self.parser.totalBytesRead) in \(self.totalTime) ~= \((Double(self.parser.totalBytesRead) / 1024.0 / 1024.0)/self.totalTime) MiB/s")
		}
	}
	#endif

	public func parser(_ parser: CHCSVParser, didBeginLine line: UInt) {
		row = templateRow
	}

	public func parser(_ parser: CHCSVParser, didEndLine line: UInt) {
		rows.append(row)
	}

	public func parser(_ parser: CHCSVParser, didReadField field: String, at index: Int) {
		if index >= row.count {
			row.append(field)
		}
		else {
			row[index] = field
		}
	}

	public func clone() -> WarpCore.Stream {
		return CSVStream(url: url, fieldSeparator: fieldSeparator, hasHeaders: self.hasHeaders, locale: self.locale)
	}
}
