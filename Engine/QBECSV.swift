import Foundation

class QBERasterCSVReader: NSObject, CHCSVParserDelegate {
    var raster = QBERaster()
    var row : [QBEValue] = []
    
    func parser(parser: CHCSVParser, didBeginLine line: UInt) {
        row = []
    }
    
    func parser(parser: CHCSVParser, didEndLine line: UInt) {
        raster.raster.append(row)
        row = []
    }
    
    func parser(parser: CHCSVParser, didReadField field: String, atIndex index: Int) {
        row.append(QBEValue(field))
    }
}