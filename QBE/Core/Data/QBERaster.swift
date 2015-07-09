import Foundation

internal typealias QBEFilter = (QBERaster) -> (QBERaster)

/** QBERaster represents a mutable, in-memory dataset. It is stored as a simple array of QBERow, which in turn is an array 
of QBEValue. Column names are stored separately. Each QBERow should contain the same number of values as there are columns
in the columnNames array. However, if rows are shorter, QBERaster will act as if there is a QBEValue.EmptyValue in its
place. */
class QBERaster: NSObject, CustomDebugStringConvertible, NSCoding {
	var raster: [[QBEValue]] = []
	var columnNames: [QBEColumn] = []
	let readOnly: Bool
	
	override init() {
		self.readOnly = false
	}
	
	init(data: [[QBEValue]], columnNames: [QBEColumn], readOnly: Bool = false) {
		self.raster = data
		self.columnNames = columnNames
		self.readOnly = readOnly
	}
	
	required init?(coder aDecoder: NSCoder) {
		let codedRaster = (aDecoder.decodeObjectForKey("raster") as? [[QBEValueCoder]]) ?? []
		raster = codedRaster.map({$0.map({return $0.value})})
		
		let saveColumns = aDecoder.decodeObjectForKey("columns") as? [String] ?? []
		columnNames = saveColumns.map({return QBEColumn($0)})
		readOnly = aDecoder.decodeBoolForKey("readOnly")
	}
	
	var isEmpty: Bool { get {
		return raster.count==0
	}}
	
	func encodeWithCoder(aCoder: NSCoder) {
		let saveValues = raster.map({return $0.map({return QBEValueCoder($0)})})
		aCoder.encodeObject(saveValues, forKey: "raster")
		
		let saveColumns = columnNames.map({return $0.name})
		aCoder.encodeObject(saveColumns, forKey: "columns")
		aCoder.encodeBool(readOnly, forKey: "readOnly")
	}
	
	func removeRows(set: NSIndexSet) {
		assert(!readOnly, "Data set is read-only")
		self.raster.removeObjectsAtIndexes(set, offset: 0)
	}
	
	func removeColumns(set: NSIndexSet) {
		assert(!readOnly, "Data set is read-only")
		columnNames.removeObjectsAtIndexes(set, offset: 0)
		
		for i in 0..<raster.count {
			raster[i].removeObjectsAtIndexes(set, offset: 0)
		}
	}
	
	func addRow() {
		assert(!readOnly, "Data set is read-only")
		let row = Array<QBEValue>(count: columnCount, repeatedValue: QBEValue("0"))
		raster.append(row)
	}
	
	func indexOfColumnWithName(name: QBEColumn) -> Int? {
		for i in 0..<columnNames.count {
			if columnNames[i] == name {
				return i
			}
		}
		
		return nil
	}
	
	var rowCount: Int {
		get {
			return raster.count
		}
	}
	
	var columnCount: Int {
		get {
			return columnNames.count
		}
	}
	
	subscript(row: Int, col: String) -> QBEValue? {
		return self[row, QBEColumn(col)]
	}
	
	subscript(row: Int, col: QBEColumn) -> QBEValue? {
		if let colNr = indexOfColumnWithName(col) {
			return self[row, colNr]
		}
		return nil
	}
	
	subscript(row: Int) -> [QBEValue] {
		assert(row < rowCount)
		return raster[row]
	}
	
	subscript(row: Int, col: Int) -> QBEValue {
		assert(row < rowCount)
		assert(col < columnCount)
		
		let rowData = raster[row]
		if(col >= rowData.count) {
			return QBEValue.EmptyValue
		}
		return rowData[col]
	}
	
	func setValue(value: QBEValue, forColumn: QBEColumn, inRow row: Int) {
		assert(row < self.rowCount)
		assert(!readOnly, "Data set is read-only")
		
		if let col = indexOfColumnWithName(forColumn) {
			raster[row][col] = value
		}
	}
	
	override var debugDescription: String { get {
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
	
	func compare(other: QBERaster) -> Bool {
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
	
	internal func leftJoin(expression: QBEExpression, raster rightRaster: QBERaster, job: QBEJob? = nil, callback: (QBERaster) -> ()) {
		let rightColumns = rightRaster.columnNames
		
		// Which columns are going to show up in the result set?
		let rightColumnsInResult = rightColumns.filter({return !self.columnNames.contains($0)})
		
		// If no columns from the right table will ever show up, we don't have to do the join
		if rightColumnsInResult.count == 0 {
			callback(self)
			return
		}
		
		// Create a list of indices of the columns from the right table that need to be copied over
		let rightIndicesInResult = rightColumnsInResult.map({return rightColumns.indexOf($0)! })
		let rightIndicesInResultSet = NSMutableIndexSet()
		rightIndicesInResult.each({rightIndicesInResultSet.addIndex($0)})
		
		// Start joining rows
		let joinExpression = expression.prepare()
		let templateRow = QBERow(Array<QBEValue>(count: self.columnNames.count + rightColumnsInResult.count, repeatedValue: QBEValue.InvalidValue), columnNames: self.columnNames + rightColumnsInResult)
		
		// Perform carthesian product (slow, so in parallel)
		let future = self.raster.parallel(
			map: { (chunk) -> ([QBETuple]) in
				var newData: [QBETuple] = []
				job?.time("leftJoin", items: chunk.count * rightRaster.rowCount, itemType: "pairs") {
					var myTemplateRow = templateRow
					
					for leftTuple in chunk {
						let leftRow = QBERow(leftTuple, columnNames: self.columnNames)
						var foundRightMatch = false
						
						for rightTuple in rightRaster.raster {
							let rightRow = QBERow(rightTuple, columnNames: rightColumns)
							
							if joinExpression.apply(leftRow, foreign: rightRow, inputValue: nil) == QBEValue.BoolValue(true) {
								myTemplateRow.values.removeAll(keepCapacity: true)
								myTemplateRow.values.extend(leftRow.values)
								myTemplateRow.values.extend(rightRow.values.objectsAtIndexes(rightIndicesInResultSet))
								newData.append(myTemplateRow.values)
								foundRightMatch = true
							}
						}
						
						// If there was no matching row in the right table, we need to add the left row regardless
						if !foundRightMatch {
							myTemplateRow.values.removeAll(keepCapacity: true)
							myTemplateRow.values.extend(leftRow.values)
							rightIndicesInResult.each({(Int) -> () in myTemplateRow.values.append(QBEValue.EmptyValue)})
							newData.append(myTemplateRow.values)
						}
					}
				}
				return newData
			},
			reduce: { (a: [QBETuple], b: [QBETuple]?) -> ([QBETuple]) in
				return a
			})
		
		future.get(job) { (newData: [QBETuple]?) -> () in
			callback(QBERaster(data: newData ?? [], columnNames: templateRow.columnNames, readOnly: true))
		}
	}
	
	/** Finds out whether a set of columns exists for which the indicates rows all have the same value. Returns a
	dictionary of the column names in this set, with the values for which the condition holds. */
	func commonalitiesOf(rows: NSIndexSet, inColumns columns: Set<QBEColumn>) -> [QBEColumn: QBEValue] {
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

class QBERasterData: NSObject, QBEData {
	private let future: QBEFuture<QBEFallible<QBERaster>>.Producer
	
	override init() {
		future = {(job: QBEJob, cb: QBEFuture<QBEFallible<QBERaster>>.Callback) in
			cb(.Success(QBERaster()))
		}
	}
	
	func raster(job: QBEJob, callback: (QBEFallible<QBERaster>) -> ()) {
		future(job, callback)
	}
	
	init(raster: QBERaster) {
		future = {(job, callback) in callback(.Success(raster))}
	}
	
	init(data: [[QBEValue]], columnNames: [QBEColumn]) {
		let raster = QBERaster(data: data, columnNames: columnNames)
		future = {(job, callback) in callback(.Success(raster))}
	}
	
	init(future: QBEFuture<QBEFallible<QBERaster>>.Producer) {
		self.future = future
	}
	
	func clone() -> QBEData {
		return QBERasterData(future: future)
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		raster(job, callback: { (r) -> () in
			callback(r.use({$0.columnNames}))
		})
	}
	
	internal func apply(description: String? = nil, filter: QBEFilter) -> QBEData {
		let ownFuture = self.future
		
		let newFuture = {(job: QBEJob, cb: QBEFuture<QBEFallible<QBERaster>>.Callback) -> () in
			ownFuture(job, {(fallibleRaster) in
				switch fallibleRaster {
					case .Success(let r):
						job.time(description ?? "raster apply", items: r.rowCount, itemType: "rows") {
							cb(.Success(filter(r)))
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
	
	func transpose() -> QBEData {
		return apply("transpose") {(r: QBERaster) -> QBERaster in
			// Find new column names (first column stays in place)
			if r.columnNames.count > 0 {
				var columns: [QBEColumn] = [r.columnNames[0]]
				for i in 0..<r.rowCount {
					columns.append(QBEColumn(r[i, 0].stringValue ?? ""))
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
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		return apply("selectColumns") {(r: QBERaster) -> QBERaster in
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
	
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		return fallback().calculate(calculations)
	}
	
	func unique(expression: QBEExpression, job: QBEJob, callback: (QBEFallible<Set<QBEValue>>) -> ()) {
		self.raster(job, callback: { (raster) -> () in
			callback(raster.use({(r) in Set<QBEValue>(r.raster.map({expression.apply(QBERow($0, columnNames: r.columnNames), foreign: nil, inputValue: nil)}))}))
		})
	}
	
	func limit(numberOfRows: Int) -> QBEData {
		return apply("limit") {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			let resultingNumberOfRows = min(numberOfRows, r.rowCount)
			for rowNumber in 0..<resultingNumberOfRows {
				newData.append(r[rowNumber])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func sort(by: [QBEOrder]) -> QBEData {
		return apply("sort") {(r: QBERaster) -> QBERaster in
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
			
			return QBERaster(data: newData, columnNames: columns, readOnly: true)
		}
	}

	func offset(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			let skipRows = min(numberOfRows, r.rowCount)
			for rowNumber in skipRows..<r.rowCount {
				newData.append(r[rowNumber])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func filter(condition: QBEExpression) -> QBEData {
		let optimizedCondition = condition.prepare()
		
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [QBETuple] = []
			
			for rowNumber in 0..<r.rowCount {
				let row = r[rowNumber]
				if optimizedCondition.apply(QBERow(row, columnNames: r.columnNames), foreign: nil, inputValue: nil) == QBEValue.BoolValue(true) {
					newData.append(row)
				}
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to rowColumn: QBEColumn?) -> QBEData {
		return fallback().flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: rowColumn)
	}
	
	func union(data: QBEData) -> QBEData {
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
							rowClone.extend(fillRight)
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
	
	func join(join: QBEJoin) -> QBEData {
		return applyAsynchronous("join") {(job: QBEJob, leftRaster: QBERaster, callback: (QBEFallible<QBERaster>) -> ()) in
			switch join {
			case .LeftJoin(let rightData, let expression):
				rightData.raster(job) { (rightRasterFallible) in
					switch rightRasterFallible {
						case .Success(let rightRaster):
							leftRaster.leftJoin(expression, raster: rightRaster, job: job) { (raster) in
								callback(.Success(raster))
							}
						
						case .Failure(let error):
							callback(.Failure(error))
					}
				}
			}
		}
	}
	
	func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
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
		
		return apply {(r: QBERaster) -> QBERaster in
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
					}
					else {
						currentIndex.values![column] = [result]
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
	
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		if horizontal.count == 0 {
			return self
		}
		
		return apply {(r: QBERaster) -> QBERaster in
			let horizontalIndexes = horizontal.map({r.indexOfColumnWithName($0)})
			let verticalIndexes = vertical.map({r.indexOfColumnWithName($0)})
			let valuesIndexes = values.map({r.indexOfColumnWithName($0)})
			
			var horizontalGroups: Set<QBEHashableArray<QBEValue>> = []
			var verticalGroups: Dictionary<QBEHashableArray<QBEValue>, Dictionary<QBEHashableArray<QBEValue>, [QBEValue]> > = [:]
			
			// Group all rows to horizontal and vertical groups
			r.raster.each({ (row) -> () in
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
				verticalGroup.row.each({row.append($0)})
				
				// See if this row has a value for each of the horizontal groups
				for hGroup in horizontalGroups {
					if let cellValues = horizontalCells[hGroup] {
						cellValues.each({row.append($0)})
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
			
			return QBERaster(data: rows, columnNames: newColumnNames, readOnly: true)
		}
	}
	
	func distinct() -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: Set<QBEHashableArray<QBEValue>> = []
			r.raster.each({newData.insert(QBEHashableArray<QBEValue>($0))})
			return QBERaster(data: newData.map({$0.row}), columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func random(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			/* Random selection without replacement works like this: first we assign each row a random number. Then, we 
			sort the list of row numbers by the number assigned to each row. We then take the top x of these rows. */
			var indexPairs = [Int](0..<r.rowCount).map({($0, rand())})
			indexPairs.sortInPlace({ (a, b) -> Bool in return a.1 < b.1 })
			let randomlySortedIndices = indexPairs.map({$0.0})
			let resultNumberOfRows = min(numberOfRows, r.rowCount)
			
			for rowNumber in 0..<resultNumberOfRows {
				newData.append(r[randomlySortedIndices[rowNumber]])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func stream() -> QBEStream {
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
		self.raster.get { (fallibleRaster) in
			switch fallibleRaster {
				case .Success(let raster):
					if self.position < raster.rowCount {
						let end = min(raster.rowCount, self.position + QBEStreamDefaultBatchSize)
						let rows = raster.raster[self.position..<end]
						self.position = end
						let hasNext = self.position < raster.rowCount
						job.reportProgress(Double(self.position) / Double(raster.rowCount), forKey: self.hashValue)
						consumer(.Success(rows), hasNext)
					}
					else {
						consumer(.Success([]), false)
					}
				
				case .Failure(let error):
					consumer(.Failure(error), false)
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
