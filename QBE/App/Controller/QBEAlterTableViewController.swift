import Foundation
import WarpCore

extension RangeReplaceableCollectionType where Index : Comparable {
	mutating func removeAtIndices<S : SequenceType where S.Generator.Element == Index>(indices: S) {
		indices.sort().lazy.reverse().forEach{ removeAtIndex($0) }
	}
}

protocol QBEAlterTableViewDelegate: NSObjectProtocol {
	func alterTableView(view: QBEAlterTableViewController, didCreateTable: QBEMutableData?)
}

class QBEAlterTableViewController: NSViewController, QBEJobDelegate, NSTableViewDataSource, NSTableViewDelegate, NSUserInterfaceValidations {
	@IBOutlet var tableNameField: NSTextField!
	@IBOutlet var progressView: NSProgressIndicator!
	@IBOutlet var progressLabel: NSTextField!
	@IBOutlet var createButton: NSButton!
	@IBOutlet var cancelButton: NSButton!
	@IBOutlet var addColumnButton: NSButton!
	@IBOutlet var removeColumnButton: NSButton!
	@IBOutlet var removeAllColumnsButton: NSButton!
	@IBOutlet var titleLabel: NSTextField!
	@IBOutlet var tableView: NSTableView!

	weak var delegate: QBEAlterTableViewDelegate? = nil
	var definition: QBEDataDefinition = QBEDataDefinition(columnNames: [])
	var warehouse: QBEDataWarehouse? = nil
	var warehouseName: String? = nil
	var createJob: QBEJob? = nil

	required init() {
		super.init(nibName: "QBEAlterTableViewController", bundle: nil)!
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	@IBAction func addColumn(sender: NSObject) {
		var i = 1
		while true {
			let newName = QBEColumn(String(format: NSLocalizedString("Column_%d", comment: ""), self.definition.columnNames.count + i))
			if !self.definition.columnNames.contains(newName) {
				self.definition.columnNames.append(newName)
				self.tableView.reloadData()
				self.updateView()
				return
			}
			++i
		}
	}

	@IBAction func delete(sender: AnyObject?) {
		self.removeColumn(sender)
	}

	func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
		switch anItem.action() {
		case Selector("delete:"):
			return tableView.selectedRowIndexes.count > 0
		default:
			return false
		}
	}

	@IBAction func removeColumn(sender: AnyObject?) {
		let si = tableView.selectedRowIndexes
		self.definition.columnNames.removeAtIndices(si)
		self.tableView.deselectAll(sender)
		self.tableView.reloadData()
		self.updateView()
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row < 0 || row > self.definition.columnNames.count {
			return nil
		}
		let col = self.definition.columnNames[row]

		if let tc = tableColumn {
			switch tc.identifier {
			case "columnName": return col.name
			default: return nil
			}
		}
		return nil
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if row < 0 || row > self.definition.columnNames.count {
			return
		}

		if let tc = tableColumn {
			switch tc.identifier {
			case "columnName":
				let col = QBEColumn(object as! String)
				if !self.definition.columnNames.contains(col) {
					return self.definition.columnNames[row] = col
				}
				else {
					if let w = self.view.window {
						let alert = NSAlert()
						alert.messageText = String(format: NSLocalizedString("Cannot set this column's name to '%@'.", comment: ""), col.name)
						alert.informativeText = String(format: NSLocalizedString("There can only be one column named '%@' in this table.", comment: ""), col.name)
						alert.alertStyle = .WarningAlertStyle
						alert.beginSheetModalForWindow(w, completionHandler: nil)
					}
				}
			default: return
			}
		}
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return self.definition.columnNames.count
	}

	@IBAction func createTable(sender: NSObject) {
		assert(self.createJob == nil, "Cannot start two create table jobs at the same time")
		if let dwh = warehouse {
			let tableName = self.tableNameField.stringValue
			if tableName.isEmpty {
				return
			}
			let mutation = QBEWarehouseMutation.Create(self.tableNameField.stringValue, QBERasterData(data: [], columnNames: self.definition.columnNames))

			if dwh.canPerformMutation(mutation) {
				self.createJob = QBEJob(.UserInitiated)
				self.updateView()
				self.progressView.startAnimation(sender)
				dwh.performMutation(mutation, job: self.createJob!, callback: { (result) -> () in
					QBEAsyncMain {
						self.createJob = nil
						self.progressView.stopAnimation(sender)

						switch result {
						case .Success(let d):
							self.delegate?.alterTableView(self, didCreateTable: d)
							self.dismissController(sender)

						case .Failure(let e):
							let a = NSAlert()
							a.messageText = NSLocalizedString("Cannot create this table", comment: "")
							a.informativeText = e
							a.alertStyle = NSAlertStyle.CriticalAlertStyle
							if let w = self.view.window {
								a.beginSheetModalForWindow(w, completionHandler: { (response) -> Void in
								})
							}
							self.updateView()
						}
					}
				})
			}
			else {
				let a = NSAlert()
				// TODO localize, make more specific
				a.messageText = NSLocalizedString("Cannot create this table", comment: "")
				a.informativeText = NSLocalizedString("The data source does not allow creation of new tables.", comment: "")
				if let w = self.view.window {
					a.beginSheetModalForWindow(w, completionHandler: { (response) -> Void in
						self.dismissController(sender)
					})
					updateView()
					return
				}
			}
		}
	}

	func updateView() {
		QBEAssertMainThread()
		let working = createJob != nil
		cancelButton.enabled = !working
		createButton.enabled = !working && !self.tableNameField.stringValue.isEmpty && (!(self.warehouse?.hasFixedColumns ?? true) || !self.definition.columnNames.isEmpty)
		addColumnButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		removeColumnButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false) && !self.definition.columnNames.isEmpty && tableView.selectedRowIndexes.count > 0
		removeAllColumnsButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false) && !self.definition.columnNames.isEmpty && tableView.selectedRowIndexes.count > 0
		tableView.enabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		progressView.hidden = !working
		progressLabel.hidden = !working
		tableNameField.enabled = !working

		if let title = self.warehouseName {
			self.titleLabel.stringValue = String(format: NSLocalizedString("Create a new table in %@.", comment: ""), title)
		}
		else {
			self.titleLabel.stringValue = NSLocalizedString("Create a new table", comment: "")
		}
	}

	func tableViewSelectionDidChange(notification: NSNotification) {
		self.updateView()
	}

	@IBAction func tableNameDidChange(sender: NSObject) {
		self.updateView()
	}

	@IBAction func removeAllColumns(sender: NSObject) {
		self.definition.columnNames.removeAll()
		self.tableView.reloadData()
		self.updateView()
	}

	override func viewWillAppear() {
		// Are we going to create a table? Then check if the pasteboard has a table definition for us we can propose
		if self.definition.columnNames.isEmpty && (self.warehouse?.hasFixedColumns ?? false) {
			let pb = NSPasteboard(name: QBEDataDefinition.pasteboardName)
			if let data = pb.dataForType(QBEDataDefinition.pasteboardName), let def = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? QBEDataDefinition {
				self.definition = def
			}
		}

		self.tableView.reloadData()
		self.updateView()
	}

	func job(job: AnyObject, didProgress: Double) {
	}
}