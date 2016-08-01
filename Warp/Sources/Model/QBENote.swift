import Foundation

class QBENote: NSObject, NSSecureCoding {
	var text: NSAttributedString = NSAttributedString(string: "")

	override init() {
		super.init()
	}

	required init?(coder: NSCoder) {
		text = coder.decodeObject(of: NSAttributedString.self, forKey: "text") ?? NSAttributedString()
		super.init()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(self.text, forKey: "text")
	}

	static var supportsSecureCoding: Bool = true
}

class QBENoteTablet: QBETablet {
	var note: QBENote

	override init() {
		note = QBENote()
		super.init()
	}

	required init?(coder: NSCoder) {
		note = coder.decodeObject(of: QBENote.self, forKey: "note") ?? QBENote()
		super.init(coder: coder)
	}

	override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(self.note, forKey: "note")
	}
}
