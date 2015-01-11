import Foundation

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
				return i.map({(j) -> QBEValue in return j.value})
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
			return i.map({(j) -> QBEValueCoder in return QBEValueCoder(j)})
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
	
	func calculate(targetColumn: QBEColumn, formula: QBEExpression) -> QBEData {
		return apply {(r: QBERaster) -> QBERaster in
			var columnNames = r.columnNames
			var columnIndex = r.indexOfColumnWithName(targetColumn) ?? -1
			if columnIndex == -1 {
				columnNames.append(targetColumn)
				columnIndex = columnNames.count-1
			}
			
			var newData: [[QBEValue]] = [columnNames.map({s in return QBEValue(s.name)})]
			
			let numberOfRows = r.rowCount
			for rowNumber in 0..<numberOfRows {
				var row = r[rowNumber]
				let inputValue: QBEValue? = (row.count <= columnIndex) ? nil : row[columnIndex]
				row[columnIndex] = formula.apply(r, rowNumber: rowNumber, inputValue: inputValue)
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
			var newData: [[QBEValue]] = [r.columnNames.map({s in return QBEValue(s.name)})]
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