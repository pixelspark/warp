import Foundation

func QBEAsyncMain(block: () -> ()) {
	dispatch_async(dispatch_get_main_queue(), block)
}

func QBEAsyncBackground(block: () -> ()) {
	let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
	dispatch_async(gq, block)
}

/** A QBESink is a function used as a callback in response to QBEStream.fetch. It receives a set of rows from the stream
as well as a boolean indicating whether the next call of fetch() will return any rows (true) or not (false). **/
typealias QBESink = ([QBERow], Bool) -> ()

let QBEStreamDefaultBatchSize = 256

/** QBEStream represents a data set that can be streamed (consumed in batches). This allows for efficient processing of
data sets for operations that do not require memory (e.g. a limit or filter can be performed almost statelessly). The 
stream implements a single method (fetch) that allows batch fetching of result rows. The size of the batches are defined
by the stream (for now). **/
protocol QBEStream: NSObjectProtocol {
	/** The column names associated with the rows produced by this stream. **/
	func columnNames(callback: ([QBEColumn]) -> ())
	
	/** Request the next batch of rows from the stream; when it is available, asynchronously call (on the main queue) the
	specified callback. If the callback is to perform computations, it should queue this work to another queue. If the 
	stream is empty (e.g. hasNext was false when fetch was last called), fetch may either silently ignore your rqeuest or 
	call the callback with an empty set of rows. **/
	func fetch(consumer: QBESink)
	
	/** Create a copy of this stream. The copied stream is reset to the initial position (e.g. will return the first row
	of the data set during the first call to fetch on the copy). **/
	func clone() -> QBEStream
}

/** A QBETransformer is a stream that provides data from an other stream, and applies a transformation step in between.
This class needs to be subclassed before it does any real work (in particular, the transform and clone methods should be
overridden). **/
private class QBETransformer: NSObject, QBEStream {
	let source: QBEStream
	var stopped = false
	
	init(source: QBEStream) {
		self.source = source
	}
	
	private func columnNames(callback: ([QBEColumn]) -> ()) {
		source.columnNames(callback)
	}
	
	/** Perform the stream transformation on the given set of rows. The function should call the callback exactly once
	with the resulting set of rows (which does not have to be of equal size as the input set) and a boolean indicating
	whether stream processing should be halted (e.g. because a certain limit is reached or all information needed by the
	transform has been found already). **/
	private func transform(rows: [QBERow], callback: ([QBERow], Bool) -> ()) {
		fatalError("QBETransformer.transform should be implemented in a subclass")
	}
	
	private func fetch(consumer: QBESink) {
		if !stopped {
			source.fetch { (rows, hasNext) -> () in
				self.transform(rows, callback: { (transformedRows, shouldStop) -> () in
					self.stopped = shouldStop
					consumer(transformedRows, !self.stopped && hasNext)
				})
			}
		}
	}
	
	private func clone() -> QBEStream {
		fatalError("Should be implemented by subclass")
	}
}

/** The QBELimitTransformer limits the number of rows passed through a stream. It effectively stops pumping data from the
source stream to the consuming stream when the limit is reached. **/
private class QBELimitTransformer: QBETransformer {
	var position = 0
	let limit: Int
	
	init(source: QBEStream, numberOfRows: Int) {
		self.limit = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(rows: [QBERow], callback: ([QBERow], Bool) -> ()) {
		if (position+rows.count) < limit {
			position += rows.count
			callback(rows, false)
		}
		else if position < limit {
			let n = limit - position
			callback(Array(rows[0..<n]), true)
		}
		else {
			callback([], true)
		}
	}
	
	private override func clone() -> QBEStream {
		return QBELimitTransformer(source: source, numberOfRows: limit)
	}
}

private class QBEColumnsTransformer: QBETransformer {
	let columns: [QBEColumn]
	var indexes: [Int]? = nil
	
	init(source: QBEStream, selectColumns: [QBEColumn]) {
		self.columns = selectColumns
		super.init(source: source)
	}
	
	override private func columnNames(callback: ([QBEColumn]) -> ()) {
		source.columnNames { (sourceColumns) -> () in
			self.ensureIndexes {
				var result: [QBEColumn] = []
				for idx in self.indexes! {
					result.append(sourceColumns[idx])
				}
				callback(result)
			}
		}
	}
	
	override private func transform(rows: [QBERow], callback: ([QBERow],Bool) -> ()) {
		ensureIndexes {
			assert(self.indexes != nil)
			
			var result: [QBERow] = []
			
			for row in rows {
				var newRow: QBERow = []
				newRow.reserveCapacity(self.indexes!.count)
				for idx in self.indexes! {
					newRow.append(row[idx])
				}
				result.append(newRow)
			}
			callback(result, false)
		}
	}
	
	private func ensureIndexes(callback: () -> ()) {
		if indexes == nil {
			indexes = []
			source.columnNames({ (sourceColumnNames: [QBEColumn]) -> () in
				for column in self.columns {
					if let idx = find(sourceColumnNames, column) {
						self.indexes!.append(idx)
					}
				}
				
				callback()
			})
		}
		else {
			callback()
		}
	}
	
	private override func clone() -> QBEStream {
		return QBEColumnsTransformer(source: source, selectColumns: columns)
	}
}

/** QBEStreamData is an implementation of QBEData that performs data operations on a stream. QBEStreamData will consume 
the whole stream and proxy to a raster-based implementation for operations that cannot efficiently be performed on a 
stream. **/
class QBEStreamData: NSObject, QBEData {
	let source: QBEStream
	
	init(source: QBEStream) {
		self.source = source
	}
	
	private func fallback() -> QBEData {
		return QBERasterData(future: self.raster)
	}

	func raster(callback: (QBERaster) -> ()) {
		var data: [QBERow] = []
		
		let s = source.clone()
		var appender: QBESink! = nil
		appender = { (rows, hasNext) -> () in
			rows.each({data.append($0)})
			if hasNext {
				QBEAsyncBackground {
					s.fetch(appender)
				}
			}
			else {
				s.columnNames({ (columnNames) -> () in
					callback(QBERaster(data: data, columnNames: columnNames, readOnly: true))
				})
			}
		}
		s.fetch(appender)
	}
	
	func transpose() -> QBEData {
		// This cannot be streamed
		return fallback().transpose()
	}
	
	func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
		return fallback().aggregate(groups, values: values)
	}
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		return QBEStreamData(source: QBEColumnsTransformer(source: source, selectColumns: columns))
	}
	
	func limit(numberOfRows: Int) -> QBEData {
		// Limit has a streaming implementation in QBELimitTransformer
		return QBEStreamData(source: QBELimitTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	func random(numberOfRows: Int) -> QBEData {
		return fallback().random(numberOfRows)
	}
	
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		return fallback().calculate(calculations)
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		source.columnNames(callback)
	}
	
	func stream() -> QBEStream? {
		return source.clone()
	}
}