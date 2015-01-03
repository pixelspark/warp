import Foundation

class QBEStep: NSObject {
    var data: QBEData? {
        get {
            return nil
        }
    }
    
    var previous: QBEStep?
    var next: QBEStep?
    var explanation: NSAttributedString?

    override private init() {
        self.explanation = NSAttributedString(string: "Hello")
    }
    
    required init(coder aDecoder: NSCoder) {
        previous = aDecoder.decodeObjectForKey("previousStep") as? QBEStep
        next = aDecoder.decodeObjectForKey("nextStep") as? QBEStep
        explanation = aDecoder.decodeObjectForKey("explanation") as? NSAttributedString
    }
    
    func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(previous, forKey: "previousStep")
        coder.encodeObject(next, forKey: "nextStep")
        coder.encodeObject(explanation, forKey: "explanation")
    }
    
    init(previous: QBEStep?, explanation: String) {
        self.previous = previous
        self.explanation = NSAttributedString(string: explanation)
    }
}

class QBETransposeStep: QBEStep {
    override var data: QBEData? {
        get {
            return self.previous?.data?.transpose()
        }
    }
}