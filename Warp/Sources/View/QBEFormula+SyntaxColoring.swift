import  Cocoa
import WarpCore

extension Formula {
	var syntaxColoredFormula: AttributedString { get {
		let regularFont = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize(for: NSControlSize.regular))!
		
		let ma = NSMutableAttributedString(string: self.originalText, attributes: [
			NSForegroundColorAttributeName: NSColor.black(),
			NSFontAttributeName: regularFont
		])
		
		for fragment in self.fragments.sorted(isOrderedBefore: {return $0.length > $1.length}) {
			if fragment.expression is Literal {
				ma.addAttributes([
					NSFontAttributeName: regularFont,
					NSForegroundColorAttributeName: NSColor.blue()
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
