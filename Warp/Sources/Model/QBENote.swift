import Foundation

class QBENote: NSObject, NSSecureCoding {
	var text: NSAttributedString = NSAttributedString(string: "")

	override init() {
		super.init()
	}

	required init?(coder: NSCoder) {
		text = coder.decodeObjectOfClass(NSAttributedString.self, forKey: "text") ?? NSAttributedString()
		super.init()
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(self.text, forKey: "text")
	}

	@objc static func supportsSecureCoding() -> Bool {
		return true
	}
}

class QBENoteTablet: QBETablet {
	var note: QBENote

	override init() {
		note = QBENote()
		super.init()
	}

	required init?(coder: NSCoder) {
		note = coder.decodeObjectOfClass(QBENote.self, forKey: "note") ?? QBENote()
		super.init(coder: coder)
	}

	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(self.note, forKey: "note")
	}
}