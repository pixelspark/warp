import Cocoa
import WarpCore

internal class QBEFilterCell: NSButtonCell {
	let raster: Raster
	let column: Column
	var selected: Bool = false
	var active: Bool = false
	
	private var cached: [Int]? = nil
	private var cacheJob: Job? = nil
	
	init(raster: Raster, column: Column) {
		self.raster = raster
		self.column = column
		super.init(textCell: "")
	}

	deinit {
		cacheJob?.cancel()
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func numberOfStripes(cellFrame: NSRect) -> Int {
		let stripeFrame = CGRectInset(cellFrame, 2, 6)
		return Int(stripeFrame.size.width) / 8
	}
	
	override func drawWithFrame(cellFrame: NSRect, inView controlView: NSView) {
		NSColor.windowBackgroundColor().set()
		NSRectFill(cellFrame)

		if active {
			let h = cellFrame.size.height - 7.0
			let iconRect = NSMakeRect(cellFrame.origin.x + (cellFrame.size.width - h) / 2.0, cellFrame.origin.y + (cellFrame.size.height - h) / 2.0, h, h)
			NSImage(named: "FilterSetIcon")?.drawInRect(iconRect)
		}
		else {
			// Calculate the 'bar code' of this colum
			let stripes = numberOfStripes(cellFrame)

			if let c = cached where c.count == stripes {
				self.drawWithFrame(cellFrame, inView: controlView, values: c)
			}
			else {
				let column = self.column
				let raster = self.raster
				cacheJob?.cancel()
				let job = Job(.Background)
				cacheJob = job
				job.async { [weak self] in
					var v = Array<Int>(count: stripes, repeatedValue: 0)
					if let index = raster.indexOfColumnWithName(column) {
						for row in raster.rows {
							if job.cancelled {
								return
							}

							let value = row.values[index]
							let hash: Int
							if case .DoubleValue(let i) = value where !isinf(i) && !isnan(i) {
								hash = Int(fmod(abs(i), Double(Int.max-1)))
							}
							else {
								hash = abs(value.stringValue?.hashValue ?? 0)
							}
							v[hash % stripes] += 1
						}
					}
					asyncMain {
						if let s = self where !job.cancelled {
							s.cached = v
							controlView.setNeedsDisplayInRect(cellFrame)
						}
					}
				}
			}
		}
	}

	private func drawWithFrame(cellFrame: NSRect, inView controlView: NSView, values: [Int]) {
		// How many stripes are non-zero?
		var nonZeroValues: [Int] = []
		var largestStripe: Int = 0
		let stripes = self.numberOfStripes(cellFrame)
		for i in 0..<stripes {
			if values[i] > 0 {
				nonZeroValues.append(values[i])
			}

			if values[i] > largestStripe {
				largestStripe = values[i]
			}
		}

		nonZeroValues.sortInPlace({return $0 < $1})

		// Draw the bar code
		let stripeFrame = CGRectInset(cellFrame, 2, 6)
		let nonZeroStripes = nonZeroValues.count
		let stripeWidth = stripeFrame.size.width / CGFloat(nonZeroStripes)
		let stripeMargin = CGFloat(1)

		for i in 0..<nonZeroStripes {
			let stripeTotal = nonZeroValues[i]

			if stripeTotal > 0 {
				let scaled = CGFloat(stripeTotal) / CGFloat(largestStripe)
				let saturation = (selected || active) ? CGFloat(nonZeroStripes) / CGFloat(stripes) : 0.0
				let alpha = (selected || active) ? min(max(0.3,scaled), 0.7) : 0.3

				let stripeColor: NSColor
				if active {
					stripeColor = NSColor(calibratedHue: CGFloat(i) / CGFloat(nonZeroStripes), saturation: saturation, brightness: 0.5, alpha: alpha)
				}
				else {
					stripeColor = NSColor(calibratedWhite: CGFloat(i) / CGFloat(nonZeroStripes), alpha: alpha)
				}

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