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

internal typealias Filter = (Raster, Job?, Int) -> (Raster)

/** Raster represents a mutable, in-memory dataset. It is stored as a simple array of Row, which in turn is an array 
of Value. Column names are stored separately. Each Row should contain the same number of values as there are columns
in the columns array. However, if rows are shorter, Raster will act as if there is a Value.empty in its
place. 

Raster is pedantic. It will assert and cause fatal errors on misuse, e.g. if a modification attempt is made to a read-
only raster, or when a non-existent column is referenced. Users of Raster should check for these two conditions before
calling methods.

Raster data can only be modified if it was created with the `readOnly` flag set to false. Modifications are performed
serially (i.e. Raster holds a mutex) and are atomic. To make multiple changes atomically, start holding the `mutex`
before performing the first change and release it after performing the last (e.g. use raster.mutex.locked {...}). */
public class Raster: NSObject, NSCoding {
	internal var raster: [[Value]] = []
	public internal(set) var columns: OrderedSet<Column> = []

	public var rows: AnyRandomAccessCollection<Row> {
		return AnyRandomAccessCollection(self.raster.lazy.map { return Row($0, columns: self.columns) })
	}

	// FIXME: use a read-write lock to allow concurrent reads, but still provide safety
	public let mutex = Mutex()
	public let readOnly: Bool

	static let progressReportRowInterval = 512
	
	public override init() {
		self.readOnly = false
	}
	
	public init(data: [[Value]], columns: OrderedSet<Column>, readOnly: Bool = false) {
		self.raster = data
		self.columns = columns
		self.readOnly = readOnly
		super.init()

		assert(self.verify(), "raster is invalid")
	}
	
	public required init?(coder aDecoder: NSCoder) {
		let codedRaster = (aDecoder.decodeObject(forKey: "raster") as? [[ValueCoder]]) ?? []
		raster = codedRaster.map({$0.map({return $0.value})})
		
		let saveColumns = aDecoder.decodeObject(forKey: "columns") as? [String] ?? []
		columns = OrderedSet(saveColumns.map({return Column($0)}))
		readOnly = aDecoder.decodeBool(forKey: "readOnly")
	}

	public func clone(_ readOnly: Bool) -> Raster {
		return self.mutex.locked {
			return Raster(data: self.raster, columns: self.columns, readOnly: readOnly)
		}
	}

	private func verify() -> Bool {
		let columnCount = self.columns.count

		// The column names must be unique
		if Set(self.columns).count != self.columns.count {
			return false
		}

		// Each raster row must contain the same number of values
		for r in raster {
			if r.count != columnCount {
				return false
			}
		}
		return true
	}
	
	public var isEmpty: Bool {
		return self.mutex.locked {
			return raster.count==0
		}
	}
	
	public func encode(with aCoder: NSCoder) {
		self.mutex.locked {
			let saveValues = raster.map({return $0.map({return ValueCoder($0)})})
			aCoder.encode(saveValues, forKey: "raster")
			
			let saveColumns = columns.map({return $0.name})
			aCoder.encode(saveColumns, forKey: "columns")
			aCoder.encode(readOnly, forKey: "readOnly")
		}
	}
	
	public func removeRows(_ set: IndexSet) {
		self.mutex.locked {
			assert(!readOnly, "Dataset set is read-only")
			self.raster.removeObjectsAtIndexes(set, offset: 0)
		}
	}

	public func removeRows(_ keys: [[Column: Value]]) {
		self.mutex.locked {
			let keysByNumber = keys.map { key in
				return key.mapDictionary { k, v in
					return (self.indexOfColumnWithName(k)!, v)
				}
			}

			self.raster = self.raster.filter { row in
				for key in keysByNumber {
					var matches = true
					// If any key does not match, we keep the row. Otherwise it must be removed
					for (colNumber, value) in key {
						if row[colNumber] != value {
							matches = false
							break
						}
					}

					if matches {
						return false
					}
				}

				return true
			}
		}
	}
	
	public func removeColumns(_ set: IndexSet) {
		self.mutex.locked {
			assert(!readOnly, "Dataset set is read-only")
			columns.subtract(Set(set.map { return self.columns[$0] }))
			
			for i in 0..<raster.count {
				raster[i].removeObjectsAtIndexes(set, offset: 0)
			}
		}
	}

	public func addColumns(_ names: OrderedSet<Column>) {
		self.mutex.locked {
			assert(!readOnly, "Dataset set is read-only")
			let oldCount = self.columns.count
			let newColumns = names.filter { !self.columns.contains($0) }
			self.columns.append(contentsOf: newColumns)
			let template = Array<Value>(repeating: Value.empty, count: newColumns.count)

			for rowIndex in 0..<raster.count {
				let cellCount = raster[rowIndex].count
				if cellCount == oldCount {
					raster[rowIndex].append(contentsOf: template)
				}
				else if cellCount > oldCount {
					// Cut off at the old count
					var oldRow = Array(raster[rowIndex][0..<oldCount])
					oldRow.append(contentsOf: template)
					raster[rowIndex] = oldRow
				}
				else if cellCount < oldCount {
					let largerTemplate = Array<Value>(repeating: Value.empty, count: newColumns.count)
					raster[rowIndex].append(contentsOf: largerTemplate)
				}
			}
		}
	}

	public var writableCopy: Raster {
		return Raster(data: self.raster, columns: self.columns, readOnly: false)
	}

	public func addRows(_ rows: [Tuple]) {
		self.mutex.locked {
			assert(!readOnly, "Dataset set is read-only")
			self.mutex.locked {
				raster.append(contentsOf: rows)
			}
		}
	}
	
	public func addRow() {
		self.mutex.locked {
			assert(!readOnly, "Dataset set is read-only")
			let row = Array<Value>(repeating: Value.empty, count: self.columns.count)
			raster.append(row)
		}
	}
	
	public func indexOfColumnWithName(_ name: Column) -> Int? {
		return self.mutex.locked { () -> Int? in
			for i in 0..<columns.count {
				if columns[i] == name {
					return i
				}
			}
			
			return nil
		}
	}
	
	public var rowCount: Int {
		return self.mutex.locked {
			return raster.count
		}
	}
	
	public subscript(row: Int, col: String) -> Value! {
		return self.mutex.locked {
			return self[row, Column(col)]
		}
	}
	
	public subscript(row: Int, col: Column) -> Value! {
		return self.mutex.locked { () -> Value? in
			if let colNr = indexOfColumnWithName(col) {
				return self[row, colNr]
			}
			return nil
		}
	}
	
	public subscript(row: Int) -> Row {
		return self.mutex.locked {
			assert(row < rowCount)
			return Row(raster[row], columns: self.columns)
		}
	}
	
	public subscript(row: Int, col: Int) -> Value! {
		return self.mutex.locked {
			if row >= self.raster.count || col >= self.columns.count {
				return nil
			}
			
			let rowDataset = raster[row]
			if(col >= rowDataset.count) {
				return .empty
			}
			return rowDataset[col]
		}
	}

	/** Set the value in the indicated row and column. When `ifMatches` is not nil, the current value must match the 
	value of `ifMatched`, or the value will not be changed. This function returns true if the value was successfully
	changed, and false if it was not (which can only happen when ifMatches is not nil and doesn't match the current
	value). The change is made atomically. */
	public func setValue(_ value: Value, forColumn: Column, inRow row: Int, ifMatches: Value? = nil) -> Bool {
		return self.mutex.locked {
			assert(row < self.rowCount)
			assert(!readOnly, "Dataset set is read-only")
			
			if let col = indexOfColumnWithName(forColumn) {
				if ifMatches == nil || raster[row][col] == ifMatches! || (!raster[row][col].isValid && !ifMatches!.isValid) {
					raster[row][col] = value
					return true
				}
				else {
					return false
				}
			}
			else {
				fatalError("column specifed for setValue does not exist: '\(forColumn.name)'")
			}
		}
	}

	@discardableResult public func update(_ key: [Column: Value], column: Column, old: Value, new: Value) -> Int {
		return self.mutex.locked {
			var changes = 0

			let fastMapping = key.mapDictionary({ (col, value) -> (Int, Value) in
				return (self.indexOfColumnWithName(col)!, value)
			})

			let columnIndex = self.indexOfColumnWithName(column)!

			for rowIndex in  0..<rowCount {
				var row = raster[rowIndex]

				// Does this row match the key?
				var match = true
				for (colIndex, value) in fastMapping {
					if row[colIndex] != value {
						match = false
						break
					}
				}

				if !match {
					continue
				}

				if row[columnIndex] == old {
					// Old value matches, we should change it to the new value
					row[columnIndex] = new
					raster[rowIndex] = row
					changes += 1
				}
				else {
					// No change
				}
			}

			return changes
		}
	}
	
	override public var debugDescription: String {
		return self.mutex.locked {
			var d = ""
			
			var line = "\t|"
			for columnName in self.columns {
				line += columnName.name+"\t|"
			}
			d += line + "\r\n"
			
			for rowNumber in 0..<rowCount {
				var line = "\(rowNumber)\t|"
				for colNumber in 0..<self.columns.count {
					line += self[rowNumber, colNumber].debugDescription + "\t|"
				}
				d += line + "\r\n"
			}
			return d
		}
	}
	
	public func compare(_ other: Raster) -> Bool {
		return self.mutex.locked {
			// Compare row count
			if self.rowCount != other.rowCount {
				return false
			}
			
			// Compare column count
			if(self.columns.count != other.columns.count) {
				return false
			}
			
			// Compare column names
			for columnNumber in 0..<self.columns.count {
				if columns[columnNumber] != other.columns[columnNumber] {
					return false
				}
			}
			
			// Compare values
			for rowNumber in 0..<self.rowCount {
				for colNumber in 0..<self.columns.count {
					if(self[rowNumber, colNumber] != other[rowNumber, colNumber]) {
						return false
					}
				}
			}
			
			return true
		}
	}
	
	internal func innerJoin(_ expression: Expression, raster rightRaster: Raster, job: Job, callback: @escaping (Raster) -> ()) {
		self.hashOrCarthesianJoin(true, expression: expression, raster: rightRaster, job: job, callback: callback)
	}
	
	internal func leftJoin(_ expression: Expression, raster rightRaster: Raster, job: Job, callback: @escaping (Raster) -> ()) {
		self.hashOrCarthesianJoin(false, expression: expression, raster: rightRaster, job: job, callback: callback)
	}
	
	private func hashOrCarthesianJoin(_ inner: Bool, expression: Expression, raster rightRaster: Raster, job: Job, callback: @escaping (Raster) -> ()) {
		// If no columns from the right table will ever show up, we don't have to do the join
		let rightColumns = rightRaster.columns
		let rightColumnsInResult = rightColumns.filter({return !self.columns.contains($0)})
		if rightColumnsInResult.isEmpty {
			callback(self)
			return
		}
		
		if let hc = HashComparison(expression: expression), hc.comparisonOperator == Binary.equal {
			// This join can be performed as a hash join
			self.hashJoin(inner, comparison: hc, raster: rightRaster, job: job, callback: callback)
		}
		else {
			self.carthesianProduct(inner, expression: expression, raster: rightRaster, job: job, callback: callback)
		}
	}
	
	/** Performs a join of this data set with a foreign data set based on a hash comparison. The function will first 
	build a hash map that maps hash values of the comparison's rightExpression to row numbers in the right data set. It
	will then iterate over all rows in the own data table, calculate the hash, and (using the hash table) find the 
	corresponding rows on the right. While the carthesianProduct implementation needs to perform m*n comparisons, this 
	function needs to calculate m+n hashes and perform m look-ups (hash-table assumed to be log n). Performance is 
	therefore much better on larger data sets (m+n+log n compared to m*n) */
	private func hashJoin(_ inner: Bool, comparison: HashComparison, raster rightRaster: Raster, job: Job, callback: @escaping (Raster) -> ()) {
		self.mutex.locked {
			assert(comparison.comparisonOperator == Binary.equal, "hashJoin does not (yet) support hash joins based on non-equality")

			// Prepare a template row for the result
			let rightColumns = rightRaster.columns
			let rightColumnsInResult = rightColumns.filter({return !self.columns.contains($0)})
			let templateRow = Row(Array<Value>(repeating: Value.invalid, count: self.columns.count + rightColumnsInResult.count), columns: self.columns + rightColumnsInResult)
			
			// Create a list of indices of the columns from the right table that need to be copied over
			let rightIndicesInResult = rightColumnsInResult.map({return rightColumns.index(of: $0)! })
			let rightIndicesInResultSet = NSMutableIndexSet()
			rightIndicesInResult.forEach({rightIndicesInResultSet.add($0)})
			
			// Build the hash map of the foreign table
			var rightHash: [Value: [Int]] = [:]
			for rowNumber in 0..<rightRaster.raster.count {
				let row = Row(rightRaster.raster[rowNumber], columns: rightColumns)
				let hash = comparison.rightExpression.apply(row, foreign: nil, inputValue: nil)
				if let existing = rightHash[hash] {
					rightHash[hash] = existing + [rowNumber]
				}
				else {
					rightHash[hash] = [rowNumber]
				}
			}
			
			// Iterate over the rows on the left side and join rows from the right side using the hash table
			let future = self.raster.parallel(
				{ (chunk) -> ([Tuple]) in
					var newDataset: [Tuple] = []
					job.time("hashJoin", items: chunk.count, itemType: "rows") {
						var myTemplateRow = templateRow
						
						for leftTuple in chunk {
							let leftRow = Row(leftTuple, columns: self.columns)
							let hash = comparison.leftExpression.apply(leftRow, foreign: nil, inputValue: nil)
							if let rightMatches = rightHash[hash] {
								for rightRowNumber in rightMatches {
									let rightRow = Row(rightRaster.raster[rightRowNumber], columns: rightColumns)
									myTemplateRow.values.removeAll(keepingCapacity: true)
									myTemplateRow.values.append(contentsOf: leftRow.values)
									myTemplateRow.values.append(contentsOf: rightRow.values.objectsAtIndexes(rightIndicesInResultSet as IndexSet))
									newDataset.append(myTemplateRow.values)
								}
							}
							else {
								/* If there was no matching row in the right table, we need to add the left row regardless if this
								is a left (non-inner) join */
								if !inner {
									myTemplateRow.values.removeAll(keepingCapacity: true)
									myTemplateRow.values.append(contentsOf: leftRow.values)
									rightIndicesInResult.forEach({(Int) -> () in myTemplateRow.values.append(Value.empty)})
									newDataset.append(myTemplateRow.values)
								}
							}
						}
					}
					return newDataset
				},
				reduce: { (a: [Tuple], b: [Tuple]?) -> ([Tuple]) in
					if let br = b {
						return br + a
					}
					return a
			})
			
			future.get(job) { (newDataset: [Tuple]?) -> () in
				callback(Raster(data: newDataset ?? [], columns: templateRow.columns, readOnly: true))
			}
		}
	}
	
	private func carthesianProduct(_ inner: Bool, expression: Expression, raster rightRaster: Raster, job: Job, callback: @escaping (Raster) -> ()) {
		self.mutex.locked {
			// Which columns are going to show up in the result set?
			let rightColumns = rightRaster.columns
			let rightColumnsInResult = rightColumns.filter({return !self.columns.contains($0)})

			// Create a list of indices of the columns from the right table that need to be copied over
			let rightIndicesInResult = rightColumnsInResult.map({return rightColumns.index(of: $0)! })
			let rightIndicesInResultSet = NSMutableIndexSet()
			rightIndicesInResult.forEach({rightIndicesInResultSet.add($0)})
			
			// Start joining rows
			let joinExpression = expression.prepare()
			let templateRow = Row(Array<Value>(repeating: Value.invalid, count: self.columns.count + rightColumnsInResult.count), columns: self.columns + rightColumnsInResult)
			
			// Perform carthesian product (slow, so in parallel)
			let future = self.raster.parallel(
				{ (chunk) -> ([Tuple]) in
					var newDataset: [Tuple] = []
					job.time("carthesianProduct", items: chunk.count * rightRaster.rowCount, itemType: "pairs") {
						var myTemplateRow = templateRow
						
						for leftTuple in chunk {
							let leftRow = Row(leftTuple, columns: self.columns)
							var foundRightMatch = false
							
							for rightTuple in rightRaster.raster {
								let rightRow = Row(rightTuple, columns: rightColumns)
								
								if joinExpression.apply(leftRow, foreign: rightRow, inputValue: nil) == Value.bool(true) {
									myTemplateRow.values.removeAll(keepingCapacity: true)
									myTemplateRow.values.append(contentsOf: leftRow.values)
									myTemplateRow.values.append(contentsOf: rightRow.values.objectsAtIndexes(rightIndicesInResultSet as IndexSet))
									newDataset.append(myTemplateRow.values)
									foundRightMatch = true
								}
							}
							
							/* If there was no matching row in the right table, we need to add the left row regardless if this
							is a left (non-inner) join */
							if !inner && !foundRightMatch {
								myTemplateRow.values.removeAll(keepingCapacity: true)
								myTemplateRow.values.append(contentsOf: leftRow.values)
								rightIndicesInResult.forEach({(Int) -> () in myTemplateRow.values.append(Value.empty)})
								newDataset.append(myTemplateRow.values)
							}
						}
					}
					return newDataset
				},
				reduce: { (a: [Tuple], b: [Tuple]?) -> ([Tuple]) in
					if let br = b {
						return br + a
					}
					return a
				})
			
			future.get(job) { (newDataset: [Tuple]?) -> () in
				callback(Raster(data: newDataset ?? [], columns: templateRow.columns, readOnly: true))
			}
		}
	}
	
	/** Finds out whether a set of columns exists for which the indicates rows all have the same value. Returns a
	dictionary of the column names in this set, with the values for which the condition holds. */
	public func commonalitiesOf(_ rows: IndexSet, inColumns columns: Set<Column>) -> [Column: Value] {
		return self.mutex.locked {
			// Check to see if the selected rows have similar values for other than the relevant columns
			var sameValues = Dictionary<Column, Value>()
			var sameColumns = columns
			
			for index in 0..<rowCount {
				if rows.contains(index) {
					for column in columns {
						if let ci = indexOfColumnWithName(column) {
							let value = self[index][ci]
							if let previous = sameValues[column] {
								if previous != value {
									sameColumns.remove(column)
									sameValues.removeValue(forKey: column)
								}
							}
							else {
								sameValues[column] = value
							}
						}
					}
					
					if sameColumns.isEmpty {
						break
					}
				}
			}
			
			return sameValues
		}
	}
}

public class RasterDataset: NSObject, Dataset {
	private let future: Future<Fallible<Raster>>.Producer
	
	public override init() {
		future = {(job: Job, cb: Future<Fallible<Raster>>.Callback) in
			cb(.success(Raster()))
		}
	}
	
	public func raster(_ job: Job, deliver: Delivery, callback: @escaping (Fallible<Raster>, StreamStatus) -> ()) {
		switch deliver {
		case .onceComplete, .incremental:
			future(job, { r in callback(r, .finished) })
		}
	}
	
	public init(raster: Raster) {
		future = {(job, callback) in callback(.success(raster))}
	}
	
	public init(data: [[Value]], columns: OrderedSet<Column>) {
		let raster = Raster(data: data, columns: columns)
		future = {(job, callback) in callback(.success(raster))}
	}
	
	public init(future: @escaping Future<Fallible<Raster>>.Producer) {
		self.future = future
	}
	
	public func clone() -> Dataset {
		return RasterDataset(future: future)
	}
	
	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		raster(job, callback: { (r) -> () in
			callback(r.use({$0.columns}))
		})
	}
	
	internal func apply(_ description: String? = nil, filter: @escaping Filter) -> Dataset {
		let ownFuture = self.future
		
		let newFuture = {(job: Job, cb: @escaping Future<Fallible<Raster>>.Callback) -> () in
			let progressKey = Unmanaged.passUnretained(self).toOpaque().hashValue
			job.reportProgress(0.0, forKey: progressKey)

			ownFuture(job, {(fallibleRaster) in
				switch fallibleRaster {
					case .success(let r):
						job.time(description ?? "raster apply", items: r.rowCount, itemType: "rows") {
							cb(.success(filter(r, job, progressKey)))
						}
					
					case .failure(let error):
						cb(.failure(error))
				}
			})
		}
		return RasterDataset(future: newFuture)
	}
	
	internal func applyAsynchronous(_ description: String? = nil, filter: @escaping (Job, Raster, @escaping (Fallible<Raster>) -> ()) -> ()) -> Dataset {
		let newFuture = {(job: Job, cb: @escaping Future<Fallible<Raster>>.Callback) -> () in
			self.future(job) {(fallibleRaster) in
				switch fallibleRaster {
					case .success(let raster):
						job.time(description ?? "raster async apply", items: raster.rowCount, itemType: "rows") {
							filter(job, raster, cb)
							return
						}
					
					case .failure(let error):
						cb(.failure(error))
				}
			}
		}
		return RasterDataset(future: newFuture)
	}
	
	public func transpose() -> Dataset {
		return apply("transpose") {(r: Raster, job, progressKey) -> Raster in
			// Find new column names (first column stays in place)
			if r.columns.count > 0 {
				var columns: [Column] = [r.columns[0]]
				for i in 0..<r.rowCount {
					columns.append(Column(r[i, 0].stringValue ?? ""))

					if (i % Raster.progressReportRowInterval) == 0 {
						job?.reportProgress(Double(i) / Double(r.rowCount), forKey: progressKey)
						if job?.isCancelled == true {
							return Raster()
						}
					}
				}
				// FIXME: check for duplicate columns
				
				var newDataset: [[Value]] = []

				for colNumber in 1..<r.columns.count {
					let columnName = r.columns[colNumber]
					var row: [Value] = [Value(columnName.name)]
					for rowNumber in 0..<r.rowCount {
						row.append(r[rowNumber, colNumber])
					}
					newDataset.append(row)
				}
				
				return Raster(data: newDataset, columns: OrderedSet(columns), readOnly: true)
			}
			else {
				return Raster()
			}
		}
	}
	
	public func selectColumns(_ columns: OrderedSet<Column>) -> Dataset {
		return apply("selectColumns") {(r: Raster, job, progressKey) -> Raster in
			var indexesToKeep: [Int] = []
			var namesToKeep: [Column] = []
			
			for col in columns {
				if let index = r.indexOfColumnWithName(col) {
					namesToKeep.append(col)
					indexesToKeep.append(index)
				}
			}
			
			// Select columns for each row
			var newDataset: [Tuple] = []
			for rowNumber in 0..<r.rowCount {
				let oldRow = r[rowNumber]
				var newRow: Tuple = []
				for i in indexesToKeep {
					newRow.append(oldRow[i])
				}
				newDataset.append(newRow)

				if (rowNumber % Raster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.isCancelled == true {
						return Raster()
					}
				}
			}
			
			return Raster(data: newDataset, columns: OrderedSet(namesToKeep), readOnly: true)
		}
	}
	
	/** The fallback data object implements data operators not implemented here. Because RasterDataset is the fallback
	for StreamDataset and the other way around, neither should call the fallback for an operation it implements itself,
	and at least one of the classes has to implement each operation. */
	private func fallback() -> Dataset {
		return StreamDataset(source: RasterDatasetStream(self))
	}
	
	public func calculate(_ calculations: Dictionary<Column, Expression>) -> Dataset {
		return fallback().calculate(calculations)
	}
	
	public func unique(_ expression: Expression, job: Job, callback: @escaping (Fallible<Set<Value>>) -> ()) {
		self.raster(job, callback: { (raster) -> () in
			callback(raster.use({(r) in Set<Value>(r.raster.map({expression.apply(Row($0, columns: r.columns), foreign: nil, inputValue: nil)}))}))
		})
	}
	
	public func limit(_ numberOfRows: Int) -> Dataset {
		return apply("limit") {(r: Raster, job, progressKey) -> Raster in
			var newDataset: [[Value]] = []
			
			let resultingNumberOfRows = min(numberOfRows, r.rowCount)
			for rowNumber in 0..<resultingNumberOfRows {
				newDataset.append(r[rowNumber].values)
			}
			
			return Raster(data: newDataset, columns: r.columns, readOnly: true)
		}
	}
	
	public func sort(_ by: [Order]) -> Dataset {
		return apply("sort") {(r: Raster, job, progressKey) -> Raster in
			let columns = r.columns
			
			let newDataset = r.raster.sorted(by: { (a, b) -> Bool in
				// Return true if a comes before b
				for order in by {
					if let aValue = order.expression?.apply(Row(a, columns: columns), foreign: nil, inputValue: nil),
						let bValue = order.expression?.apply(Row(b, columns: columns), foreign: nil, inputValue: nil) {
						
						if order.numeric {
							if order.ascending && aValue < bValue {
								return true
							}
							else if !order.ascending && bValue < aValue {
								return true
							}
							if order.ascending && aValue > bValue {
								return false
							}
							else if !order.ascending && bValue > aValue {
								return false
							}
							else {
								// Ordered same, let next order decide
							}
						}
						else {
							if let aString = aValue.stringValue, let bString = bValue.stringValue {
								let res = aString.compare(bString)
								if res == ComparisonResult.orderedAscending {
									return order.ascending
								}
								else if res == ComparisonResult.orderedDescending {
									return !order.ascending
								}
								else {
									// Ordered same, let next order decide
								}
							}
						}
					}
				}
				return false
			})

			// FIXME: more detailed progress reporting
			job?.reportProgress(1.0, forKey: progressKey)
			return Raster(data: newDataset, columns: columns, readOnly: true)
		}
	}

	public func offset(_ numberOfRows: Int) -> Dataset {
		return apply {(r: Raster, job, progressKey) -> Raster in
			var newDataset: [[Value]] = []
			
			let skipRows = min(numberOfRows, r.rowCount)
			for rowNumber in skipRows..<r.rowCount {
				newDataset.append(r[rowNumber].values)

				if (rowNumber % Raster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.isCancelled == true {
						return Raster()
					}
				}
			}
			
			return Raster(data: newDataset, columns: r.columns, readOnly: true)
		}
	}
	
	public func filter(_ condition: Expression) -> Dataset {
		let optimizedCondition = condition.prepare()
		if optimizedCondition.isConstant {
			let constantValue = optimizedCondition.apply(Row(), foreign: nil, inputValue: nil)
			if constantValue == Value(false) {
				// Never return any rows
				return apply { (r: Raster, job, progressKey) -> Raster in
					return Raster(data: [], columns: r.columns, readOnly: true)
				}
			}
			else if constantValue == Value(true) {
				// Return all rows always
				return self
			}
		}

		return apply { (r: Raster, job, progressKey) -> Raster in
			var newDataset: [Tuple] = []
			
			for rowNumber in 0..<r.rowCount {
				let row = r[rowNumber]
				if optimizedCondition.apply(row, foreign: nil, inputValue: nil) == Value.bool(true) {
					newDataset.append(row.values)
				}

				if (rowNumber % Raster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.isCancelled == true {
						return Raster()
					}
				}
			}
			
			return Raster(data: newDataset, columns: r.columns, readOnly: true)
		}
	}
	
	public func flatten(_ valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to rowColumn: Column?) -> Dataset {
		return fallback().flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: rowColumn)
	}
	
	public func union(_ data: Dataset) -> Dataset {
		return applyAsynchronous("union") { (job: Job, leftRaster: Raster, callback: @escaping (Fallible<Raster>) -> ()) in
			data.raster(job) { rightRasterFallible in
				switch rightRasterFallible {
					case .success(let rightRaster):
						var newDataset: [Tuple] = []
						
						// Determine result raster columns
						var columns = leftRaster.columns
						for rightColumn in rightRaster.columns {
							if !columns.contains(rightColumn) {
								columns.append(rightColumn)
							}
						}
					
						// Fill in the data from the left side
						let fillRight = Array<Value>(repeating: Value.empty, count: columns.count - leftRaster.columns.count)
						for row in leftRaster.raster {
							var rowClone = row
							rowClone.append(contentsOf: fillRight)
							newDataset.append(rowClone)
						}
					
						// Fill in data from the right side
						let indices = rightRaster.columns.map({return columns.index(of: $0)})
						let empty = Array<Value>(repeating: Value.empty, count: columns.count)
						for row in rightRaster.raster {
							var rowClone = empty
							for sourceIndex in 0..<row.count {
								if let destinationIndex = indices[sourceIndex] {
									rowClone[destinationIndex] = row[sourceIndex]
								}
							}
							newDataset.append(rowClone)
						}
					
						callback(.success(Raster(data: newDataset, columns: columns)))
					
					case .failure(let error):
						callback(.failure(error))
				}
			}
		}
	}
	
	public func join(_ join: Join) -> Dataset {
		return applyAsynchronous("join") {(job: Job, leftRaster: Raster, callback: @escaping (Fallible<Raster>) -> ()) in
			join.foreignDataset.raster(job) { rightRasterFallible in
				switch rightRasterFallible {
					case .success(let rightRaster):
						switch join.type {
						case .leftJoin:
							leftRaster.leftJoin(join.expression, raster: rightRaster, job: job) { (raster) in
								callback(.success(raster))
							}
							
						case .innerJoin:
							leftRaster.innerJoin(join.expression, raster: rightRaster, job: job) { (raster) in
								callback(.success(raster))
							}
						}
					
					case .failure(let error):
						callback(.failure(error))
				}
			}
		}
	}
	
	public func aggregate(_ groups: [Column : Expression], values: [Column : Aggregator]) -> Dataset {
		return fallback().aggregate(groups, values: values)
	}
	
	public func pivot(_ horizontal: OrderedSet<Column>, vertical: OrderedSet<Column>, values: OrderedSet<Column>) -> Dataset {
		if horizontal.isEmpty {
			return self
		}
		
		return apply {(r: Raster, job, progressKey) -> Raster in
			let horizontalIndexes = horizontal.map({r.indexOfColumnWithName($0)})
			let verticalIndexes = vertical.map({r.indexOfColumnWithName($0)})
			let valuesIndexes = values.map({r.indexOfColumnWithName($0)})
			
			var horizontalGroups: Set<HashableArray<Value>> = []
			var verticalGroups: Dictionary<HashableArray<Value>, Dictionary<HashableArray<Value>, [Value]> > = [:]
			
			// Group all rows to horizontal and vertical groups
			r.raster.forEach({ (row) -> () in
				let verticalGroup = HashableArray(verticalIndexes.map({$0 == nil ? Value.invalid : row[$0!]}))
				let horizontalGroup = HashableArray(horizontalIndexes.map({$0 == nil ? Value.invalid : row[$0!]}))
				horizontalGroups.insert(horizontalGroup)
				let rowValues = valuesIndexes.map({$0 == nil ? Value.invalid : row[$0!]})
				
				if verticalGroups[verticalGroup] == nil {
					verticalGroups[verticalGroup] = [horizontalGroup: rowValues]
				}
				else {
					verticalGroups[verticalGroup]![horizontalGroup] = rowValues
				}
			})
			
			// Generate column names
			var newColumnNames: OrderedSet<Column> = vertical
			for hGroup in horizontalGroups {
				let hGroupLabel = hGroup.row.reduce("", { (label, value) -> String in
					return label + (value.stringValue ?? "") + "_"
				})
				
				for value in values {
					newColumnNames.append(Column(hGroupLabel + value.name))
				}
			}
			
			// Generate rows
			var row: [Value] = []
			var rows: [Tuple] = []
			for (verticalGroup, horizontalCells) in verticalGroups {
				// Insert vertical group labels
				verticalGroup.row.forEach({row.append($0)})
				
				// See if this row has a value for each of the horizontal groups
				for hGroup in horizontalGroups {
					if let cellValues = horizontalCells[hGroup] {
						cellValues.forEach({row.append($0)})
					}
					else {
						for _ in 0..<values.count {
							row.append(Value.invalid)
						}
					}
				}
				rows.append(row)
				row.removeAll(keepingCapacity: true)
			}

			// FIXME: more detailed progress reports
			job?.reportProgress(1.0, forKey: progressKey)
			return Raster(data: rows, columns: newColumnNames, readOnly: true)
		}
	}
	
	public func distinct() -> Dataset {
		return apply {(r: Raster, job, progressKey) -> Raster in
			var newDataset: Set<HashableArray<Value>> = []
			var rowNumber = 0
			r.raster.forEach {
				newDataset.insert(HashableArray<Value>($0))
				rowNumber += 1
				if (rowNumber % Raster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
				}
				// FIXME: check job.cancelled
			}
			// FIXME: include newDataset.map in progress reporting
			return Raster(data: newDataset.map({$0.row}), columns: r.columns, readOnly: true)
		}
	}
	
	public func random(_ numberOfRows: Int) -> Dataset {
		return fallback().random(numberOfRows)
	}
	
	public func stream() -> Stream {
		return RasterDatasetStream(self)
	}
}

public class RasterWarehouse: Warehouse {
	public let hasFixedColumns = true
	public let hasNamedTables = false

	public init() {
	}

	public func canPerformMutation(_ mutation: WarehouseMutation) -> Bool {
		switch mutation {
		case .create(_,_):
			return true
		}
	}

	public func performMutation(_ mutation: WarehouseMutation, job: Job, callback: @escaping (Fallible<MutableDataset?>) -> ()) {
		switch mutation {
		case .create(_, let data):
			data.columns(job) { result in
				switch result {
				case .success(let cns):
					let raster = Raster(data: [], columns: cns, readOnly: false)
					let mutableDataset = RasterMutableDataset(raster: raster)
					let mapping = cns.mapDictionary({ return ($0,$0) })
					mutableDataset.performMutation(.import(data: data, withMapping: mapping), job: job) { result in
						switch result {
						case .success: callback(.success(mutableDataset))
						case .failure(let e): callback(.failure(e))
						}
					}

				case .failure(let e): callback(.failure(e))
				}
			}
		}
	}
}

private class RasterInsertPuller: StreamPuller {
	let raster: Raster
	var callback: ((Fallible<Void>) -> ())?
	let fastMapping: [Int?]

	init(target: Raster, mapping: ColumnMapping, source: Stream, sourceColumns: OrderedSet<Column>, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		self.raster = target
		self.callback = callback

		self.fastMapping = self.raster.columns.map { cn -> Int? in
			if let sn = mapping[cn] {
				return sourceColumns.index(of: sn)
			}
			return nil
		}

		super.init(stream: source, job: job)
	}

	private override func onReceiveRows(_ rows: [Tuple], callback: @escaping (Fallible<Void>) -> ()) {
		let newRows = rows.map { row in
			return self.fastMapping.map { v in return v == nil ? Value.empty : row[v!] }
		}

		self.raster.addRows(newRows)
		callback(.success())
	}

	override func onDoneReceiving() {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil
			self.job.async {
				cb(.success())
			}
		}
	}

	override func onError(_ error: String) {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil

			self.job.async {
				cb(.failure(error))
			}
		}
	}
}

public class RasterMutableDataset: MutableDataset {
	let raster: Raster

	public init(raster: Raster) {
		self.raster = raster
	}

	public var warehouse: Warehouse {
		return RasterWarehouse()
	}

	public func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		callback(.success(nil))
	}

	public func canPerformMutation(_ mutation: DatasetMutation) -> Bool {
		if self.raster.readOnly {
			return false
		}

		switch mutation {
		case .truncate, .alter(_), .import(_, _), .update(_,_,_,_), .edit(row: _, column: _, old: _, new: _), .insert(_), .rename(_), .remove(rows: _), .delete(keys: _):
			return true

		case .drop:
			return false
		}
	}

	public func performMutation(_ mutation: DatasetMutation, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		switch mutation {
		case .truncate:
			self.raster.raster.removeAll()
			callback(.success())

		case .rename(let mapping):
			self.raster.columns = OrderedSet(self.raster.columns.map { cn -> Column in
				if let newName = mapping[cn] {
					return newName
				}
				return cn
			})
			callback(.success())

		case .alter(let def):
			let removedColumns = self.raster.columns.filter { return !def.columns.contains($0) }
			let addedColumns = OrderedSet(def.columns.filter { return !self.raster.columns.contains($0) })

			let removeIndices = NSMutableIndexSet()
			removedColumns.forEach { removeIndices.add(self.raster.indexOfColumnWithName($0)!) }
			self.raster.removeColumns(removeIndices as IndexSet)
			self.raster.addColumns(addedColumns)
			callback(.success())

		case .import(data: let data, withMapping: let mapping):
			let stream = data.stream()
			stream.columns(job) { result in
				switch result {
				case .success(let columns):
					let puller = RasterInsertPuller(target: self.raster, mapping: mapping, source: data.stream(), sourceColumns: columns, job: job, callback: callback)
					puller.start()

				case .failure(let e):
					callback(.failure(e))
				}
			}

		case .insert(row: let row):
			let values = raster.columns.map { cn -> Value in
				return row[cn] ?? Value.empty
			}

			raster.addRows([values])
			callback(.success())

		case .edit(row: let row, column: let column, old: let old, new: let new):
			if raster.indexOfColumnWithName(column) == nil {
				callback(.failure("Column '\(column.name)' does not exist in raster and therefore cannot be updated"))
				return
			}

			_ = raster.setValue(new, forColumn: column, inRow: row, ifMatches: old)
			callback(.success())

		case .update(key: let key, column: let column, old: let old, new: let new):
			// Do all the specified columns exist?
			if raster.indexOfColumnWithName(column) == nil {
				callback(.failure("Column '\(column.name)' does not exist in raster and therefore cannot be updated"))
				return
			}

			for (col, _) in key {
				if raster.indexOfColumnWithName(col) == nil {
					callback(.failure("Column '\(col.name)' does not exist in raster and therefore cannot be updated"))
					return
				}
			}

			raster.update(key, column: column, old: old, new: new)
			callback(.success())

		case .remove(rows: let rowNumbers):
			let indexSet = NSMutableIndexSet()
			for row in rowNumbers {
				indexSet.add(row)
			}

			raster.removeRows(indexSet as IndexSet)
			callback(.success())

		case .delete(keys: let keys):
			raster.removeRows(keys)
			callback(.success())

		case .drop:
			callback(.failure("Not supported"))
		}
	}

	public func data(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(RasterDataset(raster: self.raster)))
	}
}

/** RasterDatasetStream is a data stream that streams the contents of an in-memory raster. It is used by RasterDataset
to make use of stream-based implementations of certain operations. It is also returned by RasterDataset.stream. */
private class RasterDatasetStream: NSObject, Stream {
	let data: RasterDataset
	private var raster: Future<Fallible<Raster>>
	private var position = 0
	private let mutex = Mutex()
	
	init(_ data: RasterDataset) {
		self.data = data
		self.raster = Future({ job, callback in
			data.raster(job, callback: callback)
		})
	}
	
	fileprivate func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		self.raster.get(job) { (fallibleRaster) in
			callback(fallibleRaster.use({ return $0.columns }))
		}
	}
	
	fileprivate func clone() -> Stream {
		return RasterDatasetStream(data)
	}
	
	func fetch(_ job: Job, consumer: @escaping Sink) {
		job.reportProgress(0.0, forKey: self.hashValue)
		self.raster.get(job) { (fallibleRaster) in
			switch fallibleRaster {
				case .success(let raster):
					let (rows, hasNext) = self.mutex.locked { () -> ([Tuple], Bool) in
						let progress = raster.rowCount > 0 ? Double(self.position) / Double(raster.rowCount) : 1.0
						job.async {
							job.reportProgress(progress, forKey: self.hashValue)
						}

						if self.position < raster.rowCount {
							let end = min(raster.rowCount, self.position + StreamDefaultBatchSize)
							let rows = Array(raster.raster[self.position..<end])
							self.position = end
							let hasNext = self.position < raster.rowCount
							return (rows, hasNext)
						}
						else {
							return ([], false)
						}
					}

					consumer(.success(rows), hasNext ? .hasMore : .finished)
				
				case .failure(let error):
					consumer(.failure(error), .finished)
			}
		}
	}
}

private struct HashableArray<T: Hashable>: Hashable, Equatable {
	let row: [T]
	let hashValue: Int
	
	init(_ row: [T]) {
		self.row = row
		self.hashValue = row.reduce(0) { $0.hashValue ^ $1.hashValue }
	}
}

private func ==<T>(lhs: HashableArray<T>, rhs: HashableArray<T>) -> Bool {
	if lhs.row.count != rhs.row.count {
		return false
	}
	
	for i in 0..<lhs.row.count {
		if lhs.row[i] != rhs.row[i] {
			return false
		}
	}
	
	return true
}

/** A catalog is a tree where each node is a particular aggregation group label. The first aggregation group defines the
first level in the tree, the second group is the second level, et cetera. Values are stored at the leafs and are 'reduced' 
at the end, producing a value for each possible group label combination.

Each leaf has its own Mutex protecting the leaf from concurrent modification. By recursively obtaining a lock, parallel
work can be done on different 'branches' of the tree at the same time. **/
internal class Catalog<ValueType>: NSObject {
	let mutex = Mutex()
	var children = Dictionary<Value, Catalog<ValueType>>()
	var values: [Column: ValueType]? = nil

	final func leafForRow(_ row: Row, groups: [Expression]) -> Catalog {
		var currentCatalog = self

		for groupExpression in groups {
			let groupValue = groupExpression.apply(row, foreign: nil, inputValue: nil)

			currentCatalog.mutex.locked {
				if let nextIndex = currentCatalog.children[groupValue] {
					currentCatalog = nextIndex
				}
				else {
					let nextIndex = Catalog()
					currentCatalog.children[groupValue] = nextIndex
					currentCatalog = nextIndex
				}
			}
		}

		return currentCatalog
	}

	final func visit(_ path: [Value] = [], block: ([Value], [Column: ValueType]) -> ()) {
		self.mutex.locked {
			if let v = values {
				block(path, v)
			}
			else {
				for (val, index) in children {
					let newPath = path + [val]
					index.visit(newPath, block: block)
				}
			}
		}
	}
}
