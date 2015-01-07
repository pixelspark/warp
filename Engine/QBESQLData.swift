import Foundation

class QBESQLData: NSObject, QBEData {
    private let sql: String
    
    init(sql: String) {
        self.sql = sql
    }
    
    func transpose() -> QBEData {
        return QBESQLData(sql: "TRANSPOSE(\(self.sql))")
    }
    
    func calculate(targetColumn: String, formula: QBEFunction) -> QBEData {
        return QBESQLData(sql: "CALCULATE() \(sql)")
    }
    
    func limit(numberOfRows: Int) -> QBEData {
        return QBESQLData(sql: "SELECT * FROM \(self.sql) LIMIT \(numberOfRows)")
    }
    
    func replace(value: QBEValue, withValue: QBEValue, inColumn: String) -> QBEData {
        return QBESQLData(sql: "SELECT REPLACE(\(value), \(withValue), \(inColumn)) AS \(inColumn) FROM (\(sql))")
    }
    
    var raster: QBEFuture { get {
        return {() -> QBERaster in
            let d: [[QBEValue]] = [[QBEValue("SQL")], [QBEValue(self.sql)]]
            return QBERaster(d)
        }
    }}
    
    var columnNames: [String] { get {
        return ["SQL"]
    }}
}