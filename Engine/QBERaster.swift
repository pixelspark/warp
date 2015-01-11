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
			return raster.count > 0 ? raster[0].map({v in return QBEColumn(v.stringValue)}) : []
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