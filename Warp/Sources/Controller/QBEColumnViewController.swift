import Cocoa
import WarpCore

protocol QBEColumnViewDelegate: NSObjectProtocol {
	func columnViewControllerDidRename(controller: QBEColumnViewController, column: Column, to: Column)
	func columnViewControllerDidRemove(controller: QBEColumnViewController, column: Column)
	func columnViewControllerDidSort(controller: QBEColumnViewController, column: Column, ascending: Bool)
	func columnViewControllerDidAutosize(controller: QBEColumnViewController, column: Column)
	func columnViewControllerSetFullData(controller: QBEColumnViewController, fullData: Bool)
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
	var data: Data? = nil { didSet { asyncMain { self.update() } } }
	var isFullData: Bool = false { didSet { asyncMain { self.update() } } }

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
	@IBOutlet private var fullDataButton: NSButton!
	@IBOutlet private var emptyLabel: NSTextField!

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
					self.descriptivesJob = Job(.Background)
					self.update()
					self.progressIndicator?.startAnimation(nil)

					// Todo fetch descriptives
					let descriptiveData = d.aggregate([:], values: [
						"mu": Aggregator(map: Sibling(cn), reduce: .Average),
						"s": Aggregator(map: Sibling(cn), reduce: .StandardDeviationSample),
						"mn": Aggregator(map: Sibling(cn), reduce: .Min),
						"mx": Aggregator(map: Sibling(cn), reduce: .Max),
						"c": Aggregator(map: Sibling(cn), reduce: .CountAll),
						"cd": Aggregator(map: Sibling(cn), reduce: .CountDistinct),
						"mt": Aggregator(map: Call(arguments: [Call(arguments:[Sibling(cn)], type: Function.IsEmpty), Literal(Value(1)), Literal(Value(0))], type: Function.If), reduce: .Sum)
					])

					descriptiveData.raster(self.descriptivesJob!) { result in
						switch result {
						case .Success(let raster):
							asyncMain {
								if raster.rowCount == 1 {
									let row = raster.rows.generate().next()!
									self.descriptives = QBEColumnDescriptives(
										average: row["mu"].doubleValue,
										standardDeviation: row["s"].doubleValue,
										minimumValue: row["mn"],
										maximumValue: row["mx"],
										count: row["c"].intValue!,
										countUnique: row["cd"].intValue!,
										countEmpty: row["mt"].intValue!
									)
								}
								else {
									print("Did not receive enough descriptives data!")
								}

								self.descriptivesJob = nil
								self.update()
							}

						case .Failure(let e):
							print("Descriptives failure: \(e)")
							self.update()
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
				vv.layer?.addAnimation(tr, forKey: kCATransition)
			}
		}

		let locale = QBEAppDelegate.sharedInstance.locale
		self.nameField?.stringValue = column?.name ?? ""
		self.progressIndicator?.hidden = self.descriptivesJob == nil
		self.descriptivesView?.hidden = self.descriptives == nil
		self.fullDataButton?.state = self.isFullData ? NSOnState: NSOffState
		self.fullDataButton?.image =  NSImage(named: self.isFullData ? "BigIcon" : "SmallIcon")

		if let d = self.descriptives {
			let avg = d.average == nil ? Value.InvalidValue: Value.DoubleValue(d.average!)
			self.muLabel?.stringValue = locale.localStringFor(avg)

			let sd = d.standardDeviation == nil ? Value.InvalidValue: Value.DoubleValue(d.standardDeviation!)
			self.sigmaLabel?.stringValue = locale.localStringFor(sd)

			self.minLabel?.stringValue = locale.localStringFor(d.minimumValue)
			self.maxLabel?.stringValue = locale.localStringFor(d.maximumValue)
			self.countLabel?.stringValue = locale.localStringFor(Value.IntValue(d.count))
			self.distinctLabel?.stringValue = locale.localStringFor(Value.IntValue(d.countUnique))
			self.emptyLabel?.stringValue = locale.localStringFor(Value.IntValue(d.countEmpty))
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

	@IBAction func toggleFullData(sender: NSObject) {
		self.delegate?.columnViewControllerSetFullData(self, fullData: !self.isFullData)
	}

	@IBAction func removeColumn(sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidRemove(self, column: c)
		}
	}

	@IBAction func autosizeColumn(sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidAutosize(self, column: c)
		}
	}

	@IBAction func sortAscending(sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidSort(self, column: c, ascending: true)
		}
	}

	@IBAction func sortDescending(sender: NSObject) {
		if let c = self.column {
			self.delegate?.columnViewControllerDidSort(self, column: c, ascending: false)
		}
	}

	@IBAction func rename(sender: NSObject) {
		if let c = self.column {
			let newName = Column(nameField.stringValue)
			if c != newName {
				self.delegate?.columnViewControllerDidRename(self, column:  c, to: newName)
				self.column = newName
			}
		}
	}
}