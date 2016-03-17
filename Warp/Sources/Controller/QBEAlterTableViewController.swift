import Foundation
import WarpCore

extension RangeReplaceableCollectionType where Index : Comparable {
	mutating func removeAtIndices<S : SequenceType where S.Generator.Element == Index>(indices: S) {
		indices.sort().lazy.reverse().forEach{ removeAtIndex($0) }
	}
}

protocol QBEAlterTableViewDelegate: NSObjectProtocol {
	func alterTableView(view: QBEAlterTableViewController, didAlterTable: MutableData?)
}

class QBEAlterTableViewController: NSViewController, JobDelegate, NSTableViewDataSource, NSTableViewDelegate, NSUserInterfaceValidations {
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
	var definition: DataDefinition = DataDefinition(columns: [])
	var warehouse: Warehouse? = nil
	var mutableData: MutableData? = nil
	var warehouseName: String? = nil
	var createJob: Job? = nil

	var isAltering: Bool { return mutableData != nil }

	required init() {
		super.init(nibName: "QBEAlterTableViewController", bundle: nil)!
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	@IBAction func addColumn(sender: NSObject) {
		var i = 1
		while true {
			let newName = Column(String(format: NSLocalizedString("Column_%d", comment: ""), self.definition.columns.count + i))
			if !self.definition.columns.contains(newName) {
				self.definition.columns.append(newName)
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
		self.definition.columns.removeAtIndices(si)
		self.tableView.deselectAll(sender)
		self.tableView.reloadData()
		self.updateView()
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row < 0 || row > self.definition.columns.count {
			return nil
		}
		let col = self.definition.columns[row]

		if let tc = tableColumn {
			switch tc.identifier {
			case "columnName": return col.name
			default: return nil
			}
		}
		return nil
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if row < 0 || row > self.definition.columns.count {
			return
		}

		if let tc = tableColumn {
			switch tc.identifier {
			case "columnName":
				let col = Column(object as! String)
				if !self.definition.columns.contains(col) {
					return self.definition.columns[row] = col
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
		return self.definition.columns.count
	}

	@IBAction func createOrAlterTable(sender: NSObject) {
		if isAltering {
			self.alterTable(sender)
		}
		else {
			self.createTable(sender)
		}
	}

	private func alterTable(sender: NSObject) {
		assert(self.createJob == nil, "Cannot start two create table jobs at the same time")

		if let md = self.mutableData {
			let mutation = DataMutation.Alter(self.definition)
			if md.canPerformMutation(mutation) {
				self.createJob = Job(.UserInitiated)
				self.updateView()
				self.progressView.startAnimation(sender)

				md.performMutation(mutation, job: self.createJob!) { result in
					asyncMain {
						self.createJob = nil
						self.updateView()
						self.progressView.stopAnimation(sender)

						switch result {
						case .Success:
							self.delegate?.alterTableView(self, didAlterTable: md)
							self.dismissController(sender)

						case .Failure(let e):
							NSAlert.showSimpleAlert(NSLocalizedString("Could not change this table", comment: ""), infoText: e, style: .CriticalAlertStyle, window: self.view.window)
						}
					}
				}
			}
		}
	}

	private func createTable(sender: NSObject) {
		assert(self.createJob == nil, "Cannot start two create table jobs at the same time")
		if let dwh = warehouse {
			let tableName = self.tableNameField.stringValue
			if tableName.isEmpty && dwh.hasNamedTables {
				return
			}
			let mutation = WarehouseMutation.Create(self.tableNameField.stringValue, RasterData(data: [], columns: self.definition.columns))

			if dwh.canPerformMutation(mutation) {
				self.createJob = Job(.UserInitiated)
				self.updateView()
				self.progressView.startAnimation(sender)
				dwh.performMutation(mutation, job: self.createJob!, callback: { (result) -> () in
					asyncMain {
						self.createJob = nil
						self.progressView.stopAnimation(sender)

						switch result {
						case .Success(let d):
							self.delegate?.alterTableView(self, didAlterTable: d)
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
		assertMainThread()

		let working = createJob != nil
		let needTableName = (self.warehouse?.hasNamedTables ?? true)
		cancelButton.enabled = !working
		createButton.enabled = !working && (isAltering || !needTableName || !self.tableNameField.stringValue.isEmpty) && (!(self.warehouse?.hasFixedColumns ?? true) || !self.definition.columns.isEmpty)
		addColumnButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		removeColumnButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false) && !self.definition.columns.isEmpty && tableView.selectedRowIndexes.count > 0
		removeAllColumnsButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false) && !self.definition.columns.isEmpty && tableView.selectedRowIndexes.count > 0
		tableView.enabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		progressView.hidden = !working
		progressLabel.hidden = !working
		tableNameField.enabled = !working && !isAltering && needTableName
		createButton.title = NSLocalizedString(self.isAltering ? "Modify table" : "Create table", comment: "")

		if let title = self.warehouseName {
			self.titleLabel.stringValue = String(format: NSLocalizedString(isAltering ? "Modify table %@" : "Create a new table in %@.", comment: ""), title)
		}
		else {
			self.titleLabel.stringValue = NSLocalizedString(isAltering ? "Modify table" : "Create a new table", comment: "")
		}
	}

	func tableViewSelectionDidChange(notification: NSNotification) {
		self.updateView()
	}

	@IBAction func tableNameDidChange(sender: NSObject) {
		self.updateView()
	}

	@IBAction func removeAllColumns(sender: NSObject) {
		self.definition.columns.removeAll()
		self.tableView.reloadData()
		self.updateView()
	}

	override func viewWillAppear() {
		// Are we going to create a table? Then check if the pasteboard has a table definition for us we can propose
		if self.definition.columns.isEmpty && (self.warehouse?.hasFixedColumns ?? false) {
			let pb = NSPasteboard(name: DataDefinition.pasteboardName)
			if let data = pb.dataForType(DataDefinition.pasteboardName), let def = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? DataDefinition {
				self.definition = def
			}
		}

		self.tableView.reloadData()
		self.updateView()
	}

	func job(job: AnyObject, didProgress: Double) {
	}
}