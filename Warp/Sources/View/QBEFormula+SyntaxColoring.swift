/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import  Cocoa
import WarpCore

extension Formula {
	var syntaxColoredFormula: NSAttributedString { get {
		let regularFont = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize(for: NSControlSize.regular))!
		
		let ma = NSMutableAttributedString(string: self.originalText, attributes: [
			NSForegroundColorAttributeName: NSColor.black,
			NSFontAttributeName: regularFont
		])
		
		for fragment in self.fragments.sorted(by: {return $0.length > $1.length}) {
			if fragment.expression is Literal {
				ma.addAttributes([
					NSFontAttributeName: regularFont,
					NSForegroundColorAttributeName: NSColor.blue
				], range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Sibling {
				ma.addAttributes([
					NSFontAttributeName: regularFont,
					NSForegroundColorAttributeName: NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
				], range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Foreign {
				ma.addAttributes([
					NSFontAttributeName: regularFont,
					NSForegroundColorAttributeName: NSColor(red: 0.5, green: 0.5, blue: 0.0, alpha: 1.0)
					], range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Identity {
				ma.addAttributes([
					NSFontAttributeName: regularFont,
					NSForegroundColorAttributeName: NSColor(red: 0.8, green: 0.5, blue: 0.0, alpha: 1.0)
				], range: NSMakeRange(fragment.start, fragment.length))
			}
			else if fragment.expression is Call {
				ma.addAttributes([
					NSFontAttributeName: regularFont,
				], range: NSMakeRange(fragment.start, fragment.length))
			}
		}
		
		return ma
	} }
}
