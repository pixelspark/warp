import Cocoa
import WarpCore

internal class QBEFilterPlaceholderCell: NSButtonCell {
	required init(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	init() {
		super.init(textCell: "")
	}

	override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
		NSColor.windowBackgroundColor.set()
		NSRectFill(cellFrame)
		QBEFilterPlaceholderCell.drawPlaceholder(frame: cellFrame)
	}

	static func drawPlaceholder(frame cellFrame: NSRect) {
		let h = cellFrame.size.height - 7.0
		let iconRect = NSMakeRect(cellFrame.origin.x + (cellFrame.size.width - h) / 2.0, cellFrame.origin.y + (cellFrame.size.height - h) / 2.0, h, h)
		NSImage(named: "UnavailableIcon")?.draw(in: iconRect)
	}

	@objc func drawWithFrame(_ cellFrame: NSRect, inView: NSView, withBackgroundColor: NSColor) {
		self.draw(withFrame: cellFrame, in: inView)
	}
}

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
	
	required init(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func cancel() {
		self.cacheJob?.cancel()
	}

	private func numberOfStripes(_ cellFrame: NSRect) -> Int {
		let stripeFrame = cellFrame.insetBy(dx: 2, dy: 6)
		return Int(stripeFrame.size.width) / 8
	}
	
	override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
		NSColor.windowBackgroundColor.set()
		NSRectFill(cellFrame)

		if active {
			let h = cellFrame.size.height - 7.0
			let iconRect = NSMakeRect(cellFrame.origin.x + (cellFrame.size.width - h) / 2.0, cellFrame.origin.y + (cellFrame.size.height - h) / 2.0, h, h)
			NSImage(named: "FilterSetIcon")?.draw(in: iconRect)
		}
		else {
			// Calculate the 'bar code' of this colum
			let stripes = numberOfStripes(cellFrame)

			if let c = cached, c.count == stripes {
				self.drawWithFrame(cellFrame, inView: controlView, values: c)
			}
			else {
				// Draw a placeholder
				QBEFilterPlaceholderCell.drawPlaceholder(frame: cellFrame)

				// Start gathering the data necessary to show our 'bar code'
				let column = self.column
				let raster = self.raster
				cacheJob?.cancel()
				let job = Job(.background)
				cacheJob = job
				job.async { [weak self] in
					var v = Array<Int>(repeating: 0, count: stripes)
					if let index = raster.indexOfColumnWithName(column) {
						for row in raster.rows {
							if job.isCancelled {
								return
							}

							let value = row.values[index]
							let hash: Int
							if case .double(let i) = value, !i.isInfinite && !i.isNaN {
								hash = Int(fmod(abs(i), Double(Int.max-1)))
							}
							else {
								hash = abs(value.stringValue?.hashValue ?? 0)
							}
							v[hash % stripes] += 1
						}
					}
					asyncMain {
						if let s = self, !job.isCancelled {
							s.cached = v
							controlView.setNeedsDisplay(cellFrame)
						}
					}
				}
			}
		}
	}

	private func drawWithFrame(_ cellFrame: NSRect, inView controlView: NSView, values: [Int]) {
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

		nonZeroValues.sort(by: {return $0 < $1})

		// Draw the bar code
		let stripeFrame = cellFrame.insetBy(dx: 2, dy: 6)
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
				let stripeRect = CGRect(x: stripeFrame.origin.x + CGFloat(i) * stripeWidth, y: stripeFrame.origin.y + stripeVerticalMargin / 2.0, width: stripeWidth - stripeMargin, height: stripeHeight)
				stripeColor.set()
				NSRectFill(stripeRect)
			}
		}
	}
	
	@objc func drawWithFrame(_ cellFrame: NSRect, inView: NSView, withBackgroundColor: NSColor) {
		self.draw(withFrame: cellFrame, in: inView)
	}
}
