import Foundation

/** A QBESink is a function used as a callback in response to QBEStream.fetch. It receives a set of rows from the stream
as well as a boolean indicating whether the next call of fetch() will return any rows (true) or not (false). **/
typealias QBESink = (Slice<QBERow>, Bool) -> ()

/** The default number of rows that a QBEStream will send to a consumer upon request through QBEStream.fetch. **/
let QBEStreamDefaultBatchSize = 256

/** QBEStream represents a data set that can be streamed (consumed in batches). This allows for efficient processing of
data sets for operations that do not require memory (e.g. a limit or filter can be performed almost statelessly). The 
stream implements a single method (fetch) that allows batch fetching of result rows. The size of the batches are defined
by the stream (for now). **/
protocol QBEStream {
	/** The column names associated with the rows produced by this stream. **/
	func columnNames(callback: ([QBEColumn]) -> ())
	
	/** Request the next batch of rows from the stream; when it is available, asynchronously call (on the main queue) the
	specified callback. If the callback is to perform computations, it should queue this work to another queue. If the 
	stream is empty (e.g. hasNext was false when fetch was last called), fetch may either silently ignore your rqeuest or 
	call the callback with an empty set of rows. **/
	func fetch(consumer: QBESink, job: QBEJob?)
	
	/** Create a copy of this stream. The copied stream is reset to the initial position (e.g. will return the first row
	of the data set during the first call to fetch on the copy). **/
	func clone() -> QBEStream
}

/** QBEStreamData is an implementation of QBEData that performs data operations on a stream. QBEStreamData will consume 
the whole stream and proxy to a raster-based implementation for operations that cannot efficiently be performed on a 
stream. **/
class QBEStreamData: QBEData {
	let source: QBEStream
	
	init(source: QBEStream) {
		self.source = source
	}
	
	private func fallback() -> QBEData {
		return QBERasterData(future: raster)
	}

	func raster(callback: (QBERaster) -> (), job: QBEJob?) {
		var data: [QBERow] = []
		
		let s = source.clone()
		var appender: QBESink! = nil
		appender = { (rows, hasNext) -> () in
			let cancelled = job?.cancelled ?? false
			if hasNext && !cancelled {
				QBEAsyncBackground {
					s.fetch(appender, job: job)
				}
			}
				
			rows.each({data.append($0)})
				
			if !hasNext {
				s.columnNames({ (columnNames) -> () in
					callback(QBERaster(data: data, columnNames: columnNames, readOnly: true))
				})
			}
		}
		s.fetch(appender, job: job)
	}
	
	func transpose() -> QBEData {
		// This cannot be streamed
		return fallback().transpose()
	}
	
	func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
		return fallback().aggregate(groups, values: values)
	}
	
	func distinct() -> QBEData {
		return fallback().distinct()
	}
	
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData {
		return QBEStreamData(source: QBEFlattenTransformer(source: source, valueTo: valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to))
	}
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		// Implemented by QBEColumnsTransformer
		return QBEStreamData(source: QBEColumnsTransformer(source: source, selectColumns: columns))
	}
	
	func limit(numberOfRows: Int) -> QBEData {
		// Limit has a streaming implementation in QBELimitTransformer
		return QBEStreamData(source: QBELimitTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	func random(numberOfRows: Int) -> QBEData {
		// TODO: this should be implemented as a stream. See how MongoDB/RethinkDB deal with random-without-replacement sampling.
		return fallback().random(numberOfRows)
	}
	
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) {
		// TODO: this can be implemented as a stream with some memory
		return fallback().unique(expression, callback: callback)
	}
	
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		// Implemented as stream by QBECalculateTransformer
		return QBEStreamData(source: QBECalculateTransformer(source: source, calculations: calculations))
	}
	
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}
	
	func filter(condition: QBEExpression) -> QBEData {
		return QBEStreamData(source: QBEFilterTransformer(source: source, condition: condition))
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		source.columnNames(callback)
	}
	
	func stream() -> QBEStream? {
		return source.clone()
	}
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
	private func transform(rows: Slice<QBERow>, callback: (Slice<QBERow>, Bool) -> ()) {
		fatalError("QBETransformer.transform should be implemented in a subclass")
	}
	
	private func fetch(consumer: QBESink, job: QBEJob?) {
		if !stopped {
			source.fetch({ (rows, hasNext) -> () in
				self.transform(rows, callback: { (transformedRows, shouldStop) -> () in
					self.stopped = shouldStop
					consumer(transformedRows, !self.stopped && hasNext)
				})
			}, job: job)
		}
	}
	
	/** Returns a clone of the transformer. It should also clone the source stream. **/
	private func clone() -> QBEStream {
		fatalError("Should be implemented by subclass")
	}
}

private class QBEFlattenTransformer: QBETransformer {
	private let valueTo: QBEColumn
	private let columnNameTo: QBEColumn?
	private let rowIdentifier: QBEExpression?
	private let rowIdentifierTo: QBEColumn?
	
	private let columnNames: [QBEColumn]
	private let writeRowIdentifier: Bool
	private let writeColumnIdentifier: Bool
	private var originalColumns: [QBEColumn]? = nil
	
	init(source: QBEStream, valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) {
		self.valueTo = valueTo
		self.columnNameTo = columnNameTo
		self.rowIdentifier = rowIdentifier
		self.rowIdentifierTo = to
		
		// Determine which columns we are going to produce
		var cols: [QBEColumn] = []
		if rowIdentifierTo != nil && rowIdentifier != nil {
			cols.append(rowIdentifierTo!)
			writeRowIdentifier = true
		}
		else {
			writeRowIdentifier = false
		}
		
		if let ct = columnNameTo {
			cols.append(ct)
			writeColumnIdentifier = true
		}
		else {
			writeColumnIdentifier = false
		}
		cols.append(valueTo)
		self.columnNames = cols
		
		super.init(source: source)
	}
	
	private func prepare(callback: () -> ()) {
		if self.originalColumns == nil {
			source.columnNames({ (cols) -> () in
				self.originalColumns = cols
				callback()
			})
		}
		else {
			callback()
		}
	}
	
	private override func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(columnNames)
	}
	
	private override func clone() -> QBEStream {
		return QBEFlattenTransformer(source: source.clone(), valueTo: valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: rowIdentifierTo)
	}
	
	private override func transform(rows: Slice<QBERow>, callback: (Slice<QBERow>, Bool) -> ()) {
		prepare {
			var newRows: [QBERow] = []
			newRows.reserveCapacity(self.columnNames.count * rows.count)
			var templateRow: [QBEValue] = self.columnNames.map({(c) -> (QBEValue) in return QBEValue.InvalidValue})
			let valueIndex = (self.writeRowIdentifier ? 1 : 0) + (self.writeColumnIdentifier ? 1 : 0);

			QBETime("flatten", self.columnNames.count * rows.count, "cells") {
				for row in rows {
					if self.writeRowIdentifier {
						templateRow[0] = self.rowIdentifier!.apply(row, columns: self.originalColumns!, inputValue: nil)
					}
					
					for columnIndex in 0..<self.originalColumns!.count {
						if self.writeColumnIdentifier {
							templateRow[self.writeRowIdentifier ? 1 : 0] = QBEValue(self.originalColumns![columnIndex].name)
						}
						
						templateRow[valueIndex] = row[columnIndex]
						newRows.append(templateRow)
					}
				}
			}
			callback(Slice(newRows), false)
		}
	}
}

private class QBEFilterTransformer: QBETransformer {
	var position = 0
	let condition: QBEExpression
	
	init(source: QBEStream, condition: QBEExpression) {
		self.condition = condition
		super.init(source: source)
	}
	
	private override func transform(rows: Slice<QBERow>, callback: (Slice<QBERow>, Bool) -> ()) {
		source.columnNames { (columnNames) -> () in
			QBETime("Stream filter", rows.count, "row") {
				let newRows = rows.filter({(row) -> Bool in
					return self.condition.apply(row, columns: columnNames, inputValue: nil) == QBEValue.BoolValue(true)
				})
				
				callback(newRows, false)
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBEFilterTransformer(source: source.clone(), condition: condition)
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
	
	private override func transform(rows: Slice<QBERow>, callback: (Slice<QBERow>, Bool) -> ()) {
		if (position+rows.count) < limit {
			position += rows.count
			callback(rows, false)
		}
		else if position < limit {
			let n = limit - position
			callback(rows[0..<n], true)
		}
		else {
			callback([], true)
		}
	}
	
	private override func clone() -> QBEStream {
		return QBELimitTransformer(source: source.clone(), numberOfRows: limit)
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
	
	override private func transform(rows: Slice<QBERow>, callback: (Slice<QBERow>,Bool) -> ()) {
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
			callback(Slice(result), false)
		}
	}
	
	private func ensureIndexes(callback: () -> ()) {
		// FIXME: not threadsafe
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
		return QBEColumnsTransformer(source: source.clone(), selectColumns: columns)
	}
}

private class QBECalculateTransformer: QBETransformer {
	let calculations: Dictionary<QBEColumn, QBEExpression>
	private var indices: Dictionary<QBEColumn, Int>? = nil
	private var columns: [QBEColumn]? = nil
	
	init(source: QBEStream, calculations: Dictionary<QBEColumn, QBEExpression>) {
		var optimizedCalculations = Dictionary<QBEColumn, QBEExpression>()
		for (column, expression) in calculations {
			optimizedCalculations[column] = expression.prepare()
		}
		
		self.calculations = optimizedCalculations
		super.init(source: source)
	}
	
	private func ensureIndexes(callback:() -> ()) {
		if self.indices == nil {
			source.columnNames { (var columnNames) -> () in
				var indices = Dictionary<QBEColumn, Int>()
				
				// Create newly calculated columns
				for (targetColumn, formula) in self.calculations {
					var columnIndex = find(columnNames, targetColumn) ?? -1
					if columnIndex == -1 {
						columnNames.append(targetColumn)
						columnIndex = columnNames.count-1
					}
					indices[targetColumn] = columnIndex
				}
				self.indices = indices
				self.columns = columnNames
				callback()
			}
		}
		else {
			callback()
		}
	}
	
	private override func columnNames(callback: ([QBEColumn]) -> ()) {
		self.ensureIndexes {
			callback(self.columns!)
		}
	}
	
	private override func transform(var rows: Slice<QBERow>, callback: (Slice<QBERow>, Bool) -> ()) {
		self.ensureIndexes {
			QBETime("Calculate", rows.count, "row") {
				let newData = rows.map({ (var row: QBERow) -> QBERow in
					for n in 0..<max(0, self.columns!.count - row.count) {
						row.append(QBEValue.EmptyValue)
					}
					
					for (targetColumn, formula) in self.calculations {
						let columnIndex = self.indices![targetColumn]!
						let inputValue: QBEValue = row[columnIndex]
						let newValue = formula.apply(row, columns: self.columns!, inputValue: inputValue)
						row[columnIndex] = newValue
					}
					return row
				})
			
				callback(newData, false)
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBECalculateTransformer(source: source.clone(), calculations: calculations)
	}
}