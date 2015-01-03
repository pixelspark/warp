import Foundation

typealias QBEFuture = () -> QBERaster
typealias QBEFilter = (QBERaster) -> (QBERaster)

func memoize<T>(result: () -> T) -> () -> T {
    var cached: T? = nil
    
    return {() in
        if let v = cached {
            return v
        }
        else {
            cached = result()
            return cached!
        }
    }
}

class QBEData: NSObject {
    private(set) var raster: QBEFuture
    
    override init() {
        raster = memoize {() in return QBERaster()}
    }
    
    required init(coder: NSCoder) {
        let loadedRaster = QBERaster(coder.decodeObjectForKey("data") as? [[QBEValue]] ?? [])
        raster = memoize {() in return loadedRaster}
    }
    
    init(raster: QBEFuture) {
        self.raster = raster
    }

    init(data: [[QBEValue]]) {
        raster = memoize {() in return QBERaster(data)}
    }

    private init(_ r: QBEFuture) {
        raster = r
    }
    
    func clone() -> QBEData {
        return QBEData(raster)
    }
    
    var isEmpty: Bool { get {
        return raster().isEmpty
    }}
    
    func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(raster().raster, forKey: "data")
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
    
    var columnNames: [String] {
        get {
            return raster().columnNames
        }
    }
    
    func apply(filter: QBEFilter) -> QBEData {
        return QBEData(raster: memoize({() in
            return filter(self.raster())
        }))
    }
    
    func transpose() -> QBEData {
        return apply {(r: QBERaster) -> QBERaster in
            var newData: [[QBEValue]] = []
            
            let columnNames = r.columnNames
            for colNumber in 0..<r.columnCount {
                let columnName = columnNames[colNumber];
                var row: [QBEValue] = [QBEValue(columnName)]
                for rowNumber in 0..<r.rowCount {
                    row.append(r[rowNumber, colNumber])
                }
                newData.append(row)
            }
            
            return QBERaster(newData, readOnly: true)
        }
    }
    
    func limit(numberOfRows: Int) -> QBEData {
        return apply {(r: QBERaster) -> QBERaster in
            var newData: [[QBEValue]] = [r.columnNames.map({s in return QBEValue(s)})]
            
            for rowNumber in 0..<numberOfRows {
                newData.append(r[rowNumber])
            }
            
            return QBERaster(newData, readOnly: true)
        }
    }
    
    func replace(value: QBEValue, withValue: QBEValue, inColumn: String) -> QBEData {
        return apply {(r: QBERaster) -> QBERaster in
            var newData: [[QBEValue]] = [r.columnNames.map({s in return QBEValue(s)})]
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
}