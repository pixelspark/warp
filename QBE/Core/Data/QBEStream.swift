import Foundation

/** A QBESink is a function used as a callback in response to QBEStream.fetch. It receives a set of rows from the stream
as well as a boolean indicating whether the next call of fetch() will return any rows (true) or not (false). */
typealias QBESink = (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()

/** The default number of rows that a QBEStream will send to a consumer upon request through QBEStream.fetch. */
let QBEStreamDefaultBatchSize = 256

/** QBEStream represents a data set that can be streamed (consumed in batches). This allows for efficient processing of
data sets for operations that do not require memory (e.g. a limit or filter can be performed almost statelessly). The 
stream implements a single method (fetch) that allows batch fetching of result rows. The size of the batches are defined
by the stream (for now). */
protocol QBEStream {
	/** The column names associated with the rows produced by this stream. */
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ())
	
	/** 
	Request the next batch of rows from the stream; when it is available, asynchronously call (on the main queue) the
	specified callback. If the callback is to perform computations, it should queue this work to another queue. If the 
	stream is empty (e.g. hasNext was false when fetch was last called), fetch calls your callback with hasNext set to
	false once again. 
	
	Should the stream encounter an error, the callback is called with a failed data set and hasNext set to false. Consumers
	should stop fetch()ing when either the data set is failed or hasNext is false. */
	func fetch(job: QBEJob, consumer: QBESink)
	
	/** Create a copy of this stream. The copied stream is reset to the initial position (e.g. will return the first row
	of the data set during the first call to fetch on the copy). */
	func clone() -> QBEStream
}

/** QBEStreamData is an implementation of QBEData that performs data operations on a stream. QBEStreamData will consume 
the whole stream and proxy to a raster-based implementation for operations that cannot efficiently be performed on a 
stream. */
class QBEStreamData: QBEData {
	let source: QBEStream
	
	init(source: QBEStream) {
		self.source = source
	}
	
	/** The fallback data object implements data operators not implemented here. Because QBERasterData is the fallback
	for QBEStreamData and the other way around, neither should call the fallback for an operation it implements itself,
	and at least one of the classes has to implement each operation. */
	private func fallback() -> QBEData {
		return QBERasterData(future: raster)
	}

	func raster(job: QBEJob, callback: (QBEFallible<QBERaster>) -> ()) {
		let s = source.clone()
		
		job.async {
			var data: [QBETuple] = []
			
			var appender: QBESink! = nil
			appender = { (rows, hasNext) -> () in
				switch rows {
				case .Success(let r):
					// Append the rows to our buffered raster
					data.extend(r)
					
					if !hasNext {
						s.columnNames(job) { (columnNames) -> () in
							callback(columnNames.use {(cns) -> QBERaster in
								return QBERaster(data: data, columnNames: cns, readOnly: true)
							})
						}
					}
					// If the stream indicates there are more rows, fetch them
					else {
						job.async {
							s.fetch(job, consumer: appender)
						}
					}
					
					
				case .Failure(let errorMessage):
					callback(.Failure(errorMessage))
				}
			}
			s.fetch(job, consumer: appender)
		}
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
	
	func union(data: QBEData) -> QBEData {
		// TODO: this can be implemented efficiently as a streaming operation
		return fallback().union(data)
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
	
	func unique(expression: QBEExpression, job: QBEJob, callback: (QBEFallible<Set<QBEValue>>) -> ()) {
		// TODO: this can be implemented as a stream with some memory
		return fallback().unique(expression, job: job, callback: callback)
	}
	
	func sort(by: [QBEOrder]) -> QBEData {
		return fallback().sort(by)
	}
	
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		// Implemented as stream by QBECalculateTransformer
		return QBEStreamData(source: QBECalculateTransformer(source: source, calculations: calculations))
	}
	
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}
	
	func join(join: QBEJoin) -> QBEData {
		return QBEStreamData(source: QBEJoinTransformer(source: source, join: join))
	}
	
	func filter(condition: QBEExpression) -> QBEData {
		return QBEStreamData(source: QBEFilterTransformer(source: source, condition: condition))
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		source.columnNames(job, callback: callback)
	}
	
	func stream() -> QBEStream {
		return source.clone()
	}
}

class QBEErrorStream: QBEStream {
	private let error: QBEError
	
	init(_ error: QBEError) {
		self.error = error
	}
	
	func fetch(job: QBEJob, consumer: QBESink) {
		consumer(.Failure(self.error), false)
	}
	
	func clone() -> QBEStream {
		return QBEErrorStream(self.error)
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Failure(self.error))
	}
}

/** 
A stream that never produces any data (but doesn't return errors either). */
class QBEEmptyStream: QBEStream {
	func fetch(job: QBEJob, consumer: QBESink) {
		consumer(.Success([]), false)
	}
	
	func clone() -> QBEStream {
		return QBEEmptyStream()
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Success([]))
	}
}

/** 
A stream that sources from a Swift generator of QBETuple. */
class QBESequenceStream: QBEStream {
	private let sequence: AnySequence<QBETuple>
	private var generator: AnyGenerator<QBETuple>
	private let columns: [QBEColumn]
	private var position: Int = 0
	private var rowCount: Int? = nil // nil = number of rows is yet unknown
	
	init(_ sequence: AnySequence<QBETuple>, columnNames: [QBEColumn], rowCount: Int? = nil) {
		self.sequence = sequence
		self.generator = sequence.generate()
		self.columns = columnNames
		self.rowCount = rowCount
	}
	
	func fetch(job: QBEJob, consumer: QBESink) {
		job.time("sequence", items: QBEStreamDefaultBatchSize, itemType: "rows") {
			var done = false
			var rows :[QBETuple] = []
			rows.reserveCapacity(QBEStreamDefaultBatchSize)
			
			for _ in 0..<QBEStreamDefaultBatchSize {
				if let next = self.generator.next() {
					rows.append(next)
				}
				else {
					done = true
					break
				}
			}
			position += rows.count
			if let rc = rowCount {
				job.reportProgress(Double(position) / Double(rc), forKey: unsafeAddressOf(self).hashValue)
			}
			consumer(.Success(ArraySlice(rows)), !done)
		}
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Success(self.columns))
	}
	
	func clone() -> QBEStream {
		return QBESequenceStream(self.sequence, columnNames: self.columns, rowCount: self.rowCount)
	}
}

/** A QBETransformer is a stream that provides data from an other stream, and applies a transformation step in between.
This class needs to be subclassed before it does any real work (in particular, the transform and clone methods should be
overridden). */
private class QBETransformer: NSObject, QBEStream {
	let source: QBEStream
	var stopped = false
	
	init(source: QBEStream) {
		self.source = source
	}
	
	private func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		source.columnNames(job, callback: callback)
	}
	
	/** Perform the stream transformation on the given set of rows. The function should call the callback exactly once
	with the resulting set of rows (which does not have to be of equal size as the input set) and a boolean indicating
	whether stream processing should be halted (e.g. because a certain limit is reached or all information needed by the
	transform has been found already). */
	private func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		fatalError("QBETransformer.transform should be implemented in a subclass")
	}
	
	private func fetch(job: QBEJob, consumer: QBESink) {
		if !stopped {
			source.fetch(job, consumer: QBEOnce { (fallibleRows, hasNext) -> () in
				if !hasNext {
					self.stopped = true
				}
				
				switch fallibleRows {
					case .Success(let rows):
						self.transform(rows, hasNext: hasNext, job: job, callback: { (transformedRows, shouldStop) -> () in
							self.stopped = shouldStop
							consumer(transformedRows, !self.stopped && hasNext)
						})
					
					case .Failure(let error):
						consumer(.Failure(error), false)
				}
			})
		}
	}
	
	/** Returns a clone of the transformer. It should also clone the source stream. */
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
	private var originalColumns: QBEFallible<[QBEColumn]>? = nil
	
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
	
	private func prepare(job: QBEJob, callback: () -> ()) {
		if self.originalColumns == nil {
			source.columnNames(job) { (cols) -> () in
				self.originalColumns = cols
				callback()
			}
		}
		else {
			callback()
		}
	}
	
	private override func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Success(columnNames))
	}
	
	private override func clone() -> QBEStream {
		return QBEFlattenTransformer(source: source.clone(), valueTo: valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: rowIdentifierTo)
	}
	
	private override func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		prepare(job) {
			switch self.originalColumns! {
			case .Success(let originalColumns):
				var newRows: [QBETuple] = []
				newRows.reserveCapacity(self.columnNames.count * rows.count)
				var templateRow: [QBEValue] = self.columnNames.map({(c) -> (QBEValue) in return QBEValue.InvalidValue})
				let valueIndex = (self.writeRowIdentifier ? 1 : 0) + (self.writeColumnIdentifier ? 1 : 0);
				
				job.time("flatten", items: self.columnNames.count * rows.count, itemType: "cells") {
					for row in rows {
						if self.writeRowIdentifier {
							templateRow[0] = self.rowIdentifier!.apply(QBERow(row, columnNames: originalColumns), foreign: nil, inputValue: nil)
						}
						
						for columnIndex in 0..<originalColumns.count {
							if self.writeColumnIdentifier {
								templateRow[self.writeRowIdentifier ? 1 : 0] = QBEValue(originalColumns[columnIndex].name)
							}
							
							templateRow[valueIndex] = row[columnIndex]
							newRows.append(templateRow)
						}
					}
				}
				callback(.Success(ArraySlice(newRows)), false)
				
			case .Failure(let error):
				callback(.Failure(error), false)
			}
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
	
	private override func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		source.columnNames(job) { (columnNames) -> () in
			switch columnNames {
			case .Success(let cns):
				job.time("Stream filter", items: rows.count, itemType: "row") {
					let newRows = Array(rows.filter({(row) -> Bool in
						return self.condition.apply(QBERow(row, columnNames: cns), foreign: nil, inputValue: nil) == QBEValue.BoolValue(true)
					}))
					
					callback(.Success(ArraySlice(newRows)), false)
				}
				
			case .Failure(let error):
				callback(.Failure(error), false)
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBEFilterTransformer(source: source.clone(), condition: condition)
	}
}

/** The QBERandomTransformer randomly samples the specified amount of rows from a stream. It uses reservoir sampling to
achieve this. */
private class QBERandomTransformer: QBETransformer {
	var sample: [QBETuple] = []
	let sampleSize: Int
	var samplesSeen: Int = 0
	
	init(source: QBEStream, numberOfRows: Int) {
		sampleSize = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(var rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		// Reservoir initial fill
		if sample.count < sampleSize {
			let length = sampleSize - sample.count
			
			job.time("Reservoir fill", items: min(length,rows.count), itemType: "rows") {
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
			job.time("Reservoir replace", items: rows.count, itemType: "rows") {
				for i in 0..<rows.count {
					/* The chance of choosing an item starts out at (1/s) and ends at (1/N), where s is the sample size and N
					is the number of actual input rows. */
					let probability = Int.random(0, upper: self.samplesSeen+i)
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
			callback(.Success([]), false)
		}
		else {
			// This was the last batch of inputs, call back with our sample and tell the consumer there is no more
			callback(.Success(ArraySlice(sample)), true)
		}
	}
	
	private override func clone() -> QBEStream {
		return QBERandomTransformer(source: source.clone(), numberOfRows: sampleSize)
	}
}

/** The QBEOffsetTransformer skips the first specified number of rows passed through a stream. */
private class QBEOffsetTransformer: QBETransformer {
	var position = 0
	let offset: Int
	
	init(source: QBEStream, numberOfRows: Int) {
		self.offset = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob?, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		if position > offset {
			position += rows.count
			callback(.Success(rows), false)
		}
		else {
			let rest = offset - position
			if rest > rows.count {
				callback(.Success([]), false)
			}
			else {
				callback(.Success(rows[rest..<rows.count]), false)
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBEOffsetTransformer(source: source.clone(), numberOfRows: offset)
	}
}

/** The QBELimitTransformer limits the number of rows passed through a stream. It effectively stops pumping data from the
source stream to the consuming stream when the limit is reached. */
private class QBELimitTransformer: QBETransformer {
	var position = 0
	let limit: Int
	
	init(source: QBEStream, numberOfRows: Int) {
		self.limit = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		// We haven't reached the limit yet, not even after streaming this chunk
		if (position+rows.count) < limit {
			position += rows.count
			job.reportProgress(Double(position) / Double(limit), forKey: unsafeAddressOf(self).hashValue)
			callback(.Success(rows), false)
		}
		// We will reach the limit before streaming this full chunk, split it and call it a day
		else if position < limit {
			let n = limit - position
			job.reportProgress(1.0, forKey: unsafeAddressOf(self).hashValue)
			callback(.Success(rows[0..<n]), true)
		}
		// The limit has already been met fully
		else {
			callback(.Success([]), true)
		}
	}
	
	private override func clone() -> QBEStream {
		return QBELimitTransformer(source: source.clone(), numberOfRows: limit)
	}
}

private class QBEColumnsTransformer: QBETransformer {
	let columns: [QBEColumn]
	var indexes: QBEFallible<[Int]>? = nil
	
	init(source: QBEStream, selectColumns: [QBEColumn]) {
		self.columns = selectColumns
		super.init(source: source)
	}
	
	override private func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		source.columnNames(job) { (sourceColumns) -> () in
			switch sourceColumns {
			case .Success(let cns):
				self.ensureIndexes(job) {
					callback(self.indexes!.use({(idxs) in
						return idxs.map({return cns[$0]})
					}))
				}
				
			case .Failure(let error):
				callback(.Failure(error))
			}
		}
	}
	
	override private func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>,Bool) -> ()) {
		ensureIndexes(job) {
			assert(self.indexes != nil)
			
			switch self.indexes! {
				case .Success(let idxs):
					var result: [QBETuple] = []
					
					for row in rows {
						var newRow: QBETuple = []
						newRow.reserveCapacity(idxs.count)
						for idx in idxs {
							newRow.append(row[idx])
						}
						result.append(newRow)
					}
					callback(.Success(ArraySlice(result)), false)
				
				case .Failure(let error):
					callback(.Failure(error), false)
			}
		}
	}
	
	private func ensureIndexes(job: QBEJob, callback: () -> ()) {
		if indexes == nil {
			var idxs: [Int] = []
			source.columnNames(job) { (sourceColumnNames: QBEFallible<[QBEColumn]>) -> () in
				switch sourceColumnNames {
					case .Success(let sourceCols):
						for column in self.columns {
							if let idx = sourceCols.indexOf(column) {
								idxs.append(idx)
							}
						}
						
						self.indexes = .Success(idxs)
						callback()
					
					case .Failure(let error):
						self.indexes = .Failure(error)
				}
				
			}
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
	private var indices: QBEFallible<Dictionary<QBEColumn, Int>>? = nil
	private var columns: QBEFallible<[QBEColumn]>? = nil
	
	init(source: QBEStream, calculations: Dictionary<QBEColumn, QBEExpression>) {
		var optimizedCalculations = Dictionary<QBEColumn, QBEExpression>()
		for (column, expression) in calculations {
			optimizedCalculations[column] = expression.prepare()
		}
		
		self.calculations = optimizedCalculations
		super.init(source: source)
	}
	
	private func ensureIndexes(job: QBEJob, callback: () -> ()) {
		if self.indices == nil {
			source.columnNames(job) { (columnNames) -> () in
				switch columnNames {
				case .Success(let cns):
					var columns = cns
					var indices = Dictionary<QBEColumn, Int>()
					
					// Create newly calculated columns
					for (targetColumn, _) in self.calculations {
						var columnIndex = cns.indexOf(targetColumn) ?? -1
						if columnIndex == -1 {
							columns.append(targetColumn)
							columnIndex = columns.count-1
						}
						indices[targetColumn] = columnIndex
					}
					self.indices = .Success(indices)
					self.columns = .Success(columns)
					
				case .Failure(let error):
					self.columns = .Failure(error)
					self.indices = .Failure(error)
				}
				
				callback()
			}
		}
		else {
			callback()
		}
	}
	
	private override func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		self.ensureIndexes(job) {
			callback(self.columns!)
		}
	}
	
	private override func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		self.ensureIndexes(job) {
			job.time("Calculate", items: rows.count, itemType: "row") {
				switch self.columns! {
				case .Success(let cns):
					switch self.indices! {
					case .Success(let idcs):
						let newData = Array(rows.map({ (var row: QBETuple) -> QBETuple in
							for _ in 0..<max(0, cns.count - row.count) {
								row.append(QBEValue.EmptyValue)
							}
							
							for (targetColumn, formula) in self.calculations {
								let columnIndex = idcs[targetColumn]!
								let inputValue: QBEValue = row[columnIndex]
								let newValue = formula.apply(QBERow(row, columnNames: cns), foreign: nil, inputValue: inputValue)
								row[columnIndex] = newValue
							}
							return row
						}))
						
						callback(.Success(ArraySlice(newData)), false)
						
					case .Failure(let error):
						callback(.Failure(error), false)
					}
					
				case .Failure(let error):
					callback(.Failure(error), false)
				}
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBECalculateTransformer(source: source.clone(), calculations: calculations)
	}
}

/** The QBEJoinTransformer can perform joins between a stream on the left side and an arbitrary data set on the right
side. For each chunk of rows from the left side (streamed), it will call filter() on the right side data set to obtain
a set that contains at least all rows necessary to join the rows in the chunk. It will then perform the join on the rows
in the chunk and stream out that result. 

This is memory-efficient for joins that have a 1:1 relationship between left and right, or joins where rows from the left
side all map to the same row on the right side (m:n where m>n). It breaks down for joins where a single row on the left 
side maps to a high number of rows on the right side (m:n where n>>m). However, there is no good alternative for such 
joins apart from performing it in-database (which will be tried before QBEJoinTransformer is put to work). */
private class QBEJoinTransformer: QBETransformer {
	let join: QBEJoin
	private var leftColumnNames: QBEFuture<QBEFallible<[QBEColumn]>>
	private var columnNamesCached: QBEFallible<[QBEColumn]>? = nil
	private var isIneffectiveJoin: Bool = false
	
	init(source: QBEStream, join: QBEJoin) {
		self.leftColumnNames = QBEFuture(source.columnNames)
		self.join = join
		super.init(source: source)
	}
	
	private override func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		if let c = self.columnNamesCached {
			callback(c)
		}
		else {
			self.getColumnNames(job, callback: { (c) -> () in
				self.columnNamesCached = c
				callback(c)
			})
		}
	}
	
	private func getColumnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		self.leftColumnNames.get(job) { (leftColumnsFallible) in
			switch leftColumnsFallible {
			case .Success(let leftColumns):
				switch self.join.type {
				case .LeftJoin, .InnerJoin:
					self.join.foreignData.columnNames(job) { (rightColumnsFallible) -> () in
						switch rightColumnsFallible {
						case .Success(let rightColumns):
							// Only new columns from the right side will be added
							let rightColumnsInResult = rightColumns.filter({return !leftColumns.contains($0)})
							self.isIneffectiveJoin = rightColumnsInResult.count == 0
							callback(.Success(leftColumns + rightColumnsInResult))
							
						case .Failure(let e):
							callback(.Failure(e))
						}
					}
				}
				
				case .Failure(let e):
					callback(.Failure(e))
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBEJoinTransformer(source: self.source.clone(), join: self.join)
	}
	
	private override func transform(rows: ArraySlice<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<ArraySlice<QBETuple>>, Bool) -> ()) {
		self.leftColumnNames.get(job) { (leftColumnNamesFallible) in
			switch leftColumnNamesFallible {
			case .Success(let leftColumnNames):
				// The columnNames function checks whether this join will actually add columns to the result.
				self.columnNames(job) { (columnNamesFallible) -> () in
					switch columnNamesFallible {
					case .Success(_):
						// Do we have any new columns at all?
						if self.isIneffectiveJoin {
							callback(.Success(rows), hasNext)
						}
						else {
							// We need to do work
							let foreignData = self.join.foreignData
							let joinExpression = self.join.expression
							
							// Create a filter expression that fetches all rows that we could possibly match to our own rows
							var foreignFilters: [QBEExpression] = []
							for row in rows {
								foreignFilters.append(joinExpression.expressionForForeignFiltering(QBERow(row, columnNames: leftColumnNames)))
							}
							let foreignFilter = QBEFunctionExpression(arguments: foreignFilters, type: QBEFunction.Or)
							
							// Find relevant rows from the foreign data set
							foreignData.filter(foreignFilter).raster(job, callback: { (foreignRasterFallible) -> () in
								switch foreignRasterFallible {
								case .Success(let foreignRaster):
									// Perform the actual join using our own set of rows and the raster of possible matches from the foreign table
									let ourRaster = QBERaster(data: Array(rows), columnNames: leftColumnNames, readOnly: true)
									
									switch self.join.type {
									case .LeftJoin:
										ourRaster.leftJoin(joinExpression, raster: foreignRaster, job: job) { (joinedRaster) in
											let joinedTuples = ArraySlice<QBETuple>(joinedRaster.raster)
											callback(.Success(joinedTuples), hasNext)
										}
										
									case .InnerJoin:
										ourRaster.innerJoin(joinExpression, raster: foreignRaster, job: job) { (joinedRaster) in
											let joinedTuples = ArraySlice<QBETuple>(joinedRaster.raster)
											callback(.Success(joinedTuples), hasNext)
										}
									}
								
								case .Failure(let e):
									callback(.Failure(e), false)
								}
							})
						}
					
					case .Failure(let e):
						callback(.Failure(e), false)
					}
				}
				
			case .Failure(let e):
				callback(.Failure(e), false)
			}
		}
	}
}