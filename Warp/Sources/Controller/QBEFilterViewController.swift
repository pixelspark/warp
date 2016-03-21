import Cocoa
import WarpCore

protocol QBEFilterViewDelegate: NSObjectProtocol {
	func filterView(view: QBEFilterViewController, applyFilter: FilterSet?, permanent: Bool)
}

class QBEFilterViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, JobDelegate {
	@IBOutlet weak var searchField: NSSearchField?
	@IBOutlet weak var valueList: NSTableView?
	@IBOutlet weak var progressBar: NSProgressIndicator!
	@IBOutlet weak var addFilterButton: NSButton!
	@IBOutlet weak var applyFilterButton: NSButton!
	@IBOutlet weak var clearFilterButton: NSButton!
	private var lastSearch: String? = nil
	weak var delegate: QBEFilterViewDelegate?
	
	var data: Data?

	/* Data set used for searching. Can be the full data set if the other data set is an example one. If this is nil, 
	the normal one is used. */
	var searchData: Data?
	var column: Column?
	
	private var reloadJob: Job? = nil
	private var values = OrderedDictionary<Value, Int>()
	private var valueCount = 0
	
	var filter: FilterSet = FilterSet() { didSet {
		assertMainThread()
		reloadData()
	} }
	
	func job(job: AnyObject, didProgress: Double) {
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
			self.progressBar?.hidden = false
			self.valueList?.enabled = false
			self.valueList?.layer?.opacity = 0.5
			let p = j.progress
			self.progressBar?.indeterminate = (p <= 0.0)
			self.progressBar?.doubleValue = p * 1000
		}
		else {
			self.progressBar?.hidden = true
			self.valueList?.enabled = true
			self.valueList?.layer?.opacity = 1.0
		}
	}
	
	private func reloadData() {
		assertMainThread()
		reloadJob?.cancel()
		reloadJob = nil
		
		if let d = data, let c = column {
			var filteredData = d
			if let search = searchField?.stringValue where !search.isEmpty {
				lastSearch = search
				filteredData = searchData ?? filteredData
				filteredData = filteredData.filter(Comparison(first: Literal(Value(search)), second: Sibling(c), type: Binary.MatchesRegex))
			}

			let job = Job(.UserInitiated)
			reloadJob = job
			reloadJob?.addObserver(self)
			self.updateProgress()

			filteredData.histogram(Sibling(c), job: job) { result in
				switch result {
					case .Success(let values):
						var ordered = OrderedDictionary(dictionaryInAnyOrder: values)
						ordered.sortKeysInPlace { a,b in return a.stringValue < b.stringValue }
						var count = 0
						ordered.forEach { _, v in
							count += v
						}

						asyncMain { [weak self] in
							if !job.cancelled {
								self?.values = ordered
								self?.reloadJob = nil
								self?.valueCount = count
								self?.updateProgress()
								self?.valueList?.reloadData()
							}
						}
					
					case .Failure(let e):
						trace("Error fetching unique values: \(e)")
				}
			}
		}
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return values.count
	}
	
	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if row < values.count {
			switch tableColumn?.identifier ?? "" {
				case "selected":
					if let b = object?.boolValue where b {
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
	
	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row < values.count {
			let value = values[row].0

			switch tableColumn?.identifier ?? "" {
				case "value":
					switch value {
						case .EmptyValue:
							return NSLocalizedString("(missing)", comment: "")

						case .InvalidValue:
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
					return NSNumber(bool: filter.selectedValues.contains(value))

				default:
					return nil
			}
		}
		return nil
	}

	func tableView(tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
		for d in tableView.sortDescriptors.reverse() {
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
	
	@IBAction func applyFilter(sender: NSObject) {
		self.delegate?.filterView(self, applyFilter: filter.selectedValues.count > 0 ? filter : nil, permanent: false)
	}
	
	@IBAction func searchChanged(sender: NSObject) {
		if let search = searchField?.stringValue where !search.isEmpty && search != lastSearch {
			reloadData()
		}
	}
	
	@IBAction func addFilterAsStep(sender: NSObject) {
		if filter.selectedValues.count > 0 {
			self.delegate?.filterView(self, applyFilter: filter, permanent: true)
		}
	}
	
	private func filterChanged() {
		assertMainThread()
		self.valueList?.reloadData()
		let hasFilter = filter.selectedValues.count > 0
		self.addFilterButton?.enabled = hasFilter
		self.applyFilterButton?.enabled = hasFilter
		self.clearFilterButton?.enabled = hasFilter
	}
	
	@IBAction override func selectAll(sender: AnyObject?) {
		filter.selectedValues.unionInPlace(values.keys)
		self.valueList?.reloadData()
		filterChanged()
	}
	
	@IBAction func selectNone(sender: AnyObject?) {
		filter.selectedValues.subtractInPlace(values.keys)
		self.valueList?.reloadData()
		filterChanged()
	}
	
	override func viewWillAppear() {
		if let tc = self.valueList?.tableColumnWithIdentifier("value"), let cell = tc.dataCell as? NSCell {
			cell.font = QBESettings.sharedInstance.monospaceFont ? NSFont.userFixedPitchFontOfSize(10.0) : NSFont.userFontOfSize(12.0)
		}

		self.reloadData()
		self.filterChanged()
		super.viewWillAppear()
	}

	override func viewWillDisappear() {
		self.reloadJob?.cancel()
	}
	
	@IBAction func clearFilter(sender: NSObject) {
		self.searchField?.stringValue = ""
		filter.selectedValues = []
		self.delegate?.filterView(self, applyFilter: nil, permanent: false)
		reloadData()
		filterChanged()
	}
}

private extension Data {
	/** Returns a histogram of the values for the given expression (each unique value that occurs, and the number of times
	it occurs). */
	func histogram(expression: Expression, job: Job, callback: (Fallible<[Value: Int]>) -> ()) {
		let keyColumn = Column("k")
		let countColumn = Column("n")
		let d = self.aggregate([keyColumn: expression], values: [countColumn: Aggregator(map: expression, reduce: .Count)])
		d.raster(job) { result in
			switch result {
			case .Success(let r):
				var histogram: [Value: Int] = [:]
				for row in r.rows {
					histogram[row[keyColumn]] = row[countColumn].intValue
				}
				callback(.Success(histogram))

			case .Failure(let e):
				callback(.Failure(e))
			}
		}
	}
}