import Cocoa
import WarpCore

protocol QBEFilterViewDelegate: NSObjectProtocol {
	func filterView(_ view: QBEFilterViewController, didChangeFilter: FilterSet?)
}

class QBEFilterViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, JobDelegate {
	@IBOutlet weak var searchField: NSSearchField?
	@IBOutlet weak var valueList: NSTableView?
	@IBOutlet weak var progressBar: NSProgressIndicator!
	@IBOutlet weak var clearFilterButton: NSButton!
	private var lastSearch: String? = nil
	weak var delegate: QBEFilterViewDelegate?
	
	var data: Dataset?

	/* Dataset set used for searching. Can be the full data set if the other data set is an example one. If this is nil, 
	the normal one is used. */
	var searchDataset: Dataset?
	var column: Column?
	
	private var reloadJob: Job? = nil
	private var values = OrderedDictionary<Value, Int>()
	private var valueCount = 0
	
	var filter: FilterSet = FilterSet() { didSet {
		assertMainThread()
		reloadData()
	} }
	
	func job(_ job: AnyObject, didProgress: Double) {
		asyncMain {
			self.updateProgress()
		}
	}

	deinit {
		assertMainThread()
	}
	
	private func updateProgress() {
		assertMainThread()
		if let j = self.reloadJob {
			self.progressBar?.isHidden = false
			self.valueList?.isEnabled = false
			self.valueList?.layer?.opacity = 0.5
			let p = j.progress
			self.progressBar?.isIndeterminate = (p <= 0.0)
			self.progressBar?.doubleValue = p * 1000
		}
		else {
			self.progressBar?.isHidden = true
			self.valueList?.isEnabled = true
			self.valueList?.layer?.opacity = 1.0
		}
	}
	
	private func reloadData() {
		assertMainThread()
		reloadJob?.cancel()
		reloadJob = nil
		
		if let d = data, let c = column {
			var filteredDataset = d
			if let search = searchField?.stringValue, !search.isEmpty {
				lastSearch = search
				filteredDataset = searchDataset ?? filteredDataset
				filteredDataset = filteredDataset.filter(Comparison(first: Literal(Value(search)), second: Sibling(c), type: Binary.MatchesRegex))
			}

			let job = Job(.userInitiated)
			reloadJob = job
			reloadJob?.addObserver(self)
			self.updateProgress()

			filteredDataset.histogram(Sibling(c), job: job) { result in
				switch result {
					case .success(let values):
						var ordered = OrderedDictionary(dictionaryInAnyOrder: values)
						ordered.sortKeysInPlace { a,b in return a.stringValue < b.stringValue }
						var count = 0
						ordered.forEach { _, v in
							count += v
						}

						asyncMain { [weak self] in
							if !job.isCancelled {
								self?.values = ordered
								self?.reloadJob = nil
								self?.valueCount = count
								self?.updateProgress()
								self?.valueList?.reloadData()
							}
						}
					
					case .failure(let e):
						trace("Error fetching unique values: \(e)")
				}
			}
		}
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return values.count
	}
	
	func tableView(_ tableView: NSTableView, setObjectValue object: AnyObject?, for tableColumn: NSTableColumn?, row: Int) {
		if row < values.count {
			switch tableColumn?.identifier ?? "" {
				case "selected":
					if let b = object?.boolValue, b {
						filter.selectedValues.insert(values[row].0)
					}
					else {
						filter.selectedValues.remove(values[row].0)
					}
					filterChanged()
				
				default:
					break // Ignore
			}
		}
	}
	
	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row < values.count {
			let value = values[row].0

			switch tableColumn?.identifier ?? "" {
				case "value":
					switch value {
						case .empty:
							return NSLocalizedString("(missing)", comment: "")

						case .invalid:
							return NSLocalizedString("(error)", comment: "")

						default:
							return QBEAppDelegate.sharedInstance.locale.localStringFor(value)
					}

				case "occurrence":
					if self.valueCount > 0 {
						return max(1.0, (Double(values[row].1) / Double(self.valueCount)) * 50.0)
					}
					return 0.0
				
				case "selected":
					return NSNumber(value: filter.selectedValues.contains(value))

				default:
					return nil
			}
		}
		return nil
	}

	func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
		for d in tableView.sortDescriptors.reversed() {
			if let k = d.key {
				switch k {
					case "value":
						self.values.sortKeysInPlace { a, b in
							if d.ascending {
								return a.stringValue < b.stringValue
							}
							else {
								return a.stringValue > b.stringValue
							}
						}

					case "occurrence":
						self.values.sortPairsInPlace { a, b in
							if d.ascending {
								return a.value < b.value
							}
							else {
								return a.value > b.value
							}
						}

					default:
						break
				}
			}
		}
		tableView.reloadData()
	}
	
	@IBAction func searchChanged(_ sender: NSObject) {
		if let search = searchField?.stringValue, !search.isEmpty && search != lastSearch {
			reloadData()
		}
	}

	private func update() {
		assertMainThread()
		self.valueList?.reloadData()
		let hasFilter = filter.selectedValues.count > 0
		self.clearFilterButton?.isEnabled = hasFilter
	}
	
	private func filterChanged() {
		assertMainThread()
		self.update()
		self.delegate?.filterView(self, didChangeFilter: filter.selectedValues.count > 0 ? filter : nil)
	}
	
	@IBAction override func selectAll(_ sender: AnyObject?) {
		filter.selectedValues.formUnion(Set(values.keys))
		self.valueList?.reloadData()
		filterChanged()
	}
	
	@IBAction func selectNone(_ sender: AnyObject?) {
		filter.selectedValues.subtract(Set(values.keys))
		self.valueList?.reloadData()
		filterChanged()
	}
	
	override func viewWillAppear() {
		if let tc = self.valueList?.tableColumn(withIdentifier: "value"), let cell = tc.dataCell as? NSCell {
			cell.font = QBESettings.sharedInstance.monospaceFont ? NSFont.userFixedPitchFont(ofSize: 10.0) : NSFont.userFont(ofSize: 12.0)
		}

		self.reloadData()
		self.update()
		super.viewWillAppear()
	}

	override func viewWillDisappear() {
		self.reloadJob?.cancel()
	}
	
	@IBAction func clearFilter(_ sender: NSObject) {
		self.searchField?.stringValue = ""
		filter.selectedValues = []
		reloadData()
		filterChanged()
	}
}

private extension Dataset {
	/** Returns a histogram of the values for the given expression (each unique value that occurs, and the number of times
	it occurs). */
	func histogram(_ expression: Expression, job: Job, callback: (Fallible<[Value: Int]>) -> ()) {
		let keyColumn = Column("k")
		let countColumn = Column("n")
		let d = self.aggregate([keyColumn: expression], values: [countColumn: Aggregator(map: expression, reduce: .CountAll)])
		d.raster(job) { result in
			switch result {
			case .success(let r):
				var histogram: [Value: Int] = [:]
				for row in r.rows {
					if let k = row[keyColumn], k.isValid {
						histogram[k] = row[countColumn].intValue ?? 1
					}
				}
				callback(.success(histogram))

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}
}
