import Foundation
import Cocoa

internal class QBEPostgresStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate, NSComboBoxDataSource {
	let step: QBEPostgresSourceStep?
	var tableNames: [QBEPostgresTableName]?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var userField: NSTextField?
	@IBOutlet var passwordField: NSTextField?
	@IBOutlet var hostField: NSTextField?
	@IBOutlet var portField: NSTextField?
	@IBOutlet var databaseField: NSComboBox?
	private var databaseNames: [String]?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEPostgresSourceStep {
			self.step = s
			super.init(nibName: "QBEPostgresStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEPostgresStepView", bundle: nil)
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
	
	@IBAction func updateStep(sender: NSObject) {
		if let s = step {
			var changed = false
			
			if let u = self.userField?.stringValue where u != s.user {
				s.user = u
				changed = true
			}
			
			if let u = self.passwordField?.stringValue where u != s.password {
				s.password = u
				changed = true
			}
			
			if let u = self.hostField?.stringValue where u != s.host {
				s.host = u
				changed = true
			}
			
			if let u = self.portField?.stringValue where Int(u) != s.port {
				s.port = Int(u)
				changed = true
			}
			
			if let u = self.databaseField?.stringValue where u != s.databaseName {
				s.databaseName = u
				changed = true
			}
			
			if changed {
				delegate?.suggestionsView(self, previewStep: step)
				updateView()
			}
		}
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		return databaseNames?.count ?? 0
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		return databaseNames?[index] ?? ""
	}
	
	private func updateView() {
		let job = QBEJob(.UserInitiated)
		
		if let s = step {
			self.userField?.stringValue = s.user ?? ""
			self.passwordField?.stringValue = s.password ?? ""
			self.hostField?.stringValue = s.host ?? ""
			self.portField?.stringValue = "\(s.port ?? 0)"
			self.databaseField?.stringValue = s.databaseName ?? ""
			
			tableNames = []
			tableView?.reloadData()
			if let database = s.database {
				job.async {
					// Update list of databases
					database.databases({(dbs) -> () in
						dbs.use { (databaseNames) -> () in
							QBEAsyncMain {
								self.databaseNames = databaseNames
								self.databaseField?.reloadData()
							}
							
							database.tables({(ts) -> () in
								ts.use { (tableNames) -> () in
									QBEAsyncMain {
										self.tableNames = tableNames
										self.tableView?.reloadData()
										
										// Select current table
										if self.tableNames != nil {
											for i in 0..<self.tableNames!.count {
												let tn = self.tableNames![i]
												if tn.table == s.tableName && tn.schema == s.schemaName {
													self.tableView?.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
												}
											}
										}
									}
								}
							})
						}
					})
				}
			}
		}
	}
	
	internal func tableViewSelectionDidChange(notification: NSNotification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			if step?.tableName != selectedName.table || step?.schemaName != selectedName.schema {
				step?.tableName = selectedName.table
				step?.schemaName = selectedName.schema
				delegate?.suggestionsView(self, previewStep: step)
			}
		}
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return tableNames?.count ?? 0
	}
	
	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let identifier = tableColumn?.identifier {
			switch identifier {
				case "schemaName": return tableNames?[row].schema ?? ""
				case "tableName": return tableNames?[row].table ?? ""
				default: fatalError("Invalid table column identifier")
			}
		}
		return nil
	}
}