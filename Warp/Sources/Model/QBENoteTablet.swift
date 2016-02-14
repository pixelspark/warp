import Foundation

class QBENoteTablet: QBETablet {
	var text: NSAttributedString

	override init() {
		text = NSAttributedString()
		super.init()
	}

	required init?(coder: NSCoder) {
		text = coder.decodeObjectOfClass(NSAttributedString.self, forKey: "text") ?? NSAttributedString()
		super.init(coder: coder)
	}

	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(self.text, forKey: "text")
	}
}