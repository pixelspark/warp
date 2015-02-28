import Foundation

/** Represents a data manipulation step. Steps usually connect to (at least) one previous step and (sometimes) a next step.
The step transforms a data manipulation on the data produced by the previous step; the results are in turn used by the 
next. Steps work on two datasets: the 'example' data set (which is used to let the user design the data manipulation) and
the 'full' data (which is the full dataset on which the final data operations are run). 

Subclasses of QBEStep implement the data manipulation in the apply function, and should implement the description method
as well as coding methods. The explanation variable contains a user-defined comment to an instance of the step. **/
class QBEStep: NSObject {
	func exampleData(callback: (QBEData?) -> ()) {
		self.previous?.exampleData({(data) in
			self.apply(data, callback: callback)
		})
	}
	
	func fullData(callback: (QBEData?) -> ()) {
		self.previous?.fullData({(data) in
			self.apply(data, callback: callback)
		})
	}
	
	var previous: QBEStep? { didSet {
		previous?.next = self
	} }
	
	weak var next: QBEStep?
	var explanation: NSAttributedString?
	
	/** Description returns a locale-dependent explanation of the step. It can (should) depend on the specific
	 configuration of the step. **/
	func explain(locale: QBELocale, short: Bool = false) -> String {
		return NSLocalizedString("Unknown step", comment: "")
	}
	
	override private init() {
		self.explanation = NSAttributedString(string: "")
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
	
	init(previous: QBEStep?) {
		self.previous = previous
	}
	
	func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		callback(nil)
	}
}

/** The transpose step implements a row-column switch. It has no configuration and relies on the QBEData transpose()
implementation to do the actual work. **/
class QBETransposeStep: QBEStep {
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		callback(data?.transpose())
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		return NSLocalizedString("Switch rows/columns", comment: "")
	}
}