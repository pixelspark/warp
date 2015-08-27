import Cocoa
import WarpCore

internal class QBEFilterCell: NSButtonCell {
	let raster: QBERaster
	let column: QBEColumn
	var selected: Bool = false
	var active: Bool = false
	
	private var cached: [Int]? = nil
	
	init(raster: QBERaster, column: QBEColumn) {
		self.raster = raster
		self.column = column
		super.init(textCell: "")
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override func drawWithFrame(cellFrame: NSRect, inView controlView: NSView) {
		// Calculate the 'bar code' of this column
		let stripeFrame = CGRectInset(cellFrame, 2, 6)
		let stripes = Int(stripeFrame.size.width) / 8
		
		let values: [Int]
		if let c = cached where c.count == stripes {
			values = c
		}
		else {
			var v = Array<Int>(count: stripes, repeatedValue: 0)
			if let index = raster.indexOfColumnWithName(self.column) {
				for row in raster.raster {
					let value = row[index]
					let hash: Int
					if case .DoubleValue(let i) = value where !isinf(i) && !isnan(i) {
						hash = Int(abs(i))
					}
					else {
						hash = abs(value.stringValue?.hashValue ?? 0)
					}
					v[hash % stripes]++
				}
			}
			cached = v
			values = v
		}
		
		// How many stripes are non-zero?
		var nonZeroValues: [Int] = []
		var largestStripe: Int = 0
		for i in 0..<stripes {
			if values[i] > 0 {
				nonZeroValues.append(values[i])
			}
			
			if values[i] > largestStripe {
				largestStripe = values[i]
			}
		}
		
		nonZeroValues.sortInPlace({return $0 > $1})
		
		active ? NSColor.selectedMenuItemColor().set() : NSColor.windowBackgroundColor().set()
		NSRectFill(cellFrame)
		
		// Draw the bar code
		let nonZeroStripes = nonZeroValues.count
		let stripeWidth = stripeFrame.size.width / CGFloat(nonZeroStripes)
		let stripeMargin = CGFloat(2)
		
		for i in 0..<nonZeroStripes {
			let stripeTotal = nonZeroValues[i]
			
			if stripeTotal > 0 {
				let scaled = CGFloat(stripeTotal) / CGFloat(largestStripe)
				let saturation = selected ? CGFloat(nonZeroStripes) / CGFloat(stripes) : 0.0
				let alpha = selected ? min(max(0.3,scaled), 0.7) : 0.3
				let stripeColor = NSColor(calibratedHue: CGFloat(i) / CGFloat(nonZeroStripes), saturation: saturation, brightness: 0.5, alpha: alpha)
				
				let stripeHeight = stripeFrame.size.height * scaled
				let stripeVerticalMargin = stripeFrame.size.height * (1.0-scaled)
				let stripeRect = CGRectMake(stripeFrame.origin.x + CGFloat(i) * stripeWidth, stripeFrame.origin.y + stripeVerticalMargin / 2.0, stripeWidth - stripeMargin, stripeHeight)
				stripeColor.set()
				NSRectFill(stripeRect)
			}
		}
	}
	
	@objc func drawWithFrame(cellFrame: NSRect, inView: NSView, withBackgroundColor: NSColor) {
		self.drawWithFrame(cellFrame, inView: inView)
	}
}