/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

#if os(macOS)
fileprivate typealias UXColor = NSColor
#endif

#if os(iOS)
fileprivate typealias UXColor = UIColor
#endif

extension Formula {
	var syntaxColoredFormula: NSAttributedString { get {
		#if os(macOS)
		let regularFont = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize(for: .regular))!
		let textColor = UXColor.textColor
		#endif

		#if os(iOS)
		let regularFont = UIFont.monospacedDigitSystemFont(ofSize: UIFont.labelFontSize, weight: UIFont.Weight.regular)
		let textColor = UXColor.label
		#endif

		
		let ma = NSMutableAttributedString(string: self.originalText, attributes: convertToOptionalNSAttributedStringKeyDictionary([
			convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): textColor,
			convertFromNSAttributedStringKey(NSAttributedString.Key.font): regularFont
		]))
		
		for fragment in self.fragments.sorted(by: {return $0.length > $1.length}) {
			if fragment.expression is Literal {
				ma.addAttributes(convertToNSAttributedStringKeyDictionary([
					convertFromNSAttributedStringKey(NSAttributedString.Key.font): regularFont,
					convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UXColor.systemTeal
				]), range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Sibling {
				ma.addAttributes(convertToNSAttributedStringKeyDictionary([
					convertFromNSAttributedStringKey(NSAttributedString.Key.font): regularFont,
					convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UXColor.systemGreen
				]), range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Foreign {
				ma.addAttributes(convertToNSAttributedStringKeyDictionary([
					convertFromNSAttributedStringKey(NSAttributedString.Key.font): regularFont,
					convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UXColor.systemYellow
					]), range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Identity {
				ma.addAttributes(convertToNSAttributedStringKeyDictionary([
					convertFromNSAttributedStringKey(NSAttributedString.Key.font): regularFont,
					convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UXColor.systemOrange
				]), range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Call {
				ma.addAttributes(convertToNSAttributedStringKeyDictionary([
					convertFromNSAttributedStringKey(NSAttributedString.Key.font): regularFont,
					convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UXColor.systemBlue
				]), range: NSMakeRange(fragment.start, fragment.length))
			}
		}
		
		return ma
	} }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToNSAttributedStringKeyDictionary(_ input: [String: Any]) -> [NSAttributedString.Key: Any] {
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}
