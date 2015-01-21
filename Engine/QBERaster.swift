import Foundation

internal typealias QBEFilter = (QBERaster) -> (QBERaster)

class QBERaster: DebugPrintable {
	var raster: [[QBEValue]]
	var columnNames: [QBEColumn]
	
	var readOnly: Bool
	
	init() {
		raster = []
		columnNames = []
		readOnly = false
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
		if readOnly {
			fatalError("Raster is read-only")
		}
		raster.removeObjectsAtIndexes(set, offset: 0)
	}
	
	func removeColumns(set: NSIndexSet) {
		if readOnly {
			fatalError("Raster is read-only")
		}
		
		columnNames.removeObjectsAtIndexes(set, offset: 0)
		
		for i in 0..<raster.count {
			raster[i].removeObjectsAtIndexes(set, offset: 0)
		}
	}
	
	func addRow() {
		if readOnly {
			fatalError("Raster is read-only")
		}
		
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
		if(col > rowData.count) {
			fatalError("Encountered a QBERaster row that does not contain the prescribed amount of cells")
		}
		return rowData[col]
	}
	
	func setValue(value: QBEValue, forColumn: QBEColumn, inRow row: Int) {
		assert(row < self.rowCount)
		
		if readOnly {
			fatalError("Raster is read-only")
		}
		
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


class QBERasterData: NSObject, QBEData, NSCoding, DebugPrintable {
	private(set) var raster: QBEFuture
	
	override init() {
		raster = memoize {
			return QBERaster()
		}
	}
	
	required init(coder: NSCoder) {
		let codedRaster = coder.decodeObjectForKey("data") as? [[QBEValueCoder]] ?? []
		let codedColumns = coder.decodeObjectForKey("columns") as? [String] ?? []
		
		// The raster is stored as [[QBEValueCoder]], but needs to be a [[QBEValue]]. Lazily decode it
		raster = memoize {
			return QBERaster(
				data: codedRaster.map({$0.map({$0.value})}),
				columnNames: codedColumns.map({QBEColumn($0)})
			)
		}
	}
	
	init(raster: QBERaster) {
		self.raster = memoize {
			return raster
		}
	}
	
	init(raster: QBEFuture) {
		self.raster = raster
	}
	
	init(data: [[QBEValue]], columnNames: [QBEColumn]) {
		raster = memoize {
			return QBERaster(data: data, columnNames: columnNames)
		}
	}
	
	internal init(_ r: QBEFuture) {
		raster = r
	}
	
	func clone() -> QBEData {
		return QBERasterData(raster)
	}
	
	var isEmpty: Bool { get {
		return raster().isEmpty
		}}
	
	func encodeWithCoder(coder: NSCoder) {
		// Create coders
		let codedRaster = raster().raster.map({(i) -> [QBEValueCoder] in
			return i.map({QBEValueCoder($0)})
		})
		
		coder.encodeObject(codedRaster, forKey: "data")
		coder.encodeObject(columnNames.map({$0.name}), forKey: "columns")
	}
	
	private func changeRasterDirectly(filter: QBEFilter) {
		setRaster(filter(raster()))
	}
	
	func removeRows(set: NSIndexSet) {
		changeRasterDirectly({(r: QBERaster) -> QBERaster in r.removeRows(set); return r })
	}
	
	func removeColumns(set: NSIndexSet) {
		changeRasterDirectly({(r: QBERaster) -> QBERaster in r.removeColumns(set); return r })
	}
	
	func addRow() {
		changeRasterDirectly({(r: QBERaster) -> QBERaster in r.addRow(); return r })
	}
	
	override var debugDescription: String {
		get {
			let r = raster()
			return r.debugDescription
		}
	}
	
	var columnNames: [QBEColumn] {
		get {
			return raster().columnNames
		}
	}
	
	internal func apply(filter: QBEFilter) -> QBEData {
		return QBERasterData(raster: memoize {
			return filter(self.raster())
		})
	}
	
	func transpose() -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			// Find new column names (first column stays in place)
			var columns: [QBEColumn] = [self.columnNames[0]]
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
		return apply {(r: QBERaster) -> QBERaster in
			var columnNames = r.columnNames
			var indices = Dictionary<QBEColumn, Int>()
			
			// Create newly calculated columns
			for (targetColumn, formula) in calculations {
				var columnIndex = r.indexOfColumnWithName(targetColumn) ?? -1
				if columnIndex == -1 {
					columnNames.append(targetColumn)
					columnIndex = columnNames.count-1
				}
				indices[targetColumn] = columnIndex
			}
			
			// Calculate column for each row
			var newData: [[QBEValue]] = []
			let numberOfRows = r.rowCount
			for rowNumber in 0..<numberOfRows {
				var row = r[rowNumber]
				
				for n in 0..<(columnNames.count - row.count) {
					row.append(QBEValue.EmptyValue)
				}
				
				for (targetColumn, formula) in calculations {
					let columnIndex = indices[targetColumn]!
					let inputValue: QBEValue = row[columnIndex]
					let newValue = formula.apply(r, rowNumber: rowNumber, inputValue: inputValue)
					row[columnIndex] = newValue
				}
				
				newData.append(row)
			}
			
			return QBERaster(data: newData,  columnNames: columnNames, readOnly: true)
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
					let groupValue = groupExpression.apply(r, rowNumber: rowNumber, inputValue: nil)
					
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
					let result = value.map.apply(r, rowNumber: rowNumber, inputValue: nil)
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
	
	func random(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			/* Random selection without replacement works like this: first we assign each row a random number. Then, we 
			sort the list of row numbers by the number assigned to each row. We then take the top x of these rows. */
			let numberOfSourceRows = r.rowCount
			var indexPairs = [Int](0..<r.rowCount).map({($0, rand())})
			indexPairs.sort({ (a, b) -> Bool in return a.1 < b.1 })
			let randomlySortedIndices = indexPairs.map({$0.0})
			
			for rowNumber in 0..<numberOfRows {
				newData.append(r[randomlySortedIndices[rowNumber]])
			}
			
			return QBERaster(data: newData, columnNames: r.columnNames, readOnly: true)
		}
	}
	
	func setRaster(r: QBERaster) {
		raster = {() in return r}
	}
	
	func compare(other: QBEData) -> Bool {
		return raster().compare(other.raster())
	}
	
	func stream(receiver: QBESink) {
		// FIXME: batch this, perhaps just send the whole raster at once to receiver() (but do not send column names)
		let r = raster();
		for rowNumber in 0..<r.rowCount {
			receiver(columnNames, [r[rowNumber]])
		}
	}
}