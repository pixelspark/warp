/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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

/** A 'fingerprint' describes characteristics of a set of columns. */
struct QBEFingerprint {
	let bins: [Int]
	let countInvalid: Int
	let countEmpty: Int
}

internal class QBEFilterCell: NSButtonCell {
	let raster: Raster
	let column: Column
	var selected: Bool = false
	var active: Bool = false
	
	private var cached: QBEFingerprint? = nil
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
		if active {
			let h = cellFrame.size.height - 7.0
			let iconRect = NSMakeRect(cellFrame.origin.x + (cellFrame.size.width - h) / 2.0, cellFrame.origin.y + (cellFrame.size.height - h) / 2.0, h, h)
			NSImage(named: "FilterSetIcon")?.draw(in: iconRect)
		}
		else {
			// Calculate the 'bar code' of this colum
			let stripes = numberOfStripes(cellFrame)

			if let c = cached, c.bins.count == stripes {
				self.drawWithFrame(cellFrame, inView: controlView, fingerprint: c)
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
					var countInvalid = 0
					var countEmpty = 0
					var v = Array<Int>(repeating: 0, count: stripes)
					if let index = raster.indexOfColumnWithName(column) {
						for row in raster.rows {
							if job.isCancelled {
								return
							}

							let value = row.values[index]
							let hash: Int
							if case .empty = value {
								countEmpty += 1
							}
							else if case .invalid = value {
								countInvalid += 1
							}
							else {
								if case .double(let i) = value, !i.isInfinite && !i.isNaN {
									hash = Int(fmod(abs(i), Double(Int.max-1)))
								}
								else {
									hash = abs(value.stringValue?.hashValue ?? 0)
								}
								v[hash % stripes] += 1
							}
						}
					}
					asyncMain {
						if let s = self, !job.isCancelled {
							s.cached = QBEFingerprint(bins: v, countInvalid: countInvalid, countEmpty: countEmpty)
							controlView.setNeedsDisplay(cellFrame)
						}
					}
				}
			}
		}
	}

	private func drawWithFrame(_ cellFrame: NSRect, inView controlView: NSView, fingerprint: QBEFingerprint) {
		// How many stripes are non-zero?
		var nonZeroValues: [Int] = []
		var largestStripe: Int = 0

		let stripes = self.numberOfStripes(cellFrame)
		for i in 0..<stripes {
			if fingerprint.bins[i] > 0 {
				nonZeroValues.append(fingerprint.bins[i])
			}

			if fingerprint.bins[i] > largestStripe {
				largestStripe = fingerprint.bins[i]
			}
		}

		nonZeroValues.sort(by: {return $0 < $1})

		// If there are invalid values, add them to the stripe set
		if fingerprint.countEmpty > 0 {
			nonZeroValues.insert(fingerprint.countEmpty, at: 0)
			largestStripe = max(largestStripe, fingerprint.countEmpty)
		}

		if fingerprint.countInvalid > 0 {
			nonZeroValues.insert(fingerprint.countInvalid, at: 0)
			largestStripe = max(largestStripe, fingerprint.countInvalid)
		}

		// Draw the bar code
		let stripeFrame = cellFrame.insetBy(dx: 2, dy: 6)
		let nonZeroStripes = nonZeroValues.count
		let stripeWidth = stripeFrame.size.width / CGFloat(nonZeroStripes)
		let stripeMargin = CGFloat(1)

		for i in 0..<nonZeroStripes {
			let stripeTotal = nonZeroValues[i]

			if stripeTotal > 0 {
				let scaled = (CGFloat(stripeTotal) / CGFloat(largestStripe)) * 0.8 + 0.2
				let saturation = (selected || active) ? CGFloat(nonZeroStripes) / CGFloat(stripes) : 0.0
				let alpha = (selected || active) ? min(max(0.3,scaled), 0.7) : 0.3

				let stripeColor: NSColor
				let strokeColor: NSColor
				if (fingerprint.countInvalid > 0 && i == 0) {
					strokeColor = NSColor.red
					stripeColor = NSColor.clear
				}
				else if (fingerprint.countInvalid == 0 && fingerprint.countEmpty > 0 && i == 0) {
					strokeColor = NSColor(calibratedWhite: 0.0, alpha: alpha)
					stripeColor = NSColor.clear
				}
				else if (fingerprint.countInvalid > 0 && fingerprint.countEmpty > 0 && i == 1) {
					strokeColor = NSColor(calibratedWhite: 0.0, alpha: alpha)
					stripeColor = NSColor.clear
				}
				else {
					if active {
						stripeColor = NSColor(calibratedHue: CGFloat(i) / CGFloat(nonZeroStripes), saturation: saturation, brightness: 0.5, alpha: alpha)
					}
					else {
						stripeColor = NSColor(calibratedWhite: CGFloat(i) / CGFloat(nonZeroStripes), alpha: alpha)
					}
					strokeColor = NSColor.clear
				}

				let stripeHeight = stripeFrame.size.height * scaled
				let stripeVerticalMargin = stripeFrame.size.height * (1.0-scaled)
				let stripeRect = CGRect(x: stripeFrame.origin.x + CGFloat(i) * stripeWidth, y: stripeFrame.origin.y + stripeVerticalMargin / 2.0, width: stripeWidth - stripeMargin, height: stripeHeight)
				stripeColor.setFill()
				strokeColor.setStroke()

				let roundRect = NSBezierPath(roundedRect: stripeRect, xRadius: 1.0, yRadius: 1.0)
				roundRect.fill()
				roundRect.stroke()
			}
		}
	}
	
	@objc func drawWithFrame(_ cellFrame: NSRect, inView: NSView, withBackgroundColor: NSColor) {
		self.draw(withFrame: cellFrame, in: inView)
	}
}
