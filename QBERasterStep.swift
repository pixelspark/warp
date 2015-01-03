import Foundation

class QBERasterStep: QBEStep {
    private var staticData: QBEData?
    
    init(raster: QBERaster, explanation: String) {
        super.init(previous: nil, explanation: explanation)
        self.staticData = QBEData()
        self.staticData?.setRaster(raster)
    }
    
    required init(coder aDecoder: NSCoder) {
        staticData = aDecoder.decodeObjectForKey("staticData") as? QBEData
        super.init(coder: aDecoder)
    }
    
    override func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(staticData, forKey: "staticData")
        super.encodeWithCoder(coder)
    }
    
    override var data: QBEData? { get { return staticData }}
}