import Foundation

/** A QBESink is a function used as a callback in response to QBEStream.fetch. It receives a set of rows from the stream
as well as a boolean indicating whether the next call of fetch() will return any rows (true) or not (false). **/
typealias QBESink = (ArraySlice<QBERow>, Bool) -> ()

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
	
	/** The fallback data object implements data operators not implemented here. Because QBERasterData is the fallback
	for QBEStreamData and the other way around, neither should call the fallback for an operation it implements itself,
	and at least one of the classes has to implement each operation. **/
	private func fallback() -> QBEData {
		return QBERasterData(future: raster)
	}

	func raster(job: QBEJob?, callback: (QBERaster) -> ()) {
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
			
			data.extend(rows)
				
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
	
	func offset(numberOfRows: Int) -> QBEData {
		return QBEStreamData(source: QBEOffsetTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	func limit(numberOfRows: Int) -> QBEData {
		// Limit has a streaming implementation in QBELimitTransformer
		return QBEStreamData(source: QBELimitTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	func random(numberOfRows: Int) -> QBEData {
		return QBEStreamData(source: QBERandomTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) {
		// TODO: this can be implemented as a stream with some memory
		return fallback().unique(expression, callback: callback)
	}
	
	func sort(by order: [QBEOrder]) -> QBEData {
		return fallback().sort(by: order)
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
	
	func stream() -> QBEStream {
		return source.clone()
	}
}

/** A stream that never produces any data. **/
class QBEEmptyStream: QBEStream {
	func fetch(consumer: QBESink, job: QBEJob?) {
		consumer([], true)
	}
	
	func clone() -> QBEStream {
		return QBEEmptyStream()
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback([])
	}
}

/** A stream that sources from a Swift generator of QBERow. **/
class QBESequenceStream: QBEStream {
	private let sequence: SequenceOf<QBERow>
	private var generator: GeneratorOf<QBERow>
	private let columns: [QBEColumn]
	
	init(_ sequence: SequenceOf<QBERow>, columnNames: [QBEColumn]) {
		self.sequence = sequence
		self.generator = sequence.generate()
		self.columns = columnNames
	}
	
	func fetch(consumer: QBESink, job: QBEJob?) {
		var done = false
		var rows :[QBERow] = []
		rows.reserveCapacity(QBEStreamDefaultBatchSize)
		
		for i in 0..<QBEStreamDefaultBatchSize {
			if let next = generator.next() {
				rows.append(next)
			}
			else {
				done = true
				break
			}
		}
		
		consumer(ArraySlice(rows), !done)
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(self.columns)
	}
	
	func clone() -> QBEStream {
		return QBESequenceStream(self.sequence, columnNames: self.columns)
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
	private func transform(rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
		fatalError("QBETransformer.transform should be implemented in a subclass")
	}
	
	private func fetch(consumer: QBESink, job: QBEJob?) {
		if !stopped {
			source.fetch({ (rows, hasNext) -> () in
				self.transform(rows, hasNext: hasNext, job: job, callback: { (transformedRows, shouldStop) -> () in
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
	
	private override func transform(rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
		prepare {
			var newRows: [QBERow] = []
			newRows.reserveCapacity(self.columnNames.count * rows.count)
			var templateRow: [QBEValue] = self.columnNames.map({(c) -> (QBEValue) in return QBEValue.InvalidValue})
			let valueIndex = (self.writeRowIdentifier ? 1 : 0) + (self.writeColumnIdentifier ? 1 : 0);

			QBETime("flatten", self.columnNames.count * rows.count, "cells", job) {
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
			callback(ArraySlice(newRows), false)
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
	
	private override func transform(rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
		source.columnNames { (columnNames) -> () in
			QBETime("Stream filter", rows.count, "row", job) {
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

/** The QBERandomTransformer randomly samples the specified amount of rows from a stream. It uses reservoir sampling to
achieve this. **/
private class QBERandomTransformer: QBETransformer {
	var sample: [QBERow] = []
	let sampleSize: Int
	var samplesSeen: Int = 0
	
	init(source: QBEStream, numberOfRows: Int) {
		sampleSize = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(var rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
		// Reservoir initial fill
		if sample.count < sampleSize {
			let length = sampleSize - sample.count
			
			QBETime("Reservoir fill",min(length,rows.count), "rows", job) {
				sample += rows[0..<min(length,rows.count)]
				self.samplesSeen += min(length,rows.count)
				
				if length >= rows.count {
					rows = []
				}
				else {
					rows = rows[min(length,rows.count)..<rows.count]
				}
			}
		}
		
		/* Reservoir replace (note: if the sample size is larger than the total number of samples we'll ever recieve, 
		this will never execute. We will return the full sample in that case below. */
		if sample.count == sampleSize {
			QBETime("Reservoir replace", rows.count, "rows", job) {
				for i in 0..<rows.count {
					/* The chance of choosing an item starts out at (1/s) and ends at (1/N), where s is the sample size and N
					is the number of actual input rows. */
					let probability = Int.random(lower: 0, upper: self.samplesSeen+i)
					if probability < self.sampleSize {
						// Place this sample in the list at the randomly chosen position
						self.sample[probability] = rows[i]
					}
				}
				
				self.samplesSeen += rows.count
			}
		}
		
		if hasNext {
			// More input is coming from the source, do not return our sample yet
			callback([], false)
		}
		else {
			// This was the last batch of inputs, call back with our sample and tell the consumer there is no more
			callback(ArraySlice(sample), true)
		}
	}
	
	private override func clone() -> QBEStream {
		return QBERandomTransformer(source: source.clone(), numberOfRows: sampleSize)
	}
}

/** The QBEOffsetTransformer skips the first specified number of rows passed through a stream. **/
private class QBEOffsetTransformer: QBETransformer {
	var position = 0
	let offset: Int
	
	init(source: QBEStream, numberOfRows: Int) {
		self.offset = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
		if position > offset {
			position += rows.count
			callback(rows, false)
		}
		else {
			let rest = offset - position
			if rest > rows.count {
				callback([], false)
			}
			else {
				callback(rows[rest..<rows.count], false)
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBEOffsetTransformer(source: source.clone(), numberOfRows: offset)
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
	
	private override func transform(rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
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
	
	override private func transform(rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>,Bool) -> ()) {
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
			callback(ArraySlice(result), false)
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
	
	private override func transform(var rows: ArraySlice<QBERow>, hasNext: Bool, job: QBEJob?, callback: (ArraySlice<QBERow>, Bool) -> ()) {
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