import Foundation

class QBELimitStep: QBEStep {
    var numberOfRows: Int
    
    init(previous: QBEStep?, explanation: String, numberOfRows: Int) {
        self.numberOfRows = numberOfRows
        super.init(previous: previous, explanation: explanation)
    }

    required init(coder aDecoder: NSCoder) {
        numberOfRows = Int(aDecoder.decodeIntForKey("numberOfRows"))
        super.init(coder: aDecoder)
    }
    
    override func encodeWithCoder(coder: NSCoder) {
        super.encodeWithCoder(coder)
        coder.encodeInt(Int32(numberOfRows), forKey: "numberOfRows")
    }
    
    override var data: QBEData? {
        get {
            return self.previous?.data?.limit(numberOfRows)
        }
    }
}