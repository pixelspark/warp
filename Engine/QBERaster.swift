import Foundation

internal typealias QBEFilter = (QBERaster) -> (QBERaster)

/** QBERaster represents a mutable, in-memory dataset. It is stored as a simple array of QBERow, which in turn is an array 
of QBEValue. Column names are stored separately. Each QBERow should contain the same number of values as there are columns
in the columnNames array. However, if rows are shorter, QBERaster will act as if there is a QBEValue.EmptyValue in its
place. **/
class QBERaster: DebugPrintable {
	var raster: [[QBEValue]] = []
	var columnNames: [QBEColumn] = []
	let readOnly: Bool = false
	
	init() {
	}
	
	init(data: [[QBEValue]], columnNames: [QBEColumn], readOnly: Bool = false) {
		self.raster = data
		self.columnNames = columnNames
		self.readOnly = readOnly
	}
	
	var isEmpty: Bool { get {
		return raster.count==0
	}}
	
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
		var row = Array<QBEValue>(count: columnCount, repeatedValue: QBEValue("0"))
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
	
	var debugDescription: String { get {
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
}

typealias QBERasterCallback = (QBERaster) -> ()
typealias QBERasterFuture = (QBERasterCallback) -> ()

class QBERasterData: NSObject, QBEData {
	private let future: QBERasterFuture
	
	override init() {
		future = {(cb: QBERasterCallback) in
			cb(QBERaster())
		}
	}
	
	func raster(callback: (QBERaster) -> ()) {
		future(callback)
	}
	
	init(raster: QBERaster) {
		future = {$0(raster)}
	}
	
	init(data: [[QBEValue]], columnNames: [QBEColumn]) {
		let raster = QBERaster(data: data, columnNames: columnNames)
		future = {$0(raster)}
	}
	
	init(future: QBERasterFuture) {
		self.future = future
	}
	
	func clone() -> QBEData {
		return QBERasterData(future: future)
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		raster { (r) -> () in
			callback(r.columnNames)
		}
	}
	
	internal func apply(filter: QBEFilter) -> QBEData {
		let newFuture = {(cb: QBERasterCallback) -> () in
			let transformer = {cb(filter($0))}
			self.future({transformer($0)})
		}
		return QBERasterData(future: newFuture)
	}
	
	func transpose() -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			// Find new column names (first column stays in place)
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
	}
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var indexesToKeep: [Int] = []
			var namesToKeep: [QBEColumn] = []
			
			for col in columns {
				if let index = r.indexOfColumnWithName(col) {
					namesToKeep.append(col)
					indexesToKeep.append(index)
				}
			}
			
			// Select columns for each row
			var newData: [QBERow] = []
			for rowNumber in 0..<r.rowCount {
				var oldRow = r[rowNumber]
				var newRow: [QBEValue] = []
				for i in indexesToKeep {
					newRow.append(oldRow[i])
				}
				newData.append(newRow)
			}
			
			return QBERaster(data: newData, columnNames: namesToKeep, readOnly: true)
		}
	}
	
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		return QBEStreamData(source: QBERasterDataStream(self)).calculate(calculations)
	}
	
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) {
		self.raster { (raster) -> () in
			let values = Set<QBEValue>(raster.raster.map({expression.apply($0, columns: raster.columnNames, inputValue: nil)}))
			callback(values)
		}
	}
	
	func limit(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			let resultingNumberOfRows = min(numberOfRows, r.rowCount)
			for rowNumber in 0..<resultingNumberOfRows {
				newData.append(r[rowNumber])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
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
			
			func reduce(aggregations: [QBEColumn : QBEAggregation], callback: ([QBEValue]) -> (), row: [QBEValue] = []) {
				if values != nil {
					var result = Dictionary<QBEColumn, QBEValue>()
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
						index.reduce(aggregations, callback: callback, row: newRow)
					}
				}
			}
		}
		
		return apply {(r: QBERaster) -> QBERaster in
			let index = QBEIndex()
			
			for rowNumber in 0..<r.rowCount {
				let row = r[rowNumber]
				
				// Calculate group values
				var currentIndex = index
				for (groupColumn, groupExpression) in groups {
					let groupValue = groupExpression.apply(row, columns: r.columnNames, inputValue: nil)
					
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
					let result = value.map.apply(row, columns: r.columnNames, inputValue: nil)
					if let bag = currentIndex.values![column] {
						currentIndex.values![column]!.append(result)
					}
					else {
						currentIndex.values![column] = [result]
					}
				}
			}

			// Generate output raster and column headers
			var headers: [QBEColumn] = []
			for (columnName, expression) in groups {
				headers.append(columnName)
			}
			
			for (columnName, aggregation) in values {
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
				horizontalGroups.add(horizontalGroup)
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
			var rows: [QBERow] = []
			for (verticalGroup, horizontalCells) in verticalGroups {
				// Insert vertical group labels
				verticalGroup.row.each({row.append($0)})
				
				// See if this row has a value for each of the horizontal groups
				for hGroup in horizontalGroups {
					if let cellValues = horizontalCells[hGroup] {
						cellValues.each({row.append($0)})
					}
					else {
						for c in 0..<values.count {
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
			r.raster.each({newData.add(QBEHashableArray<QBEValue>($0))})
			return QBERaster(data: newData.elements.map({$0.row}), columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func random(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			/* Random selection without replacement works like this: first we assign each row a random number. Then, we 
			sort the list of row numbers by the number assigned to each row. We then take the top x of these rows. */
			let numberOfSourceRows = r.rowCount
			var indexPairs = [Int](0..<r.rowCount).map({($0, rand())})
			indexPairs.sort({ (a, b) -> Bool in return a.1 < b.1 })
			let randomlySortedIndices = indexPairs.map({$0.0})
			let resultNumberOfRows = min(numberOfRows, r.rowCount)
			
			for rowNumber in 0..<resultNumberOfRows {
				newData.append(r[randomlySortedIndices[rowNumber]])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func stream() -> QBEStream? {
		return QBERasterDataStream(self)
	}
}

/** QBERasterDataStream is a data stream that streams the contents of an in-memory raster. It is used by QBERasterData
to make use of stream-based implementations of certain operations. It is also returned by QBERasterData.stream. **/
private class QBERasterDataStream: NSObject, QBEStream {
	let data: QBERasterData
	private var raster: QBERaster?
	private var position = 0
	
	init(_ data: QBERasterData) {
		self.data = data
	}
	
	private func columnNames(callback: ([QBEColumn]) -> ()) {
		if let cn = raster?.columnNames {
			callback(cn)
		}
	}
	
	private func clone() -> QBEStream {
		return QBERasterDataStream(data)
	}
	
	func fetch(consumer: QBESink) {
		if raster == nil {
			data.raster({ (r) -> () in
				self.raster = r
				self.fetch(consumer)
			})
		}
		else {
			if position < raster!.rowCount {
				let end = min(raster!.rowCount, self.position + QBEStreamDefaultBatchSize)
				let rows = raster!.raster[self.position..<end]
				self.position = end
				let hasNext = self.position < self.raster!.rowCount
				consumer(rows, hasNext)
			}
			else {
				consumer([], false)
			}
		}
	}
}

private struct QBEHashableArray<T: Hashable>: Hashable, Equatable {
	let row: [T]
	let hashValue: Int
	
	init(_ row: [T]) {
		self.row = row
		self.hashValue = reduce(row, 0) { $0.hashValue ^ $1.hashValue }
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
