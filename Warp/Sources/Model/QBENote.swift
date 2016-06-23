import Foundation

class QBENote: NSObject, NSSecureCoding {
	var text: AttributedString = AttributedString(string: "")

	override init() {
		super.init()
	}

	required init?(coder: NSCoder) {
		text = coder.decodeObjectOfClass(AttributedString.self, forKey: "text") ?? AttributedString()
		super.init()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(self.text, forKey: "text")
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

	override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(self.note, forKey: "note")
	}
}
