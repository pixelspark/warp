import Foundation
import WarpCore

internal class QBEPrestoSourceStepView: QBEStepViewControllerFor<QBEPrestoSourceStep>, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDataSource, NSComboBoxDelegate {
	var tableNames: [String]?
	var schemaNames: [String]?
	var catalogNames: [String]?
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var urlField: NSTextField?
	@IBOutlet var catalogField: NSComboBox?
	@IBOutlet var schemaField: NSComboBox?

	required init?(step: QBEStep, delegate: QBEStepViewDelegate) {
		super.init(step: step, delegate: delegate, nibName: "QBEPrestoSourceStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	@IBAction func update(sender: NSObject) {
		step.url = urlField?.stringValue ?? step.url
		step.catalogName = catalogField?.stringValue ?? step.catalogName
		step.schemaName = schemaField?.stringValue ?? step.schemaName
		updateView()
		self.delegate?.stepView(self, didChangeConfigurationForStep: step)
	}
	
	private func updateView() {
		let job = QBEJob(.UserInitiated)

		urlField?.stringValue = step.url ?? ""
		catalogField?.stringValue = step.catalogName ?? ""
		schemaField?.stringValue = step.schemaName ?? ""
		
		step.catalogNames(job) { (catalogsFallible) -> () in
			catalogsFallible.maybe {(catalogs) in
				QBEAsyncMain {
					self.catalogNames = Array(catalogs)
					self.catalogField?.reloadData()
				}
			}
		}
		
		step.schemaNames(job) { (schemasFallible) -> () in
			schemasFallible.maybe { (schemas) in
				QBEAsyncMain {
					self.schemaNames = Array(schemas)
					self.schemaField?.reloadData()
				}
			}
		}
		
		step.tableNames(job) { (namesFallible) -> () in
			namesFallible.maybe { (names) in
				QBEAsyncMain {
					self.tableNames = Array(names)
					self.tableView?.reloadData()
					
					if self.tableNames != nil {
						let currentTable = self.step.tableName
						for i in 0..<self.tableNames!.count {
							if self.tableNames![i]==currentTable {
								self.tableView?.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
								break
							}
						}
					}
				}
			}
		}
	}
	
	internal func tableViewSelectionDidChange(notification: NSNotification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			step.tableName = selectedName
			delegate?.stepView(self, didChangeConfigurationForStep: step)
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