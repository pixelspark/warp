import Foundation

/** A QBESink is a function used as a callback in response to QBEStream.fetch. It receives a set of rows from the stream
as well as a boolean indicating whether the next call of fetch() will return any rows (true) or not (false). */
public typealias QBESink = (QBEFallible<Array<QBETuple>>, Bool) -> ()

/** The default number of rows that a QBEStream will send to a consumer upon request through QBEStream.fetch. */
public let QBEStreamDefaultBatchSize = 256

/** QBEStream represents a data set that can be streamed (consumed in batches). This allows for efficient processing of
data sets for operations that do not require memory (e.g. a limit or filter can be performed almost statelessly). The 
stream implements a single method (fetch) that allows batch fetching of result rows. The size of the batches are defined
by the stream (for now).

Streams are drained using concurrent calls to the 'fetch' method (multiple 'wavefronts'). */
public protocol QBEStream {
	/** The column names associated with the rows produced by this stream. */
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ())
	
	/** 
	Request the next batch of rows from the stream; when it is available, asynchronously call (on the main queue) the
	specified callback. If the callback is to perform computations, it should queue this work to another queue. If the 
	stream is empty (e.g. hasNext was false when fetch was last called), fetch calls your callback with hasNext set to
	false once again. 
	
	Should the stream encounter an error, the callback is called with a failed data set and hasNext set to false. Consumers
	should stop fetch()ing when either the data set is failed or hasNext is false. 
	
	Note that fetch may be called multiple times concurrently (i.e. multiple 'wavefronts') - it is the stream's job to 
	ensure ordered and consistent delivery of data. Streams may use a serial dispatch queue to serialize requests if 
	necessary. */
	func fetch(job: QBEJob, consumer: QBESink)
	
	/** Create a copy of this stream. The copied stream is reset to the initial position (e.g. will return the first row
	of the data set during the first call to fetch on the copy). */
	func clone() -> QBEStream
}

/** This class manages the multithreaded retrieval of data from a stream. It will make concurrent calls to a stream's
fetch function ('wavefronts') and store the returned rows. When all results are in, a callback is called. The class also
exists to avoid issues with reference counting (the sink closure needs to reference itself). */
private class QBEStreamPuller {
	let job: QBEJob
	let stream: QBEStream
	var data: [QBETuple] = []
	var columnNames: [QBEColumn]
	let callback: (QBEFallible<QBERaster>) -> ()

	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBEStreamPuller", DISPATCH_QUEUE_SERIAL)
	private let concurrentWavefronts: Int
	private var outstandingWavefronts = 0
	private var lastStartedWavefront = 0
	private var lastSinkedWavefront = 0
	private var earlyResults: [Int : (QBEFallible<[QBETuple]>, Bool)] = [:]

	init(stream: QBEStream, job: QBEJob, columnNames: [QBEColumn], callback: (QBEFallible<QBERaster>) -> ()) {
		self.columnNames = columnNames
		self.callback = callback
		self.stream = stream
		self.job = job
		self.concurrentWavefronts = NSProcessInfo.processInfo().processorCount
	}

	/** Start up to self.concurrentFetches number of fetch 'wavefronts' that will deliver their data to the
	'sink' funtion. */
	private func start() {
		dispatch_sync(queue) {
			while self.outstandingWavefronts < self.concurrentWavefronts {
				self.lastStartedWavefront++
				self.outstandingWavefronts++
				let waveFrontId = self.lastStartedWavefront
				self.job.async {
					self.job.log("Start wf \(waveFrontId)")
					self.stream.fetch(self.job, consumer: { (rows, hasNext) in
						/** Some fetches may return earlier than others, but we need to reassemble them in the correct
						order. Therefore we keep track of a 'wavefront ID'. If the last wavefront that was 'sinked' was
						this wavefront's id minus one, we can sink this one directly. Otherwise we need to put it in a 
						queue for later sinking. */
						self.job.log("finish wf \(waveFrontId)")
						dispatch_sync(self.queue) {
							if self.lastSinkedWavefront == waveFrontId-1 {
								self.lastSinkedWavefront = waveFrontId
								self.job.log("Direct: \(waveFrontId)")
								self.sink(rows, hasNext: hasNext)

								// Maybe now we can sink an earlier result
								while let (earlierRows, earlierHasNext) = self.earlyResults[self.lastSinkedWavefront+1] {
									self.earlyResults.removeValueForKey(self.lastSinkedWavefront+1)
									self.lastSinkedWavefront++
									self.job.log("Delayed: \(self.lastSinkedWavefront) \(earlierHasNext)")
									self.sink(earlierRows, hasNext: earlierHasNext)
								}
							}
							else {
								self.job.log("Out-of-order: \(waveFrontId) but expecting \(self.lastSinkedWavefront+1)")
								self.earlyResults[waveFrontId] = (rows, hasNext)
								//self.lastSinkedWavefront = waveFrontId
							}
						}
					})
				}
			}
		}
	}

	/** Receives batches of data from streams and appends them to the buffer of rows. It will spawn new wavefronts
	through 'start' each time it is called, unless the stream indicates there are no more records. When the last
	wavefront has reported in, sink will call self.callback. */
	private func sink(rows: QBEFallible<Array<QBETuple>>, hasNext: Bool) {
		var isLast = false
		self.outstandingWavefronts--;
		isLast = self.outstandingWavefronts == 0

		switch rows {
		case .Success(let r):
			// Append the rows to our buffered raster
			self.data.appendContentsOf(r)

			if !hasNext {
				if isLast {
					self.job.log("Last job and !hasNext, stopping")
					self.callback(.Success(QBERaster(data: self.data, columnNames: self.columnNames, readOnly: true)))
				}
				else {
					self.job.log("!hasNext, but not last job; waiting")
				}
			}
			else {
				// If the stream indicates there are more rows, fetch them
				job.async {
					self.start()
					return
				}
			}

		case .Failure(let errorMessage):
			callback(.Failure(errorMessage))
		}
	}
}

/** QBEStreamData is an implementation of QBEData that performs data operations on a stream. QBEStreamData will consume
the whole stream and proxy to a raster-based implementation for operations that cannot efficiently be performed on a 
stream. */
public class QBEStreamData: QBEData {
	public let source: QBEStream
	
	public init(source: QBEStream) {
		self.source = source
	}
	
	/** The fallback data object implements data operators not implemented here. Because QBERasterData is the fallback
	for QBEStreamData and the other way around, neither should call the fallback for an operation it implements itself,
	and at least one of the classes has to implement each operation. */
	private func fallback() -> QBEData {
		return QBERasterData(future: raster)
	}

	public func raster(job: QBEJob, callback: (QBEFallible<QBERaster>) -> ()) {
		let s = source.clone()
		job.async {
			s.columnNames(job) { (columnNames) -> () in
				switch columnNames {
					case .Success(let cns):
						let h = QBEStreamPuller(stream: s, job: job, columnNames: cns, callback: callback)
						h.start()

					case .Failure(let e):
						callback(.Failure(e))
				}
			}
		}
	}

	public func transpose() -> QBEData {
		// This cannot be streamed
		return fallback().transpose()
	}
	
	public func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
		return fallback().aggregate(groups, values: values)
	}
	
	public func distinct() -> QBEData {
		return fallback().distinct()
	}
	
	public func union(data: QBEData) -> QBEData {
		// TODO: this can be implemented efficiently as a streaming operation
		return fallback().union(data)
	}
	
	public func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData {
		return QBEStreamData(source: QBEFlattenTransformer(source: source, valueTo: valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to))
	}
	
	public func selectColumns(columns: [QBEColumn]) -> QBEData {
		// Implemented by QBEColumnsTransformer
		return QBEStreamData(source: QBEColumnsTransformer(source: source, selectColumns: columns))
	}
	
	public func offset(numberOfRows: Int) -> QBEData {
		return QBEStreamData(source: QBEOffsetTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	public func limit(numberOfRows: Int) -> QBEData {
		// Limit has a streaming implementation in QBELimitTransformer
		return QBEStreamData(source: QBELimitTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	public func random(numberOfRows: Int) -> QBEData {
		return QBEStreamData(source: QBERandomTransformer(source: source, numberOfRows: numberOfRows))
	}
	
	public func unique(expression: QBEExpression, job: QBEJob, callback: (QBEFallible<Set<QBEValue>>) -> ()) {
		// TODO: this can be implemented as a stream with some memory
		return fallback().unique(expression, job: job, callback: callback)
	}
	
	public func sort(by: [QBEOrder]) -> QBEData {
		return fallback().sort(by)
	}
	
	public func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		// Implemented as stream by QBECalculateTransformer
		return QBEStreamData(source: QBECalculateTransformer(source: source, calculations: calculations))
	}
	
	public func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}
	
	public func join(join: QBEJoin) -> QBEData {
		return QBEStreamData(source: QBEJoinTransformer(source: source, join: join))
	}
	
	public func filter(condition: QBEExpression) -> QBEData {
		return QBEStreamData(source: QBEFilterTransformer(source: source, condition: condition))
	}
	
	public func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		source.columnNames(job, callback: callback)
	}
	
	public func stream() -> QBEStream {
		return source.clone()
	}
}

public class QBEErrorStream: QBEStream {
	private let error: QBEError
	
	public init(_ error: QBEError) {
		self.error = error
	}
	
	public func fetch(job: QBEJob, consumer: QBESink) {
		consumer(.Failure(self.error), false)
	}
	
	public func clone() -> QBEStream {
		return QBEErrorStream(self.error)
	}
	
	public func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Failure(self.error))
	}
}

/** 
A stream that never produces any data (but doesn't return errors either). */
public class QBEEmptyStream: QBEStream {
	public init() {
	}

	public func fetch(job: QBEJob, consumer: QBESink) {
		consumer(.Success([]), false)
	}
	
	public func clone() -> QBEStream {
		return QBEEmptyStream()
	}
	
	public func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Success([]))
	}
}

/** 
A stream that sources from a Swift generator of QBETuple. */
public class QBESequenceStream: QBEStream {
	private let sequence: AnySequence<QBETuple>
	private var generator: AnyGenerator<QBETuple>
	private let columns: [QBEColumn]
	private var position: Int = 0
	private var rowCount: Int? = nil // nil = number of rows is yet unknown
	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBESequenceStream", DISPATCH_QUEUE_SERIAL)
	
	public init(_ sequence: AnySequence<QBETuple>, columnNames: [QBEColumn], rowCount: Int? = nil) {
		self.sequence = sequence
		self.generator = sequence.generate()
		self.columns = columnNames
		self.rowCount = rowCount
	}
	
	public func fetch(job: QBEJob, consumer: QBESink) {
		dispatch_sync(queue) {
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
				self.position += rows.count
				if let rc = self.rowCount {
					job.reportProgress(Double(self.position) / Double(rc), forKey: unsafeAddressOf(self).hashValue)
				}

				job.async {
					consumer(.Success(Array(rows)), !done)
				}
			}
		}
	}
	
	public func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		callback(.Success(self.columns))
	}
	
	public func clone() -> QBEStream {
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
	private func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
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
						self.transform(rows, hasNext: hasNext, job: job, callback: { (transformedRows, shouldContinue) -> () in
							self.stopped = self.stopped || !shouldContinue
							job.async {
								consumer(transformedRows, !self.stopped && hasNext)
							}
						})
					
					case .Failure(let error):
						consumer(.Failure(error), false)
				}
			})
		}
		else {
			consumer(.Success([]), false)
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
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
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
				callback(.Success(Array(newRows)), false)
				
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
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
		source.columnNames(job) { (columnNames) -> () in
			switch columnNames {
			case .Success(let cns):
				job.time("Stream filter", items: rows.count, itemType: "row") {
					let newRows = Array(rows.filter({(row) -> Bool in
						return self.condition.apply(QBERow(row, columnNames: cns), foreign: nil, inputValue: nil) == QBEValue.BoolValue(true)
					}))
					
					callback(.Success(Array(newRows)), hasNext)
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
	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBERandomTransformer", DISPATCH_QUEUE_SERIAL)
	var reservoir: QBEReservoir<QBETuple>
	var done = false
	
	init(source: QBEStream, numberOfRows: Int) {
		reservoir = QBEReservoir<QBETuple>(sampleSize: numberOfRows)
		super.init(source: source)
	}
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
		dispatch_sync(queue) {
			job.time("Reservoir fill", items: rows.count, itemType: "rows") {
				self.reservoir.add(rows)
			}
			
			if hasNext {
				// More input is coming from the source, do not return our sample yet
				callback(.Success([]), true)
			}
			else {
				// This was the last batch of inputs, call back with our sample and tell the consumer there is no more
				if !self.done {
					self.done = true
					callback(.Success(Array(self.reservoir.sample)), false)
				}
				else {
					callback(.Success(Array()), false)
				}
			}
		}
	}
	
	private override func clone() -> QBEStream {
		return QBERandomTransformer(source: source.clone(), numberOfRows: reservoir.sampleSize)
	}
}

/** The QBEOffsetTransformer skips the first specified number of rows passed through a stream. */
private class QBEOffsetTransformer: QBETransformer {
	var position = 0
	let offset: Int
	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBEOffsetTransformer", DISPATCH_QUEUE_SERIAL)
	
	init(source: QBEStream, numberOfRows: Int) {
		self.offset = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob?, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
		dispatch_sync(queue) {
			if self.position > self.offset {
				self.position += rows.count
				callback(.Success(rows), hasNext)
			}
			else {
				let rest = self.offset - self.position
				self.position += rows.count
				if rest > rows.count {
					callback(.Success([]), hasNext)
				}
				else {
					callback(.Success(Array(rows[rest..<rows.count])), hasNext)
				}
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
	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBELimitTransformer", DISPATCH_QUEUE_SERIAL)
	var position = 0
	let limit: Int
	
	init(source: QBEStream, numberOfRows: Int) {
		self.limit = numberOfRows
		super.init(source: source)
	}
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
		dispatch_sync(queue) {
			// We haven't reached the limit yet, not even after streaming this chunk
			if (self.position + rows.count) < self.limit {
				self.position += rows.count
				job.reportProgress(Double(self.position) / Double(self.limit), forKey: unsafeAddressOf(self).hashValue)
				callback(.Success(rows), hasNext)
			}
			// We will reach the limit before streaming this full chunk, split it and call it a day
			else if self.position < self.limit {
				let n = self.limit - self.position
				self.position += rows.count
				job.reportProgress(1.0, forKey: unsafeAddressOf(self).hashValue)
				callback(.Success(Array(rows[0..<n])), false)
			}
			// The limit has already been met fully
			else {
				callback(.Success([]), false)
			}
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
	
	override private func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>,Bool) -> ()) {
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
					callback(.Success(Array(result)), hasNext)
				
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
	private let queue = dispatch_queue_create("nl.pixelspark.Warp.QBECalculateTransformer", DISPATCH_QUEUE_SERIAL)
	private var ensureIndexes: QBEFuture<Void>! = nil

	init(source: QBEStream, calculations: Dictionary<QBEColumn, QBEExpression>) {
		var optimizedCalculations = Dictionary<QBEColumn, QBEExpression>()
		for (column, expression) in calculations {
			optimizedCalculations[column] = expression.prepare()
		}
		
		self.calculations = optimizedCalculations
		super.init(source: source)

		self.ensureIndexes = QBEFuture({ [unowned self] (job, callback) -> () in
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
		})
	}
	
	private override func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		self.ensureIndexes.get(job) {
			callback(self.columns!)
		}
	}
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
		self.ensureIndexes.get(job) {
			job.time("Stream calculate", items: rows.count, itemType: "row") {
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
						
						callback(.Success(Array(newData)), hasNext)
						
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
	
	private override func transform(rows: Array<QBETuple>, hasNext: Bool, job: QBEJob, callback: (QBEFallible<Array<QBETuple>>, Bool) -> ()) {
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
											let joinedTuples = Array<QBETuple>(joinedRaster.raster)
											callback(.Success(joinedTuples), hasNext)
										}
										
									case .InnerJoin:
										ourRaster.innerJoin(joinExpression, raster: foreignRaster, job: job) { (joinedRaster) in
											let joinedTuples = Array<QBETuple>(joinedRaster.raster)
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