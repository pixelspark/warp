/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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
