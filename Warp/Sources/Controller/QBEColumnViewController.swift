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

protocol QBEColumnViewDelegate: NSObjectProtocol {
	func columnViewControllerDidRename(_ controller: QBEColumnViewController, column: Column, to: Column)
	func columnViewControllerDidRemove(_ controller: QBEColumnViewController, column: Column)
	func columnViewControllerDidSort(_ controller: QBEColumnViewController, column: Column, ascending: Bool)
	func columnViewControllerDidAutosize(_ controller: QBEColumnViewController, column: Column)
	func columnViewControllerSetFullData(_ controller: QBEColumnViewController, fullDataset: Bool)
}

private struct QBEColumnDescriptives {
	let average: Double?
	let standardDeviation: Double?
	let minimumValue: Value
	let maximumValue: Value
	let count: Int
	let countUnique: Int
	let countEmpty: Int
}

class QBEColumnViewController: NSViewController {
	weak var delegate: QBEColumnViewDelegate? = nil
	var column: Column? = nil { didSet { asyncMain { self.update() } } }
	var data: Dataset? = nil { didSet { asyncMain { self.update() } } }
	var isFullDataset: Bool = false { didSet { asyncMain { self.update() } } }

	private var descriptives: QBEColumnDescriptives? = nil
	private var descriptivesJob: Job? = nil

	@IBOutlet private var nameField: NSTextField!
	@IBOutlet private var muLabel: NSTextField!
	@IBOutlet private var sigmaLabel: NSTextField!
	@IBOutlet private var minLabel: NSTextField!
	@IBOutlet private var maxLabel: NSTextField!
	@IBOutlet private var countLabel: NSTextField!
	@IBOutlet private var distinctLabel: NSTextField!
	@IBOutlet private var progressIndicator: NSProgressIndicator!
	@IBOutlet private var descriptivesView: NSView!
	@IBOutlet private var fullDatasetButton: NSButton!
	@IBOutlet private var emptyLabel: NSTextField!

	deinit {
		assertMainThread()
	}

	override func viewWillAppear() {
		self.updateDescriptives()
		self.update()
	}

	override func viewWillDisappear() {
		self.descriptivesJob?.cancel()
		self.descriptivesJob = nil
		self.descriptives = nil
	}

	func updateDescriptives() {
		asyncMain {
			self.descriptivesJob?.cancel()
			self.descriptivesJob = nil
			self.descriptives = nil

			if let d = self.data, let cn = self.column {
				asyncMain {
					self.descriptivesJob = Job(.background)
					self.update()
					self.progressIndicator?.startAnimation(nil)

					// Todo fetch descriptives
					let descriptiveDataset = d.aggregate([:], values: [
						"mu": Aggregator(map: Sibling(cn), reduce: .Average),
						"s": Aggregator(map: Sibling(cn), reduce: .StandardDeviationSample),
						"mn": Aggregator(map: Sibling(cn), reduce: .Min),
						"mx": Aggregator(map: Sibling(cn), reduce: .Max),
						"c": Aggregator(map: Sibling(cn), reduce: .CountAll),
						"cd": Aggregator(map: Sibling(cn), reduce: .CountDistinct),
						"mt": Aggregator(map: Call(arguments: [Call(arguments:[Sibling(cn)], type: Function.IsEmpty), Literal(Value(1)), Literal(Value(0))], type: Function.If), reduce: .Sum)
					])

					descriptiveDataset.raster(self.descriptivesJob!) { [weak self] result in
						switch result {
						case .success(let raster):
							asyncMain {
								if raster.rowCount == 1 {
									let row = raster.rows.makeIterator().next()!
									self?.descriptives = QBEColumnDescriptives(
										average: row["mu"].doubleValue,
										standardDeviation: row["s"].doubleValue,
										minimumValue: row["mn"],
										maximumValue: row["mx"],
										count: row["c"].intValue ?? 0,
										countUnique: row["cd"].intValue ?? 0,
										countEmpty: row["mt"].intValue ?? 0
									)
								}
								else {
									print("Did not receive enough descriptives data!")
								}

								self?.descriptivesJob = nil
								self?.update()
							}

						case .failure(let e):
							print("Descriptives failure: \(e)")
							self?.update()
						}
					}
				}
			}
			else {
				print("Not fetching descriptives: no data or no column")
				self.update()
			}
		}
	}

	private func update() {
		for v in [self.muLabel, self.sigmaLabel, self.maxLabel, self.minLabel, self.distinctLabel, self.countLabel, self.emptyLabel] {
			if let vv = v {
				let tr = CATransition()
				tr.duration = 0.3
				tr.type = kCATransitionPush
				tr.subtype = kCATransitionFromBottom
				tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
				vv.layer?.add(tr, forKey: kCATransition)
			}
		}

		let locale = QBEAppDelegate.sharedInstance.locale
		self.nameField?.stringValue = column?.name ?? ""
		self.progressIndicator?.isHidden = self.descriptivesJob == nil
		self.descriptivesView?.isHidden = self.descriptives == nil
		self.fullDatasetButton?.state = self.isFullDataset ? NSOnState: NSOffState
		self.fullDatasetButton?.image =  NSImage(named: self.isFullDataset ? "BigIcon" : "SmallIcon")

		if let d = self.descriptives, let locale = locale {
			let avg = d.average == nil ? Value.invalid: Value.double(d.average!)
			self.muLabel?.stringValue = locale.localStringFor(avg)

			let sd = d.standardDeviation == nil ? Value.invalid: Value.double(d.standardDeviation!)
			self.sigmaLabel?.stringValue = locale.localStringFor(sd)

			self.minLabel?.stringValue = locale.localStringFor(d.minimumValue)
			self.maxLabel?.stringValue = locale.localStringFor(d.maximumValue)
			self.countLabel?.stringValue = locale.localStringFor(Value.int(d.count))
			self.distinctLabel?.stringValue = locale.localStringFor(Value.int(d.countUnique))
			self.emptyLabel?.stringValue = locale.localStringFor(Value.int(d.countEmpty))
		}
		else {
			if self.descriptivesJob == nil {
				self.muLabel?.stringValue = "?"
				self.sigmaLabel?.stringValue = "?"
				self.minLabel?.stringValue = "?"
				self.maxLabel?.stringValue = "?"
				self.countLabel?.stringValue = "?"
				self.distinctLabel?.stringValue = "?"
				self.emptyLabel?.stringValue = "?"
			}
		}
	}

	@IBAction func toggleFullData(_ sender: NSObject) {
		self.delegate?.columnViewControllerSetFullData(self, fullDataset: !self.isFullDataset)
	}

	@IBAction func removeColumn(_ sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidRemove(self, column: c)
		}
	}

	@IBAction func autosizeColumn(_ sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidAutosize(self, column: c)
		}
	}

	@IBAction func sortAscending(_ sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidSort(self, column: c, ascending: true)
		}
	}

	@IBAction func sortDescending(_ sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidSort(self, column: c, ascending: false)
		}
	}

	@IBAction func rename(_ sender: NSObject) {
		if let c = self.column {
			let newName = Column(nameField.stringValue)
			if c != newName {
				self.delegate?.columnViewControllerDidRename(self, column:  c, to: newName)
				self.column = newName
			}
		}
	}
}
