/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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
				filteredDataset = filteredDataset.filter(Comparison(first: Literal(Value(search)), second: Sibling(c), type: Binary.matchesRegex))
			}

			let job = Job(.userInitiated)
			reloadJob = job
			reloadJob?.addObserver(self)
			self.updateProgress()
			let locale = QBEAppDelegate.sharedInstance.locale ?? Language()

			filteredDataset.histogram(Sibling(c), job: job) { [weak self] result in
				switch result {
					case .success(let values):
						var ordered = OrderedDictionary(dictionaryInAnyOrder: values)

						ordered.sortKeysInPlace { a,b in return locale.localStringFor(a)  < locale.localStringFor(b) }
						var count = 0
						ordered.forEach { _, v in
							count += v
						}

						asyncMain {
							let s: QBEFilterViewController? = self
							if !job.isCancelled {
								s?.values = ordered
								s?.valueCount = count
							}
						}

					case .failure(let e):
						trace("Error fetching unique values: \(e)")
				}

				asyncMain {
					let s: QBEFilterViewController? = self
					if !job.isCancelled {
						s?.reloadJob = nil
						s?.updateProgress()
						s?.valueList?.reloadData()
					}
				}
			}
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return values.count
	}
	
	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		if row < values.count {
			switch tableColumn?.identifier ?? "" {
				case "selected":
					if (object as? Bool) ?? false {
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
	
	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
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
						let averageValueCount = Double(self.valueCount) / Double(self.values.count)
						return max(1.0, (Double(values[row].1) / averageValueCount) * 25.0)
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
								return a < b
							}
							else {
								return a > b
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

	override func selectAll(_ sender: Any?) {
		filter.selectedValues.formUnion(Set(values.keys))
		self.valueList?.reloadData()
		filterChanged()
	}
	
	func selectNone(_ sender: Any?) {
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
	func histogram(_ expression: Expression, job: Job, callback: @escaping (Fallible<[Value: Int]>) -> ()) {
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
