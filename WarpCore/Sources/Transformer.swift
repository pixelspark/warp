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

/** A Transformer is a stream that provides data from an other stream, and applies a transformation step in between.
This class needs to be subclassed before it does any real work (in particular, the transform and clone methods should be
overridden). A subclass may also implement the `finish` method, which will be called after the final set of rows has been
transformed, but before it is returned to the tranformer's customer. This provides an opportunity to alter the final
result (which is useful for transformers that only return rows after having seen all input rows). */
open class Transformer: NSObject, Stream {
	public let source: Stream
	var stopped = false
	var started = false
	private var outstandingTransforms = 0 { didSet { assert(outstandingTransforms >= 0) } }
	let mutex = Mutex()

	public init(source: Stream) {
		self.source = source
	}

	open func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		source.columns(job, callback: callback)
	}

	public final func fetch(_ job: Job, consumer: @escaping Sink) {
		let shouldContinue = self.mutex.locked { () -> Bool in
			if !started {
				self.started = true
				job.reportProgress(0.0, forKey: Unmanaged.passUnretained(self).toOpaque().hashValue)
			}

			if !self.stopped {
				self.outstandingTransforms += 1
			}
			return !self.stopped
		}

		if shouldContinue {
			source.fetch(job, consumer: once { (fallibleRows, streamStatus) -> () in
				if streamStatus == .finished {
					self.mutex.locked {
						self.stopped = true
					}
				}

				switch fallibleRows {
				case .success(let rows):
					job.async {
						self.transform(rows, streamStatus: streamStatus, job: job, callback: once { (transformedRows, newStreamStatus) -> () in
							let (sourceStopped, outstandingTransforms) = self.mutex.locked { () -> (Bool, Int) in
								self.stopped = self.stopped || newStreamStatus != .hasMore
								self.outstandingTransforms -= 1
								return (self.stopped, self.outstandingTransforms)
							}

							job.async {
								if sourceStopped {
									if outstandingTransforms == 0 {
										self.mutex.locked {
											assert(self.stopped, "finish() called while not stopped yet")
										}
										self.finish(transformedRows, job: job, callback: once { extraRows, finalStreamStatus in
											job.reportProgress(1.0, forKey: Unmanaged.passUnretained(self).toOpaque().hashValue)
											consumer(extraRows, finalStreamStatus)
										})
									}
									else {
										consumer(transformedRows, .finished)
									}
								}
								else {
									consumer(transformedRows, newStreamStatus)
								}
							}
						})
					}

				case .failure(let error):
					consumer(.failure(error), .finished)
				}
			})
		}
		else {
			consumer(.success([]), .finished)
		}
	}

	/** This method will be called after the last transformer has finished its job, but before the last result is
	returned to the stream's consumer. This is the 'last chance' to do any work (i.e. transformers that only return any
	data after having seen all data should do so here). The rows returned from the last call to transform are provided
	as parameter. */
	open func finish(_ lastRows: Fallible<[Tuple]>, job: Job, callback: @escaping Sink) {
		return callback(lastRows, .finished)
	}

	/** Perform the stream transformation on the given set of rows. The function should call the callback exactly once
	with the resulting set of rows (which does not have to be of equal size as the input set) and a boolean indicating
	whether stream processing should be halted (e.g. because a certain limit is reached or all information needed by the
	transform has been found already). */
	open func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		fatalError("Transformer.transform should be implemented in a subclass")
	}

	/** Returns a clone of the transformer. It should also clone the source stream. */
	open func clone() -> Stream {
		fatalError("Should be implemented by subclass")
	}
}

/** StreamDataset is an implementation of Dataset that performs data operations on a stream. StreamDataset will consume
the whole stream and proxy to a raster-based implementation for operations that cannot efficiently be performed on a
stream. */
open class StreamDataset: Dataset {
	public let source: Stream

	public init(source: Stream) {
		self.source = source
	}

	/** The fallback data object implements data operators not implemented here. Because RasterDataset is the fallback
	for StreamDataset and the other way around, neither should call the fallback for an operation it implements itself,
	and at least one of the classes has to implement each operation. */
	private func fallback() -> Dataset {
		return RasterDataset(future: { job, callback in
			return self.raster(job, callback: callback)
		})
	}

	open func raster(_ job: Job, deliver: Delivery, callback: @escaping (Fallible<Raster>, StreamStatus) -> ()) {
		let s = source.clone()
		job.async {
			s.columns(job, callback: once { (columns) -> () in
				switch columns {
				case .success(let cns):
					let h = RasterStreamPuller(stream: s, job: job, columns: cns, deliver: deliver, callback: callback)
					h.start()

				case .failure(let e):
					callback(.failure(e), .finished)
				}
			})
		}
	}

	open func transpose() -> Dataset {
		// This cannot be streamed
		return fallback().transpose()
	}

	open func aggregate(_ groups: [Column : Expression], values: [Column : Aggregator]) -> Dataset {
		return StreamDataset(source: AggregateTransformer(source: source, groups: groups, values: values))
	}

	open func distinct() -> Dataset {
		return fallback().distinct()
	}

	open func union(_ data: Dataset) -> Dataset {
		// TODO: this can be implemented efficiently as a streaming operation
		return fallback().union(data)
	}

	open func flatten(_ valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) -> Dataset {
		return StreamDataset(source: FlattenTransformer(source: source, valueTo: valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to))
	}

	open func selectColumns(_ columns: OrderedSet<Column>) -> Dataset {
		return StreamDataset(source: ColumnsTransformer(source: source, selectColumns: columns))
	}

	open func offset(_ numberOfRows: Int) -> Dataset {
		return StreamDataset(source: OffsetTransformer(source: source, numberOfRows: numberOfRows))
	}

	open func limit(_ numberOfRows: Int) -> Dataset {
		// Limit has a streaming implementation in LimitTransformer
		return StreamDataset(source: LimitTransformer(source: source, numberOfRows: numberOfRows))
	}

	open func random(_ numberOfRows: Int) -> Dataset {
		return StreamDataset(source: RandomTransformer(source: source, numberOfRows: numberOfRows))
	}

	open func unique(_ expression: Expression, job: Job, callback: @escaping (Fallible<Set<Value>>) -> ()) {
		// TODO: this can be implemented as a stream with some memory
		return fallback().unique(expression, job: job, callback: callback)
	}

	open func sort(_ by: [Order]) -> Dataset {
		return fallback().sort(by)
	}

	open func calculate(_ calculations: Dictionary<Column, Expression>) -> Dataset {
		// Implemented as stream by CalculateTransformer
		return StreamDataset(source: CalculateTransformer(source: source, calculations: calculations))
	}

	open func pivot(_ horizontal: OrderedSet<Column>, vertical: OrderedSet<Column>, values: OrderedSet<Column>) -> Dataset {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}

	open func join(_ join: Join) -> Dataset {
		return StreamDataset(source: JoinTransformer(source: source, join: join))
	}

	open func filter(_ condition: Expression) -> Dataset {
		return StreamDataset(source: FilterTransformer(source: source, condition: condition))
	}

	open func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		source.columns(job, callback: callback)
	}

	open func stream() -> Stream {
		return source.clone()
	}
}

private class FlattenTransformer: Transformer {
	private let valueTo: Column
	private let columnNameTo: Column?
	private let rowIdentifier: Expression?
	private let rowIdentifierTo: Column?

	private let columns: OrderedSet<Column>
	private let writeRowIdentifier: Bool
	private let writeColumnIdentifier: Bool
	private var originalColumns: Fallible<OrderedSet<Column>>? = nil

	init(source: Stream, valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) {
		self.valueTo = valueTo
		self.columnNameTo = columnNameTo
		self.rowIdentifier = rowIdentifier
		self.rowIdentifierTo = to

		// Determine which columns we are going to produce
		var cols: OrderedSet<Column> = []
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
		self.columns = cols

		super.init(source: source)
	}

	private func prepare(_ job: Job, callback: @escaping () -> ()) {
		if self.originalColumns == nil {
			source.columns(job) { (cols) -> () in
				self.originalColumns = cols
				callback()
			}
		}
		else {
			callback()
		}
	}

	private override func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success(columns))
	}

	private override func clone() -> Stream {
		return FlattenTransformer(source: source.clone(), valueTo: valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: rowIdentifierTo)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		prepare(job) {
			switch self.originalColumns! {
			case .success(let originalColumns):
				var newRows: [Tuple] = []
				newRows.reserveCapacity(self.columns.count * rows.count)
				var templateRow: [Value] = self.columns.map({(c) -> (Value) in return Value.invalid})
				let valueIndex = (self.writeRowIdentifier ? 1 : 0) + (self.writeColumnIdentifier ? 1 : 0);

				job.time("flatten", items: self.columns.count * rows.count, itemType: "cells") {
					for row in rows {
						if self.writeRowIdentifier {
							templateRow[0] = self.rowIdentifier!.apply(Row(row, columns: originalColumns), foreign: nil, inputValue: nil)
						}

						for columnIndex in 0..<originalColumns.count {
							if self.writeColumnIdentifier {
								templateRow[self.writeRowIdentifier ? 1 : 0] = Value(originalColumns[columnIndex].name)
							}

							templateRow[valueIndex] = row[columnIndex]
							newRows.append(templateRow)
						}
					}
				}
				callback(.success(Array(newRows)), streamStatus)

			case .failure(let error):
				callback(.failure(error), .finished)
			}
		}
	}
}

private class FilterTransformer: Transformer {
	var position = 0
	let condition: Expression

	init(source: Stream, condition: Expression) {
		self.condition = condition
		super.init(source: source)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		source.columns(job) { (columns) -> () in
			switch columns {
			case .success(let cns):
				job.time("Stream filter", items: rows.count, itemType: "row") {
					let newRows = Array(rows.filter({(row) -> Bool in
						return self.condition.apply(Row(row, columns: cns), foreign: nil, inputValue: nil) == Value.bool(true)
					}))

					callback(.success(Array(newRows)), streamStatus)
				}

			case .failure(let error):
				callback(.failure(error), .finished)
			}
		}
	}

	private override func clone() -> Stream {
		return FilterTransformer(source: source.clone(), condition: condition)
	}
}

/** The RandomTransformer randomly samples the specified amount of rows from a stream. It uses reservoir sampling to
achieve this. */
private class RandomTransformer: Transformer {
	var reservoir: Reservoir<Tuple>

	init(source: Stream, numberOfRows: Int) {
		reservoir = Reservoir<Tuple>(sampleSize: numberOfRows)
		super.init(source: source)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		self.mutex.locked {
			job.time("Reservoir fill", items: rows.count, itemType: "rows") {
				self.reservoir.add(rows)
			}

			callback(.success([]), streamStatus)
		}
	}

	private override func finish(_ lastRows: Fallible<[Tuple]>, job: Job, callback: @escaping Sink) {
		self.mutex.locked {
			callback(.success(Array(self.reservoir.sample)), .finished)
		}
	}

	private override func clone() -> Stream {
		return RandomTransformer(source: source.clone(), numberOfRows: reservoir.sampleSize)
	}
}

/** The OffsetTransformer skips the first specified number of rows passed through a stream. */
private class OffsetTransformer: Transformer {
	var position = 0
	let offset: Int

	init(source: Stream, numberOfRows: Int) {
		self.offset = numberOfRows
		super.init(source: source)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		self.mutex.locked {
			if self.position > self.offset {
				self.position += rows.count
				job.async {
					callback(.success(rows), streamStatus)
				}
			}
			else {
				let rest = self.offset - self.position
				let count = rows.count
				self.position += count
				if rest > count {
					job.async {
						callback(.success([]), streamStatus)
					}
				}
				else {
					job.async {
						callback(.success(Array(rows[rest..<count])), streamStatus)
					}
				}
			}
		}
	}

	private override func clone() -> Stream {
		return OffsetTransformer(source: source.clone(), numberOfRows: offset)
	}
}

/** The LimitTransformer limits the number of rows passed through a stream. It effectively stops pumping data from the
source stream to the consuming stream when the limit is reached. */
private class LimitTransformer: Transformer {
	var position = 0
	let limit: Int

	init(source: Stream, numberOfRows: Int) {
		self.limit = numberOfRows
		super.init(source: source)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		self.mutex.locked {
			// We haven't reached the limit yet, not even after streaming this chunk
			if (self.position + rows.count) < self.limit {
				self.position += rows.count
				let progress = Double(self.position) / Double(self.limit)

				job.async {
					job.reportProgress(progress, forKey: Unmanaged.passUnretained(self).toOpaque().hashValue)
					callback(.success(rows), streamStatus)
				}
			}
				// We will reach the limit before streaming this full chunk, split it and call it a day
			else if self.position < self.limit {
				let n = self.limit - self.position
				self.position += rows.count
				job.async {
					job.reportProgress(1.0, forKey: Unmanaged.passUnretained(self).toOpaque().hashValue)
					callback(.success(Array(rows[0..<n])), .finished)
				}
			}
				// The limit has already been met fully
			else {
				job.async {
					callback(.success([]), .finished)
				}
			}
		}
	}

	private override func clone() -> Stream {
		return LimitTransformer(source: source.clone(), numberOfRows: limit)
	}
}

private class ColumnsTransformer: Transformer {
	let columns: OrderedSet<Column>
	var indexes: Fallible<[Int]>? = nil

	init(source: Stream, selectColumns: OrderedSet<Column>) {
		self.columns = selectColumns
		super.init(source: source)
	}

	override private func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		source.columns(job) { (sourceColumns) -> () in
			switch sourceColumns {
			case .success(let cns):
				self.ensureIndexes(job) {
					switch self.indexes! {
					case .success(let idxs):
						let names = OrderedSet(idxs.map({ return cns[$0] }))
						callback(.success(names))

					case .failure(let e):
						callback(.failure(e))
					}
				}

			case .failure(let error):
				callback(.failure(error))
			}
		}
	}

	override private func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		ensureIndexes(job) {
			assert(self.indexes != nil)

			switch self.indexes! {
			case .success(let idxs):
				var result: [Tuple] = []

				for row in rows {
					var newRow: Tuple = []
					newRow.reserveCapacity(idxs.count)
					for idx in idxs {
						newRow.append(row[idx])
					}
					result.append(newRow)
				}
				callback(.success(Array(result)), streamStatus)

			case .failure(let error):
				callback(.failure(error), .finished)
			}
		}
	}

	private func ensureIndexes(_ job: Job, callback: @escaping () -> ()) {
		if indexes == nil {
			var idxs: [Int] = []
			source.columns(job) { (sourceColumnNames: Fallible<OrderedSet<Column>>) -> () in
				switch sourceColumnNames {
				case .success(let sourceCols):
					for column in self.columns {
						if let idx = sourceCols.index(of: column) {
							idxs.append(idx)
						}
					}

					self.indexes = .success(idxs)
					callback()

				case .failure(let error):
					self.indexes = .failure(error)
				}

			}
		}
		else {
			callback()
		}
	}

	private override func clone() -> Stream {
		return ColumnsTransformer(source: source.clone(), selectColumns: columns)
	}
}

private class CalculateTransformer: Transformer {
	let calculations: Dictionary<Column, Expression>
	private var indices: Fallible<Dictionary<Column, Int>>? = nil
	private var columns: Fallible<OrderedSet<Column>>? = nil
	private let queue = DispatchQueue(label: "nl.pixelspark.Warp.CalculateTransformer", attributes: [])
	private var ensureIndexes: Future<Void>! = nil

	init(source: Stream, calculations: Dictionary<Column, Expression>) {
		var optimizedCalculations = Dictionary<Column, Expression>()
		for (column, expression) in calculations {
			optimizedCalculations[column] = expression.prepare()
		}

		self.calculations = optimizedCalculations
		super.init(source: source)

		weak var s: CalculateTransformer? = self
		self.ensureIndexes = Future({ (job, callback) -> () in
			if let s = s {
				if s.indices == nil {
					source.columns(job) { (columns) -> () in
						switch columns {
						case .success(let cns):
							var columns = cns
							var indices = Dictionary<Column, Int>()

							// Create newly calculated columns
							for (targetColumn, _) in s.calculations {
								var columnIndex = cns.index(of: targetColumn) ?? -1
								if columnIndex == -1 {
									columns.append(targetColumn)
									columnIndex = columns.count-1
								}
								indices[targetColumn] = columnIndex
							}
							s.indices = .success(indices)
							s.columns = .success(columns)

						case .failure(let error):
							s.columns = .failure(error)
							s.indices = .failure(error)
						}

						callback()
					}
				}
				else {
					callback()
				}
			}
		})
	}

	private override func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		self.ensureIndexes.get(job) {
			callback(self.columns!)
		}
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		self.ensureIndexes.get(job) {
			job.time("Stream calculate", items: rows.count, itemType: "row") {
				switch self.columns! {
				case .success(let cns):
					switch self.indices! {
					case .success(let idcs):
						let newDataset = Array(rows.map({ (inRow: Tuple) -> Tuple in
							var row = inRow
							for _ in 0..<max(0, cns.count - row.count) {
								row.append(Value.empty)
							}

							for (targetColumn, formula) in self.calculations {
								let columnIndex = idcs[targetColumn]!
								let inputValue: Value = row[columnIndex]
								let newValue = formula.apply(Row(row, columns: cns), foreign: nil, inputValue: inputValue)
								row[columnIndex] = newValue
							}
							return row
						}))

						callback(.success(Array(newDataset)), streamStatus)

					case .failure(let error):
						callback(.failure(error), .finished)
					}

				case .failure(let error):
					callback(.failure(error), .finished)
				}
			}
		}
	}

	private override func clone() -> Stream {
		return CalculateTransformer(source: source.clone(), calculations: calculations)
	}
}

/** The JoinTransformer can perform joins between a stream on the left side and an arbitrary data set on the right
side. For each chunk of rows from the left side (streamed), it will call filter() on the right side data set to obtain
a set that contains at least all rows necessary to join the rows in the chunk. It will then perform the join on the rows
in the chunk and stream out that result.

This is memory-efficient for joins that have a 1:1 relationship between left and right, or joins where rows from the left
side all map to the same row on the right side (m:n where m>n). It breaks down for joins where a single row on the left
side maps to a high number of rows on the right side (m:n where n>>m). However, there is no good alternative for such
joins apart from performing it in-database (which will be tried before JoinTransformer is put to work). */
private class JoinTransformer: Transformer {
	let join: Join
	private var leftColumnNames: Future<Fallible<OrderedSet<Column>>>
	private var columnNamesCached: Fallible<OrderedSet<Column>>? = nil
	private var isIneffectiveJoin: Bool = false

	init(source: Stream, join: Join) {
		self.leftColumnNames = Future(source.columns)
		self.join = join
		super.init(source: source)
	}

	private override func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
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

	private func getColumnNames(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		self.leftColumnNames.get(job) { (leftColumnsFallible) in
			switch leftColumnsFallible {
			case .success(let leftColumns):
				switch self.join.type {
				case .leftJoin, .innerJoin:
					self.join.foreignDataset.columns(job) { (rightColumnsFallible) -> () in
						switch rightColumnsFallible {
						case .success(let rightColumns):
							// Only new columns from the right side will be added
							let rightColumnsInResult = rightColumns.filter({return !leftColumns.contains($0)})
							self.isIneffectiveJoin = rightColumnsInResult.isEmpty
							callback(.success(leftColumns + rightColumnsInResult))

						case .failure(let e):
							callback(.failure(e))
						}
					}
				}

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}

	private override func clone() -> Stream {
		return JoinTransformer(source: self.source.clone(), join: self.join)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		self.leftColumnNames.get(job) { (leftColumnNamesFallible) in
			switch leftColumnNamesFallible {
			case .success(let leftColumnNames):
				// The columns function checks whether this join will actually add columns to the result.
				self.columns(job) { (columnNamesFallible) -> () in
					switch columnNamesFallible {
					case .success(_):
						// Do we have any new columns at all?
						if self.isIneffectiveJoin {
							callback(.success(rows), streamStatus)
						}
						else {
							// We need to do work
							let foreignDataset = self.join.foreignDataset
							let joinExpression = self.join.expression

							// Create a filter expression that fetches all rows that we could possibly match to our own rows
							var foreignFilters: [Expression] = []
							for row in rows {
								foreignFilters.append(joinExpression.expressionForForeignFiltering(Row(row, columns: leftColumnNames)))
							}
							let foreignFilter = Call(arguments: foreignFilters, type: Function.Or)

							// Find relevant rows from the foreign data set
							foreignDataset.filter(foreignFilter).raster(job, callback: { (foreignRasterFallible) -> () in
								switch foreignRasterFallible {
								case .success(let foreignRaster):
									// Perform the actual join using our own set of rows and the raster of possible matches from the foreign table
									let ourRaster = Raster(data: Array(rows), columns: leftColumnNames, readOnly: true)

									switch self.join.type {
									case .leftJoin:
										ourRaster.leftJoin(joinExpression, raster: foreignRaster, job: job) { (joinedRaster) in
											let joinedTuples = Array<Tuple>(joinedRaster.raster)
											callback(.success(joinedTuples), streamStatus)
										}

									case .innerJoin:
										ourRaster.innerJoin(joinExpression, raster: foreignRaster, job: job) { (joinedRaster) in
											let joinedTuples = Array<Tuple>(joinedRaster.raster)
											callback(.success(joinedTuples), streamStatus)
										}
									}

								case .failure(let e):
									callback(.failure(e), .finished)
								}
							})
						}

					case .failure(let e):
						callback(.failure(e), .finished)
					}
				}

			case .failure(let e):
				callback(.failure(e), .finished)
			}
		}
	}
}

private class AggregateTransformer: Transformer {
	let groups: OrderedDictionary<Column, Expression>
	let values: OrderedDictionary<Column, Aggregator>

	private var groupExpressions: [Expression]
	private var reducers = Catalog<Reducer>()
	private var sourceColumnNames: Future<Fallible<OrderedSet<Column>>>! = nil

	init(source: Stream, groups: OrderedDictionary<Column, Expression>, values: OrderedDictionary<Column, Aggregator>) {
		#if DEBUG
			// Check if there are duplicate target column names. If so, bail out
			for (col, _) in values {
				if groups[col] != nil {
					fatalError("Duplicate column names in aggregate are not allowed")
				}
			}

			// Check whether all aggregations can be written as a 'reducer' (then we can do streaming aggregation)
			for (_, aggregation) in values {
				if aggregation.reduce.reducer == nil {
					fatalError("Not all aggregators are reducers")
					break
				}
			}
		#endif

		self.groups = groups
		self.values = values
		self.groupExpressions = groups.map { (_, e) in return e }
		super.init(source: source)

		self.sourceColumnNames = Future<Fallible<OrderedSet<Column>>>({ [unowned self] (job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) in
			self.source.columns(job, callback: callback)
			})
	}

	convenience init(source: Stream, groups: [Column: Expression], values: [Column: Aggregator]) {
		self.init(source: source, groups: OrderedDictionary(dictionaryInAnyOrder: groups), values: OrderedDictionary(dictionaryInAnyOrder: values))
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		let reducerTemplate = self.values.mapDictionary { (c,a) in return (c, a.reduce.reducer!) }
		self.sourceColumnNames.get(job) { sourceColumnsFallible in
			switch sourceColumnsFallible {
			case .success(let sourceColumns):
				job.async {
					job.time("Stream reduce collect", items: rows.count, itemType: "rows") {
						var leafs: [Catalog<Reducer>: [Row]] = [:]

						for row in rows {
							let namedRow = Row(row, columns: sourceColumns)
							let leaf = self.reducers.leafForRow(namedRow, groups: self.groupExpressions)

							leaf.mutex.locked {
								if leaf.values == nil {
									leaf.values = reducerTemplate
								}
							}

							if leafs[leaf] == nil {
								leafs[leaf] = []
							}
							leafs[leaf]!.append(namedRow)
						}

						for (leaf, namedRows) in leafs {
							leaf.mutex.locked {
								for namedRow in namedRows {
									// Add values to the reducers
									for (column, aggregation) in self.values {
										leaf.values![column]!.add([aggregation.map.apply(namedRow, foreign: nil, inputValue: nil)])
									}
								}
							}
						}
					}

					callback(.success([]), streamStatus)
				}

			case .failure(let e):
				callback(.failure(e), .finished)
			}
		}
	}

	private override func finish(_ lastRows: Fallible<[Tuple]>, job: Job, callback: @escaping Sink) {
		// This was the last batch of inputs, call back with our sample and tell the consumer there is no more
		job.async {
			var rows: [Tuple] = []

			job.time("stream aggregate reduce", items: 1, itemType: "result") {
				self.reducers.mutex.locked {
					self.reducers.visit(block: { (path, bucket) -> () in
						rows.append(path + self.values.keys.map { k in return bucket[k]!.result })
					})
				}
			}

			callback(.success(rows), .finished)
		}
	}

	private override func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success(OrderedSet(self.groups.keys).union(with: OrderedSet(self.values.keys))))
	}

	private override func clone() -> Stream {
		return AggregateTransformer(source: source.clone(), groups: groups, values: values)
	}
}
