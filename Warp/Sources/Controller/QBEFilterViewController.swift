import Cocoa
import WarpCore

protocol QBEFilterViewDelegate: NSObjectProtocol {
	func filterView(view: QBEFilterViewController, applyFilter: QBEFilterSet?, permanent: Bool)
}

class QBEFilterViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, QBEJobDelegate {
	@IBOutlet weak var searchField: NSSearchField?
	@IBOutlet weak var valueList: NSTableView?
	@IBOutlet weak var progressBar: NSProgressIndicator!
	@IBOutlet weak var addFilterButton: NSButton!
	@IBOutlet weak var applyFilterButton: NSButton!
	@IBOutlet weak var clearFilterButton: NSButton!
	private var lastSearch: String? = nil
	weak var delegate: QBEFilterViewDelegate?
	
	var data: QBEData?

	/* Data set used for searching. Can be the full data set if the other data set is an example one. If this is nil, 
	the normal one is used. */
	var searchData: QBEData?
	var column: QBEColumn?
	
	private var reloadJob: QBEJob? = nil
	private var values: [QBEValue] = []
	
	var filter: QBEFilterSet = QBEFilterSet() { didSet {
		QBEAssertMainThread()
		reloadData()
	} }
	
	func job(job: AnyObject, didProgress: Double) {3
		self.updateProgress()
	}

	deinit {
		QBEAssertMainThread()
	}
	
	private func updateProgress() {
		QBEAssertMainThread()
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
		QBEAssertMainThread()
		reloadJob?.cancel()
		reloadJob = nil
		
		if let d = data, let c = column {
			var filteredData = d
			if let search = searchField?.stringValue where !search.isEmpty {
				lastSearch = search
				filteredData = searchData ?? filteredData
				filteredData = filteredData.filter(QBEBinaryExpression(first: QBELiteralExpression(QBEValue(search)), second: QBESiblingExpression(columnName: c), type: QBEBinary.MatchesRegex))
			}

			let job = QBEJob(QBEQoS.UserInitiated)
			reloadJob = job
			reloadJob?.addObserver(self)
			self.updateProgress()
			
			filteredData.unique(QBESiblingExpression(columnName: c), job: job, callback: { [weak self] (fallibleValues) -> () in
				switch fallibleValues {
					case .Success(let values):
						var valuesSorted = Array(values)
						valuesSorted.sortInPlace({return $0.stringValue < $1.stringValue})
						QBEAsyncMain { [weak self] in
							if !job.cancelled {
								self?.values = valuesSorted
								self?.reloadJob = nil
								self?.updateProgress()
								self?.valueList?.reloadData()
							}
						}
					
					case .Failure(let e):
						QBELog("Error fetching unique values: \(e)")
				}
			})
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
						filter.selectedValues.insert(values[row])
					}
					else {
						filter.selectedValues.remove(values[row])
					}
					filterChanged()
				
				default:
					break // Ignore
			}
		}
	}
	
	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row < values.count {
			switch tableColumn?.identifier ?? "" {
				case "value":
					let value = values[row]
					switch value {
						case .EmptyValue:
							return NSLocalizedString("(missing)", comment: "")

						case .InvalidValue:
							return NSLocalizedString("(error)", comment: "")

						default:
							return QBEAppDelegate.sharedInstance.locale.localStringFor(values[row])
					}
				
				case "selected":
					return NSNumber(bool: filter.selectedValues.contains(values[row]))
				
				default:
					return nil
			}
		}
		return nil
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
		QBEAssertMainThread()
		self.valueList?.reloadData()
		let hasFilter = filter.selectedValues.count > 0
		self.addFilterButton?.enabled = hasFilter
		self.applyFilterButton?.enabled = hasFilter
		self.clearFilterButton?.enabled = hasFilter
	}
	
	@IBAction override func selectAll(sender: AnyObject?) {
		filter.selectedValues.unionInPlace(values)
		self.valueList?.reloadData()
		filterChanged()
	}
	
	@IBAction func selectNone(sender: AnyObject?) {
		filter.selectedValues.subtractInPlace(values)
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