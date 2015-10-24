import Foundation

internal typealias QBEFilter = (QBERaster, QBEJob?, Int) -> (QBERaster)

/** QBERaster represents a mutable, in-memory dataset. It is stored as a simple array of QBERow, which in turn is an array 
of QBEValue. Column names are stored separately. Each QBERow should contain the same number of values as there are columns
in the columnNames array. However, if rows are shorter, QBERaster will act as if there is a QBEValue.EmptyValue in its
place. */
public class QBERaster: NSObject, CustomDebugStringConvertible, NSCoding {
	public internal(set) var raster: [[QBEValue]] = []
	public internal(set) var columnNames: [QBEColumn] = []
	public let readOnly: Bool

	static let progressReportRowInterval = 512
	
	public override init() {
		self.readOnly = false
	}
	
	public init(data: [[QBEValue]], columnNames: [QBEColumn], readOnly: Bool = false) {
		self.raster = data
		self.columnNames = columnNames
		self.readOnly = readOnly
	}
	
	public required init?(coder aDecoder: NSCoder) {
		let codedRaster = (aDecoder.decodeObjectForKey("raster") as? [[QBEValueCoder]]) ?? []
		raster = codedRaster.map({$0.map({return $0.value})})
		
		let saveColumns = aDecoder.decodeObjectForKey("columns") as? [String] ?? []
		columnNames = saveColumns.map({return QBEColumn($0)})
		readOnly = aDecoder.decodeBoolForKey("readOnly")
	}
	
	public var isEmpty: Bool { get {
		return raster.count==0
	}}
	
	public func encodeWithCoder(aCoder: NSCoder) {
		let saveValues = raster.map({return $0.map({return QBEValueCoder($0)})})
		aCoder.encodeObject(saveValues, forKey: "raster")
		
		let saveColumns = columnNames.map({return $0.name})
		aCoder.encodeObject(saveColumns, forKey: "columns")
		aCoder.encodeBool(readOnly, forKey: "readOnly")
	}
	
	public func removeRows(set: NSIndexSet) {
		assert(!readOnly, "Data set is read-only")
		self.raster.removeObjectsAtIndexes(set, offset: 0)
	}
	
	public func removeColumns(set: NSIndexSet) {
		assert(!readOnly, "Data set is read-only")
		columnNames.removeObjectsAtIndexes(set, offset: 0)
		
		for i in 0..<raster.count {
			raster[i].removeObjectsAtIndexes(set, offset: 0)
		}
	}
	
	public func addRow() {
		assert(!readOnly, "Data set is read-only")
		let row = Array<QBEValue>(count: columnCount, repeatedValue: QBEValue("0"))
		raster.append(row)
	}
	
	public func indexOfColumnWithName(name: QBEColumn) -> Int? {
		for i in 0..<columnNames.count {
			if columnNames[i] == name {
				return i
			}
		}
		
		return nil
	}
	
	public var rowCount: Int {
		get {
			return raster.count
		}
	}
	
	public var columnCount: Int {
		get {
			return columnNames.count
		}
	}
	
	public subscript(row: Int, col: String) -> QBEValue? {
		return self[row, QBEColumn(col)]
	}
	
	public subscript(row: Int, col: QBEColumn) -> QBEValue? {
		if let colNr = indexOfColumnWithName(col) {
			return self[row, colNr]
		}
		return nil
	}
	
	public subscript(row: Int) -> [QBEValue] {
		assert(row < rowCount)
		return raster[row]
	}
	
	public subscript(row: Int, col: Int) -> QBEValue {
		assert(row < rowCount)
		assert(col < columnCount)
		
		let rowData = raster[row]
		if(col >= rowData.count) {
			return QBEValue.EmptyValue
		}
		return rowData[col]
	}
	
	public func setValue(value: QBEValue, forColumn: QBEColumn, inRow row: Int) {
		assert(row < self.rowCount)
		assert(!readOnly, "Data set is read-only")
		
		if let col = indexOfColumnWithName(forColumn) {
			raster[row][col] = value
		}
	}
	
	override public var debugDescription: String { get {
		var d = ""
		
		var line = "\t|"
		for columnName in self.columnNames {
			line += columnName.name+"\t|"
		}
		d += line + "\r\n"
		
		for rowNumber in 0..<rowCount {
			var line = "\(rowNumber)\t|"
			for colNumber in 0..<self.columnCount {
				line += self[rowNumber, colNumber].debugDescription + "\t|"
			}
			d += line + "\r\n"
		}
		return d
	} }
	
	public func compare(other: QBERaster) -> Bool {
		// Compare row count
		if self.rowCount != other.rowCount {
			return false
		}
		
		// Compare column count
		if(self.columnCount != other.columnCount) {
			return false
		}
		
		// Compare column names
		for columnNumber in 0..<self.columnCount {
			if columnNames[columnNumber] != other.columnNames[columnNumber] {
				return false
			}
		}
		
		// Compare values
		for rowNumber in 0..<self.rowCount {
			for colNumber in 0..<self.columnCount {
				if(self[rowNumber, colNumber] != other[rowNumber, colNumber]) {
					return false
				}
			}
		}
		
		return true
	}
	
	internal func innerJoin(expression: QBEExpression, raster rightRaster: QBERaster, job: QBEJob? = nil, callback: (QBERaster) -> ()) {
		self.hashOrCarthesianJoin(true, expression: expression, raster: rightRaster, job: job, callback: callback)
	}
	
	internal func leftJoin(expression: QBEExpression, raster rightRaster: QBERaster, job: QBEJob? = nil, callback: (QBERaster) -> ()) {
		self.hashOrCarthesianJoin(false, expression: expression, raster: rightRaster, job: job, callback: callback)
	}
	
	private func hashOrCarthesianJoin(inner: Bool, expression: QBEExpression, raster rightRaster: QBERaster, job: QBEJob? = nil, callback: (QBERaster) -> ()) {
		// If no columns from the right table will ever show up, we don't have to do the join
		let rightColumns = rightRaster.columnNames
		let rightColumnsInResult = rightColumns.filter({return !self.columnNames.contains($0)})
		if rightColumnsInResult.count == 0 {
			callback(self)
			return
		}
		
		if let hc = QBEHashComparison(expression: expression) where hc.comparisonOperator == QBEBinary.Equal {
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
	private func hashJoin(inner: Bool, comparison: QBEHashComparison, raster rightRaster: QBERaster, job: QBEJob? = nil, callback: (QBERaster) -> ()) {
		assert(comparison.comparisonOperator == QBEBinary.Equal, "hashJoin does not (yet) support hash joins based on non-equality")

		// Prepare a template row for the result
		let rightColumns = rightRaster.columnNames
		let rightColumnsInResult = rightColumns.filter({return !self.columnNames.contains($0)})
		let templateRow = QBERow(Array<QBEValue>(count: self.columnNames.count + rightColumnsInResult.count, repeatedValue: QBEValue.InvalidValue), columnNames: self.columnNames + rightColumnsInResult)
		
		// Create a list of indices of the columns from the right table that need to be copied over
		let rightIndicesInResult = rightColumnsInResult.map({return rightColumns.indexOf($0)! })
		let rightIndicesInResultSet = NSMutableIndexSet()
		rightIndicesInResult.forEach({rightIndicesInResultSet.addIndex($0)})
		
		// Build the hash map of the foreign table
		var rightHash: [QBEValue: [Int]] = [:]
		for rowNumber in 0..<rightRaster.raster.count {
			let row = QBERow(rightRaster.raster[rowNumber], columnNames: rightColumns)
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
			map: { (chunk) -> ([QBETuple]) in
				var newData: [QBETuple] = []
				job?.time("hashJoin", items: chunk.count, itemType: "rows") {
					var myTemplateRow = templateRow
					
					for leftTuple in chunk {
						let leftRow = QBERow(leftTuple, columnNames: self.columnNames)
						let hash = comparison.leftExpression.apply(leftRow, foreign: nil, inputValue: nil)
						if let rightMatches = rightHash[hash] {
							for rightRowNumber in rightMatches {
								let rightRow = QBERow(rightRaster.raster[rightRowNumber], columnNames: rightColumns)
								myTemplateRow.values.removeAll(keepCapacity: true)
								myTemplateRow.values.appendContentsOf(leftRow.values)
								myTemplateRow.values.appendContentsOf(rightRow.values.objectsAtIndexes(rightIndicesInResultSet))
								newData.append(myTemplateRow.values)
							}
						}
						else {
							/* If there was no matching row in the right table, we need to add the left row regardless if this
							is a left (non-inner) join */
							if !inner {
								myTemplateRow.values.removeAll(keepCapacity: true)
								myTemplateRow.values.appendContentsOf(leftRow.values)
								rightIndicesInResult.forEach({(Int) -> () in myTemplateRow.values.append(QBEValue.EmptyValue)})
								newData.append(myTemplateRow.values)
							}
						}
					}
				}
				return newData
			},
			reduce: { (a: [QBETuple], b: [QBETuple]?) -> ([QBETuple]) in
				if let br = b {
					return br + a
				}
				return a
		})
		
		future.get(job) { (newData: [QBETuple]?) -> () in
			callback(QBERaster(data: newData ?? [], columnNames: templateRow.columnNames, readOnly: true))
		}
	}
	
	private func carthesianProduct(inner: Bool, expression: QBEExpression, raster rightRaster: QBERaster, job: QBEJob? = nil, callback: (QBERaster) -> ()) {
		// Which columns are going to show up in the result set?
		let rightColumns = rightRaster.columnNames
		let rightColumnsInResult = rightColumns.filter({return !self.columnNames.contains($0)})

		// Create a list of indices of the columns from the right table that need to be copied over
		let rightIndicesInResult = rightColumnsInResult.map({return rightColumns.indexOf($0)! })
		let rightIndicesInResultSet = NSMutableIndexSet()
		rightIndicesInResult.forEach({rightIndicesInResultSet.addIndex($0)})
		
		// Start joining rows
		let joinExpression = expression.prepare()
		let templateRow = QBERow(Array<QBEValue>(count: self.columnNames.count + rightColumnsInResult.count, repeatedValue: QBEValue.InvalidValue), columnNames: self.columnNames + rightColumnsInResult)
		
		// Perform carthesian product (slow, so in parallel)
		let future = self.raster.parallel(
			map: { (chunk) -> ([QBETuple]) in
				var newData: [QBETuple] = []
				job?.time("carthesianProduct", items: chunk.count * rightRaster.rowCount, itemType: "pairs") {
					var myTemplateRow = templateRow
					
					for leftTuple in chunk {
						let leftRow = QBERow(leftTuple, columnNames: self.columnNames)
						var foundRightMatch = false
						
						for rightTuple in rightRaster.raster {
							let rightRow = QBERow(rightTuple, columnNames: rightColumns)
							
							if joinExpression.apply(leftRow, foreign: rightRow, inputValue: nil) == QBEValue.BoolValue(true) {
								myTemplateRow.values.removeAll(keepCapacity: true)
								myTemplateRow.values.appendContentsOf(leftRow.values)
								myTemplateRow.values.appendContentsOf(rightRow.values.objectsAtIndexes(rightIndicesInResultSet))
								newData.append(myTemplateRow.values)
								foundRightMatch = true
							}
						}
						
						/* If there was no matching row in the right table, we need to add the left row regardless if this
						is a left (non-inner) join */
						if !inner && !foundRightMatch {
							myTemplateRow.values.removeAll(keepCapacity: true)
							myTemplateRow.values.appendContentsOf(leftRow.values)
							rightIndicesInResult.forEach({(Int) -> () in myTemplateRow.values.append(QBEValue.EmptyValue)})
							newData.append(myTemplateRow.values)
						}
					}
				}
				return newData
			},
			reduce: { (a: [QBETuple], b: [QBETuple]?) -> ([QBETuple]) in
				if let br = b {
					return br + a
				}
				return a
			})
		
		future.get(job) { (newData: [QBETuple]?) -> () in
			callback(QBERaster(data: newData ?? [], columnNames: templateRow.columnNames, readOnly: true))
		}
	}
	
	/** Finds out whether a set of columns exists for which the indicates rows all have the same value. Returns a
	dictionary of the column names in this set, with the values for which the condition holds. */
	public func commonalitiesOf(rows: NSIndexSet, inColumns columns: Set<QBEColumn>) -> [QBEColumn: QBEValue] {
		// Check to see if the selected rows have similar values for other than the relevant columns
		var sameValues = Dictionary<QBEColumn, QBEValue>()
		var sameColumns = columns
		
		for index in 0..<rowCount {
			if rows.containsIndex(index) {
				for column in columns {
					if let ci = indexOfColumnWithName(column) {
						let value = self[index][ci]
						if let previous = sameValues[column] {
							if previous != value {
								sameColumns.remove(column)
								sameValues.removeValueForKey(column)
							}
						}
						else {
							sameValues[column] = value
						}
					}
				}
				
				if sameColumns.count == 0 {
					break
				}
			}
		}
		
		return sameValues
	}
}

public class QBERasterData: NSObject, QBEData {
	private let future: QBEFuture<QBEFallible<QBERaster>>.Producer
	
	override init() {
		future = {(job: QBEJob, cb: QBEFuture<QBEFallible<QBERaster>>.Callback) in
			cb(.Success(QBERaster()))
		}
	}
	
	public func raster(job: QBEJob, callback: (QBEFallible<QBERaster>) -> ()) {
		future(job, callback)
	}
	
	public init(raster: QBERaster) {
		future = {(job, callback) in callback(.Success(raster))}
	}
	
	public init(data: [[QBEValue]], columnNames: [QBEColumn]) {
		let raster = QBERaster(data: data, columnNames: columnNames)
		future = {(job, callback) in callback(.Success(raster))}
	}
	
	public init(future: QBEFuture<QBEFallible<QBERaster>>.Producer) {
		self.future = future
	}
	
	public func clone() -> QBEData {
		return QBERasterData(future: future)
	}
	
	public func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		raster(job, callback: { (r) -> () in
			callback(r.use({$0.columnNames}))
		})
	}
	
	internal func apply(description: String? = nil, filter: QBEFilter) -> QBEData {
		let ownFuture = self.future
		
		let newFuture = {(job: QBEJob, cb: QBEFuture<QBEFallible<QBERaster>>.Callback) -> () in
			let progressKey = unsafeAddressOf(self).hashValue
			job.reportProgress(0.0, forKey: progressKey)

			ownFuture(job, {(fallibleRaster) in
				switch fallibleRaster {
					case .Success(let r):
						job.time(description ?? "raster apply", items: r.rowCount, itemType: "rows") {
							cb(.Success(filter(r, job, progressKey)))
						}
					
					case .Failure(let error):
						cb(.Failure(error))
				}
			})
		}
		return QBERasterData(future: newFuture)
	}
	
	internal func applyAsynchronous(description: String? = nil, filter: (QBEJob, QBERaster, (QBEFallible<QBERaster>) -> ()) -> ()) -> QBEData {
		let newFuture = {(job: QBEJob, cb: QBEFuture<QBEFallible<QBERaster>>.Callback) -> () in
			self.future(job) {(fallibleRaster) in
				switch fallibleRaster {
					case .Success(let raster):
						job.time(description ?? "raster async apply", items: raster.rowCount, itemType: "rows") {
							filter(job, raster, cb)
							return
						}
					
					case .Failure(let error):
						cb(.Failure(error))
				}
			}
		}
		return QBERasterData(future: newFuture)
	}
	
	public func transpose() -> QBEData {
		return apply("transpose") {(r: QBERaster, job, progressKey) -> QBERaster in
			// Find new column names (first column stays in place)
			if r.columnNames.count > 0 {
				var columns: [QBEColumn] = [r.columnNames[0]]
				for i in 0..<r.rowCount {
					columns.append(QBEColumn(r[i, 0].stringValue ?? ""))

					if (i % QBERaster.progressReportRowInterval) == 0 {
						job?.reportProgress(Double(i) / Double(r.rowCount), forKey: progressKey)
						if job?.cancelled == true {
							return QBERaster()
						}
					}
				}
				
				var newData: [[QBEValue]] = []
				
				let columnNames = r.columnNames
				for colNumber in 1..<r.columnCount {
					let columnName = columnNames[colNumber];
					var row: [QBEValue] = [QBEValue(columnName.name)]
					for rowNumber in 0..<r.rowCount {
						row.append(r[rowNumber, colNumber])
					}
					newData.append(row)
				}
				
				return QBERaster(data: newData, columnNames: columns, readOnly: true)
			}
			else {
				return QBERaster()
			}
		}
	}
	
	public func selectColumns(columns: [QBEColumn]) -> QBEData {
		return apply("selectColumns") {(r: QBERaster, job, progressKey) -> QBERaster in
			var indexesToKeep: [Int] = []
			var namesToKeep: [QBEColumn] = []
			
			for col in columns {
				if let index = r.indexOfColumnWithName(col) {
					namesToKeep.append(col)
					indexesToKeep.append(index)
				}
			}
			
			// Select columns for each row
			var newData: [QBETuple] = []
			for rowNumber in 0..<r.rowCount {
				var oldRow = r[rowNumber]
				var newRow: QBETuple = []
				for i in indexesToKeep {
					newRow.append(oldRow[i])
				}
				newData.append(newRow)

				if (rowNumber % QBERaster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.cancelled == true {
						return QBERaster()
					}
				}
			}
			
			return QBERaster(data: newData, columnNames: namesToKeep, readOnly: true)
		}
	}
	
	/** The fallback data object implements data operators not implemented here. Because QBERasterData is the fallback
	for QBEStreamData and the other way around, neither should call the fallback for an operation it implements itself,
	and at least one of the classes has to implement each operation. */
	private func fallback() -> QBEData {
		return QBEStreamData(source: QBERasterDataStream(self))
	}
	
	public func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		return fallback().calculate(calculations)
	}
	
	public func unique(expression: QBEExpression, job: QBEJob, callback: (QBEFallible<Set<QBEValue>>) -> ()) {
		self.raster(job, callback: { (raster) -> () in
			callback(raster.use({(r) in Set<QBEValue>(r.raster.map({expression.apply(QBERow($0, columnNames: r.columnNames), foreign: nil, inputValue: nil)}))}))
		})
	}
	
	public func limit(numberOfRows: Int) -> QBEData {
		return apply("limit") {(r: QBERaster, job, progressKey) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			let resultingNumberOfRows = min(numberOfRows, r.rowCount)
			for rowNumber in 0..<resultingNumberOfRows {
				newData.append(r[rowNumber])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	public func sort(by: [QBEOrder]) -> QBEData {
		return apply("sort") {(r: QBERaster, job, progressKey) -> QBERaster in
			let columns = r.columnNames
			
			let newData = r.raster.sort({ (a, b) -> Bool in
				// Return true if a comes before b
				for order in by {
					if let aValue = order.expression?.apply(QBERow(a, columnNames: columns), foreign: nil, inputValue: nil),
						let bValue = order.expression?.apply(QBERow(b, columnNames: columns), foreign: nil, inputValue: nil) {
						
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
								if res == NSComparisonResult.OrderedAscending {
									return order.ascending
								}
								else if res == NSComparisonResult.OrderedDescending {
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
			return QBERaster(data: newData, columnNames: columns, readOnly: true)
		}
	}

	public func offset(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster, job, progressKey) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			let skipRows = min(numberOfRows, r.rowCount)
			for rowNumber in skipRows..<r.rowCount {
				newData.append(r[rowNumber])

				if (rowNumber % QBERaster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.cancelled == true {
						return QBERaster()
					}
				}
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	public func filter(condition: QBEExpression) -> QBEData {
		let optimizedCondition = condition.prepare()
		
		return apply {(r: QBERaster, job, progressKey) -> QBERaster in
			var newData: [QBETuple] = []
			
			for rowNumber in 0..<r.rowCount {
				let row = r[rowNumber]
				if optimizedCondition.apply(QBERow(row, columnNames: r.columnNames), foreign: nil, inputValue: nil) == QBEValue.BoolValue(true) {
					newData.append(row)
				}

				if (rowNumber % QBERaster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.cancelled == true {
						return QBERaster()
					}
				}
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	public func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to rowColumn: QBEColumn?) -> QBEData {
		return fallback().flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: rowColumn)
	}
	
	public func union(data: QBEData) -> QBEData {
		return applyAsynchronous("union") {(job: QBEJob, leftRaster: QBERaster, callback: (QBEFallible<QBERaster>) -> ()) in
			data.raster(job) { (rightRasterFallible) in
				switch rightRasterFallible {
					case .Success(let rightRaster):
						var newData: [QBETuple] = []
						
						// Determine result raster columns
						var columns = leftRaster.columnNames
						for rightColumn in rightRaster.columnNames {
							if !columns.contains(rightColumn) {
								columns.append(rightColumn)
							}
						}
					
						// Fill in the data from the left side
						let fillRight = Array<QBEValue>(count: columns.count - leftRaster.columnCount, repeatedValue: QBEValue.EmptyValue)
						for row in leftRaster.raster {
							var rowClone = row
							rowClone.appendContentsOf(fillRight)
							newData.append(rowClone)
						}
					
						// Fill in data from the right side
						let indices = rightRaster.columnNames.map({return columns.indexOf($0)})
						let empty = Array<QBEValue>(count: columns.count, repeatedValue: QBEValue.EmptyValue)
						for row in rightRaster.raster {
							var rowClone = empty
							for sourceIndex in 0..<row.count {
								if let destinationIndex = indices[sourceIndex] {
									rowClone[destinationIndex] = row[sourceIndex]
								}
							}
							newData.append(rowClone)
						}
					
						callback(.Success(QBERaster(data: newData, columnNames: columns)))
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			}
		}
	}
	
	public func join(join: QBEJoin) -> QBEData {
		return applyAsynchronous("join") {(job: QBEJob, leftRaster: QBERaster, callback: (QBEFallible<QBERaster>) -> ()) in
			join.foreignData.raster(job) { (rightRasterFallible) in
				switch rightRasterFallible {
					case .Success(let rightRaster):
						switch join.type {
						case .LeftJoin:
							leftRaster.leftJoin(join.expression, raster: rightRaster, job: job) { (raster) in
								callback(.Success(raster))
							}
							
						case .InnerJoin:
							leftRaster.innerJoin(join.expression, raster: rightRaster, job: job) { (raster) in
								callback(.Success(raster))
							}
						}
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			}
		}
	}
	
	public func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
		/* This implementation is fairly naive and simply generates a tree where each node is a particular aggregation
		group label. The first aggregation group defines the first level in the tree, the second group is the second
		level, et cetera. Values are stored at the leafs and are 'reduced' at the end, producing a value for each 
		possible group label combination. */
		class QBEIndex {
			var children = Dictionary<QBEValue, QBEIndex>()
			var values: [QBEColumn: [QBEValue]]? = nil
			
			func reduce(aggregations: [QBEColumn : QBEAggregation], row: [QBEValue] = [], callback: ([QBEValue]) -> ()) {
				if values != nil {
					var newRow = row
					for (column, aggregation) in aggregations {
						newRow.append(aggregation.reduce.apply(values![column] ?? []))
					}
					callback(newRow)
				}
				else {
					for (val, index) in children {
						var newRow = row
						newRow.append(val)
						index.reduce(aggregations, row: newRow, callback: callback)
					}
				}
			}
		}
		
		#if DEBUG
		// Check if there are duplicate target column names. If so, bail out
		for (col, _) in values {
			if groups[col] != nil {
				fatalError("Duplicate column names in QBERasterData.aggregate are not allowed")
			}
		}
		#endif
		
		return apply("raster aggregate") {(r: QBERaster, job, progressKey) -> QBERaster in
			let index = QBEIndex()
			
			for rowNumber in 0..<r.rowCount {
				let row = r[rowNumber]
				
				// Calculate group values
				var currentIndex = index
				for (_, groupExpression) in groups {
					let groupValue = groupExpression.apply(QBERow(row, columnNames: r.columnNames), foreign: nil, inputValue: nil)
					
					if let nextIndex = currentIndex.children[groupValue] {
						currentIndex = nextIndex
					}
					else {
						let nextIndex = QBEIndex()
						currentIndex.children[groupValue] = nextIndex
						currentIndex = nextIndex
					}
				}
				
				// Calculate values
				if currentIndex.values == nil {
					currentIndex.values = Dictionary<QBEColumn, [QBEValue]>()
				}
				
				for (column, value) in values {
					let result = value.map.apply(QBERow(row, columnNames: r.columnNames), foreign: nil, inputValue: nil)
					if var bag = currentIndex.values![column] {
						bag.append(result)
						currentIndex.values![column] = bag
					}
					else {
						currentIndex.values![column] = [result]
					}
				}

				// Report progress
				if (rowNumber % QBERaster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.cancelled == true {
						return QBERaster()
					}
				}
			}

			// Generate output raster and column headers
			var headers: [QBEColumn] = []
			for (columnName, _) in groups {
				headers.append(columnName)
			}
			
			for (columnName, _) in values {
				headers.append(columnName)
			}
			var newRaster: [[QBEValue]] = []
			
			// Time to aggregate
			index.reduce(values, callback: {newRaster.append($0)})
			return QBERaster(data: newRaster, columnNames: headers, readOnly: true)
		}
	}
	
	public func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		if horizontal.count == 0 {
			return self
		}
		
		return apply {(r: QBERaster, job, progressKey) -> QBERaster in
			let horizontalIndexes = horizontal.map({r.indexOfColumnWithName($0)})
			let verticalIndexes = vertical.map({r.indexOfColumnWithName($0)})
			let valuesIndexes = values.map({r.indexOfColumnWithName($0)})
			
			var horizontalGroups: Set<QBEHashableArray<QBEValue>> = []
			var verticalGroups: Dictionary<QBEHashableArray<QBEValue>, Dictionary<QBEHashableArray<QBEValue>, [QBEValue]> > = [:]
			
			// Group all rows to horizontal and vertical groups
			r.raster.forEach({ (row) -> () in
				let verticalGroup = QBEHashableArray(verticalIndexes.map({$0 == nil ? QBEValue.InvalidValue : row[$0!]}))
				let horizontalGroup = QBEHashableArray(horizontalIndexes.map({$0 == nil ? QBEValue.InvalidValue : row[$0!]}))
				horizontalGroups.insert(horizontalGroup)
				let rowValues = valuesIndexes.map({$0 == nil ? QBEValue.InvalidValue : row[$0!]})
				
				if verticalGroups[verticalGroup] == nil {
					verticalGroups[verticalGroup] = [horizontalGroup: rowValues]
				}
				else {
					verticalGroups[verticalGroup]![horizontalGroup] = rowValues
				}
			})
			
			// Generate column names
			var newColumnNames: [QBEColumn] = vertical
			for hGroup in horizontalGroups {
				let hGroupLabel = hGroup.row.reduce("", combine: { (label, value) -> String in
					return label + (value.stringValue ?? "") + "_"
				})
				
				for value in values {
					newColumnNames.append(QBEColumn(hGroupLabel + value.name))
				}
			}
			
			// Generate rows
			var row: [QBEValue] = []
			var rows: [QBETuple] = []
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
							row.append(QBEValue.InvalidValue)
						}
					}
				}
				rows.append(row)
				row.removeAll(keepCapacity: true)
			}

			// FIXME: more detailed progress reports
			job?.reportProgress(1.0, forKey: progressKey)
			return QBERaster(data: rows, columnNames: newColumnNames, readOnly: true)
		}
	}
	
	public func distinct() -> QBEData {
		return apply {(r: QBERaster, job, progressKey) -> QBERaster in
			var newData: Set<QBEHashableArray<QBEValue>> = []
			var rowNumber = 0
			r.raster.forEach {
				newData.insert(QBEHashableArray<QBEValue>($0))
				rowNumber++
				if (rowNumber % QBERaster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
				}
				// FIXME: check job.cancelled
			}
			// FIXME: include newData.map in progress reporting
			return QBERaster(data: newData.map({$0.row}), columnNames: r.columnNames, readOnly: true)
		}
	}
	
	public func random(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster, job, progressKey) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			/* Random selection without replacement works like this: first we assign each row a random number. Then, we 
			sort the list of row numbers by the number assigned to each row. We then take the top x of these rows. */
			var indexPairs = [Int](0..<r.rowCount).map({($0, rand())})
			indexPairs.sortInPlace({ (a, b) -> Bool in return a.1 < b.1 })
			let randomlySortedIndices = indexPairs.map({$0.0})
			let resultNumberOfRows = min(numberOfRows, r.rowCount)
			
			for rowNumber in 0..<resultNumberOfRows {
				newData.append(r[randomlySortedIndices[rowNumber]])

				if (rowNumber % QBERaster.progressReportRowInterval) == 0 {
					job?.reportProgress(Double(rowNumber) / Double(r.rowCount), forKey: progressKey)
					if job?.cancelled == true {
						return QBERaster()
					}
				}
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	public func stream() -> QBEStream {
		return QBERasterDataStream(self)
	}
}

/** QBERasterDataStream is a data stream that streams the contents of an in-memory raster. It is used by QBERasterData
to make use of stream-based implementations of certain operations. It is also returned by QBERasterData.stream. */
private class QBERasterDataStream: NSObject, QBEStream {
	let data: QBERasterData
	private var raster: QBEFuture<QBEFallible<QBERaster>>
	private var position = 0
	
	init(_ data: QBERasterData) {
		self.data = data
		self.raster = QBEFuture(data.raster)
	}
	
	private func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		self.raster.get { (fallibleRaster) in
			callback(fallibleRaster.use({ return $0.columnNames }))
		}
	}
	
	private func clone() -> QBEStream {
		return QBERasterDataStream(data)
	}
	
	func fetch(job: QBEJob, consumer: QBESink) {
		job.reportProgress(0.0, forKey: self.hashValue)
		self.raster.get { (fallibleRaster) in
			switch fallibleRaster {
				case .Success(let raster):
					if self.position < raster.rowCount {
						let end = min(raster.rowCount, self.position + QBEStreamDefaultBatchSize)
						let rows = Array(raster.raster[self.position..<end])
						self.position = end
						let hasNext = self.position < raster.rowCount
						job.reportProgress(Double(self.position) / Double(raster.rowCount), forKey: self.hashValue)
						consumer(.Success(rows), hasNext ? .HasMore : .Finished)
					}
					else {
						consumer(.Success([]), .Finished)
					}
				
				case .Failure(let error):
					consumer(.Failure(error), .Finished)
			}
		}
	}
}

private struct QBEHashableArray<T: Hashable>: Hashable, Equatable {
	let row: [T]
	let hashValue: Int
	
	init(_ row: [T]) {
		self.row = row
		self.hashValue = row.reduce(0) { $0.hashValue ^ $1.hashValue }
	}
}

private func ==<T>(lhs: QBEHashableArray<T>, rhs: QBEHashableArray<T>) -> Bool {
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
