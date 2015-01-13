import Foundation

private extension Array {
	mutating func removeObjectsAtIndexes(indexes: NSIndexSet, offset: Int) {
		for var i = indexes.lastIndex; i != NSNotFound; i = indexes.indexLessThanIndex(i) {
			self.removeAtIndex(i+offset)
		}
	}
}

class QBERaster {
	var raster: [[QBEValue]] {
		didSet {
			// FIXME: check whether duplicate column names have been introduced
		}
	}
	
	var readOnly: Bool
	
	init() {
		raster = []
		readOnly = false
	}
	
	init(_ data: [[QBEValue]]) {
		raster = data
		readOnly = false
	}
	
	init(_ data: [[QBEValue]], readOnly: Bool) {
		self.readOnly = readOnly
		self.raster = data
	}
	
	var isEmpty: Bool { get {
		return raster.count==0
		}}
	
	func removeRows(set: NSIndexSet) {
		if readOnly {
			fatalError("Raster is read-only")
		}
		raster.removeObjectsAtIndexes(set, offset: 1)
	}
	
	func removeColumns(set: NSIndexSet) {
		if readOnly {
			fatalError("Raster is read-only")
		}
		
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
		if raster.count<1 {
			return nil
		}
		
		let header = columnNames
		for i in 0..<self.columnCount {
			if(header[i]==name) {
				return i
			}
		}
		return nil
	}
	
	var columnNames: [QBEColumn] {
		get {
			return raster.count > 0 ? raster[0].map({QBEColumn($0.stringValue!)}) : []
		}
	}
	
	var rowCount: Int {
		get {
			return max(0, raster.count-1)
		}
	}
	
	var columnCount: Int {
		get {
			return raster.count > 0 ? raster[0].count : 0
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
		return raster[row+1]
	}
	
	subscript(row: Int, col: Int) -> QBEValue {
		assert(row < rowCount)
		assert(col < columnCount)
		
		let rowData = raster[row+1]
		if(col > rowData.count) {
			return QBEValue("")
		}
		return rowData[col]
	}
	
	func setValue(value: QBEValue, forColumn: QBEColumn, inRow row: Int) {
		assert(row < self.rowCount)
		
		if readOnly {
			fatalError("Raster is read-only")
		}
		
		if let col = indexOfColumnWithName(forColumn) {
			var rowData = raster[row+1]
			rowData[col] = value
			raster[row+1] = rowData
		}
	}
	
	func description() -> String {
		var d = ""
		
		var line = "\t|"
		for columnName in self.columnNames {
			line += columnName.name+"\t|"
		}
		d += line + "\r\n"
		
		for rowNumber in 0..<rowCount {
			var line = "\(rowNumber)\t|"
			for colNumber in 0..<self.columnCount {
				line += self[rowNumber, colNumber].description + "\t|"
			}
			d += line + "\r\n"
		}
		return d
	}
	
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


class QBERasterData: NSObject, QBEData, NSCoding {
	private(set) var raster: QBEFuture
	
	override init() {
		raster = memoize {
			return QBERaster()
		}
	}
	
	required init(coder: NSCoder) {
		let codedRaster = coder.decodeObjectForKey("data") as? [[QBEValueCoder]] ?? []
		
		// The raster is stored as [[QBEValueCoder]], but needs to be a [[QBEValue]]. Lazily decode it
		raster = memoize {
			return QBERaster(codedRaster.map({(i) -> [QBEValue] in
				return i.map({$0.value})
			}))
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
	
	init(data: [[QBEValue]]) {
		raster = memoize {
			return QBERaster(data)
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
	
	override var description: String {
		get {
			let r = raster()
			return r.description()
		}
	}
	
	var columnNames: [QBEColumn] {
		get {
			return raster().columnNames
		}
	}
	
	func apply(filter: QBEFilter) -> QBEData {
		return QBERasterData(raster: memoize {
			return filter(self.raster())
			})
	}
	
	func transpose() -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = []
			
			let columnNames = r.columnNames
			for colNumber in 0..<r.columnCount {
				let columnName = columnNames[colNumber];
				var row: [QBEValue] = [QBEValue(columnName.name)]
				for rowNumber in 0..<r.rowCount {
					row.append(r[rowNumber, colNumber])
				}
				newData.append(row)
			}
			
			return QBERaster(newData, readOnly: true)
		}
	}
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			let indexesToKeep = columns.map({(col) -> Int? in return r.indexOfColumnWithName(col)})
			var newData: [[QBEValue]] = [columns.map({QBEValue($0.name)})]
			
			for rowNumber in 0..<r.rowCount {
				var oldRow = r[rowNumber]
				var newRow: [QBEValue] = []
				for i in indexesToKeep {
					if i != nil {
						newRow.append(oldRow[i!])
					}
				}
				newData.append(newRow)
			}
			
			return QBERaster(newData, readOnly: true)
		}
	}
	
	func calculate(targetColumn: QBEColumn, formula: QBEExpression) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var columnNames = r.columnNames
			var columnIndex = r.indexOfColumnWithName(targetColumn) ?? -1
			if columnIndex == -1 {
				columnNames.append(targetColumn)
				columnIndex = columnNames.count-1
			}
			
			var newData: [[QBEValue]] = [columnNames.map({QBEValue($0.name)})]
			
			let numberOfRows = r.rowCount
			for rowNumber in 0..<numberOfRows {
				var row = r[rowNumber]
				let inputValue: QBEValue? = (row.count <= columnIndex) ? nil : row[columnIndex]
				let newValue = formula.apply(r, rowNumber: rowNumber, inputValue: inputValue)
				
				if row.count > columnIndex {
					row[columnIndex] = newValue
				}
				else {
					row.append(newValue)
				}
				
				newData.append(row)
			}
			
			return QBERaster(newData, readOnly: true)
		}
	}
	
	func limit(numberOfRows: Int) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = [r.columnNames.map({s in return QBEValue(s.name)})]
			
			for rowNumber in 0..<numberOfRows {
				newData.append(r[rowNumber])
			}
			
			return QBERaster(newData, readOnly: true)
		}
	}
	
	func replace(value: QBEValue, withValue: QBEValue, inColumn: QBEColumn) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var newData: [[QBEValue]] = [r.columnNames.map({QBEValue($0.name)})]
			if let replaceColumnIndex = self.raster().indexOfColumnWithName(inColumn) {
				for rowNumber in 0..<r.rowCount {
					var newRow = r[rowNumber]
					if newRow[replaceColumnIndex] == value {
						newRow[replaceColumnIndex] = withValue
					}
					newData.append(newRow)
				}
				
				return QBERaster(newData, readOnly: true)
			}
			return r
		}
	}
	
	func setRaster(r: QBERaster) {
		raster = {() in return r}
	}
	
	func compare(other: QBEData) -> Bool {
		return raster().compare(other.raster())
	}
	
	func stream(receiver: ([[QBEValue]]) -> ()) {
		// FIXME: batch this, perhaps just send the whole raster at once to receiver() (but do not send column names)
		let r = raster();
		for rowNumber in 0..<r.rowCount {
			receiver([r[rowNumber]])
		}
	}
}