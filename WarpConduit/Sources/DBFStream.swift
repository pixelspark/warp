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

final public class DBFStream: NSObject, WarpCore.Stream {
	let url: URL

	private var queue = DispatchQueue(label: "nl.pixelspark.Warp.QBEDBFStream")
	private let handle: DBFHandle?
	private let recordCount: Int32
	private let fieldCount: Int32
	private var columns: OrderedSet<Column>? = nil
	private var types: [DBFFieldType]? = nil
	private var position: Int32 = 0
	private var mutex = Mutex()

	public init(url: URL) {
		self.url = url
		self.handle = DBFOpen((url as NSURL).fileSystemRepresentation, "rb")
		if self.handle == nil {
			self.fieldCount = 0
			self.recordCount = 0
		}
		else {
			self.recordCount = DBFGetRecordCount(self.handle)
			self.fieldCount = DBFGetFieldCount(self.handle)
		}
	}

	deinit {
		DBFClose(handle)
	}

	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		if self.columns == nil {
			let fieldCount = self.fieldCount
			var fields: OrderedSet<Column> = []
			var types: [DBFFieldType] = []
			for i in 0..<fieldCount {
				var fieldName =  [CChar](repeating: 0, count: 12)
				let type = DBFGetFieldInfo(handle, i, &fieldName, nil, nil)
				if let fieldNameString = String(cString: fieldName, encoding: String.Encoding.utf8) {
					fields.append(Column(fieldNameString))
					types.append(type)
				}
			}
			self.types = types
			columns = fields
		}

		callback(.success(columns!))
	}

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		(self.queue).async {
			self.columns(job) { (columns) -> () in
                let (start, end): (Int32, Int32) = self.mutex.locked { () -> (Int32, Int32) in
                    let start = self.position
					let end = min(self.recordCount, start + Int32(StreamDefaultBatchSize))
					self.position = end
					return (start, end)
				}

				var rows: [Tuple] = []
				for recordIndex in start..<end {
					if DBFIsRecordDeleted(self.handle, recordIndex) == 0 {
						var row: Tuple = []
						for fieldIndex in 0..<self.fieldCount {
							if DBFIsAttributeNULL(self.handle, recordIndex, fieldIndex) != 0 {
								row.append(Value.empty)
							}
							else {
								switch self.types![Int(fieldIndex)].rawValue {
								case FTString.rawValue:
									if let s = String(cString: DBFReadStringAttribute(self.handle, recordIndex, fieldIndex), encoding: String.Encoding.utf8) {
										row.append(Value.string(s))
									}
									else {
										row.append(Value.invalid)
									}

								case FTInteger.rawValue:
									row.append(Value.int(Int(DBFReadIntegerAttribute(self.handle, recordIndex, fieldIndex))))

								case FTDouble.rawValue:
									row.append(Value.double(DBFReadDoubleAttribute(self.handle, recordIndex, fieldIndex)))

								case FTInvalid.rawValue:
									row.append(Value.invalid)

								case FTLogical.rawValue:
									// TODO: this needs to be translated to a BoolValue. However, no idea how logical values are stored in DBF..
									row.append(Value.invalid)

								default:
									row.append(Value.invalid)
								}
							}
						}

						rows.append(row)
					}
				}


				job.async {
					let status = self.mutex.locked { () -> StreamStatus in
						return (self.position < (self.recordCount-1)) ? .hasMore : .finished
					}
					consumer(.success(Array(rows)), status)
				}
			}
		}
	}

	public func clone() -> WarpCore.Stream {
		return DBFStream(url: self.url)
	}
}
