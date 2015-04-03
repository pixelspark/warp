import Foundation

internal class QBEPrestoSourceStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDataSource, NSComboBoxDelegate {
	let step: QBEPrestoSourceStep?
	var tableNames: [String]?
	var schemaNames: [String]?
	var catalogNames: [String]?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var urlField: NSTextField?
	@IBOutlet var catalogField: NSComboBox?
	@IBOutlet var schemaField: NSComboBox?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEPrestoSourceStep {
			self.step = s
			super.init(nibName: "QBEPrestoSourceStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEPrestoSourceStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			s.url = urlField?.stringValue ?? s.url
			s.catalogName = catalogField?.stringValue ?? s.catalogName
			s.schemaName = schemaField?.stringValue ?? s.schemaName
			updateView()
			self.delegate?.suggestionsView(self, previewStep: s)
		}
	}
	
	private func updateView() {
		if let s = step {
			urlField?.stringValue = s.url ?? ""
			catalogField?.stringValue = s.catalogName ?? ""
			schemaField?.stringValue = s.schemaName ?? ""
			
			s.catalogNames({ (catalogs) -> () in
				QBEAsyncMain {
					self.catalogNames = Array(catalogs)
					self.catalogField?.reloadData()
				}
			})
			
			s.schemaNames({ (schemas) -> () in
				QBEAsyncMain {
					self.schemaNames = Array(schemas)
					self.schemaField?.reloadData()
				}
			})
			
			s.tableNames({ (names) -> () in
				QBEAsyncMain {
					self.tableNames = Array(names)
					self.tableView?.reloadData()
					
					if self.tableNames != nil {
						let currentTable = s.tableName
						for i in 0..<self.tableNames!.count {
							if self.tableNames![i]==currentTable {
								self.tableView?.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
								break
							}
						}
					}
				}
			})
		}
	}
	
	internal func tableViewSelectionDidChange(notification: NSNotification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			step?.tableName = selectedName
			delegate?.suggestionsView(self, previewStep: step)
		}
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return tableNames?.count ?? 0
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return tableNames?[row] ?? ""
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		if aComboBox == catalogField {
			return catalogNames?.count ?? 0
		}
		else if aComboBox == schemaField {
			return schemaNames?.count ?? 0
		}
		return 0
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		if aComboBox == catalogField {
			return catalogNames?[index] ?? ""
		}
		else if aComboBox == schemaField {
			return schemaNames?[index] ?? ""
		}
		return ""
	}
}