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

class QBEAlterTableViewController: NSViewController, QBEJobDelegate, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet var tableNameField: NSTextField!
	@IBOutlet var progressView: NSProgressIndicator!
	@IBOutlet var progressLabel: NSTextField!
	@IBOutlet var createButton: NSButton!
	@IBOutlet var cancelButton: NSButton!
	@IBOutlet var addColumnButton: NSButton!
	@IBOutlet var removeColumnButton: NSButton!
	@IBOutlet var titleLabel: NSTextField!
	@IBOutlet var tableView: NSTableView!

	weak var delegate: QBEAlterTableViewDelegate? = nil
	var columns: [QBEColumn] = []
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
		self.columns.append(QBEColumn(String(format: NSLocalizedString("Column_%d", comment: ""), self.columns.count)))
		self.updateView()
	}

	@IBAction func removeColumn(sender: NSObject) {
		let si = tableView.selectedRowIndexes
		self.columns.removeAtIndices(si)
		self.updateView()
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row < 0 || row > self.columns.count {
			return nil
		}
		let col = self.columns[row]

		if let tc = tableColumn {
			switch tc.identifier {
			case "columnName": return col.name
			default: return nil
			}
		}
		return nil
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if row < 0 || row > self.columns.count {
			return
		}

		if let tc = tableColumn {
			switch tc.identifier {
			case "columnName": return self.columns[row] = QBEColumn(object as! String)
			default: return
			}
		}
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return self.columns.count
	}

	@IBAction func createTable(sender: NSObject) {
		assert(self.createJob == nil, "Cannot start two create table jobs at the same time")
		if let dwh = warehouse {
			let tableName = self.tableNameField.stringValue
			if tableName.isEmpty {
				return
			}
			let mutation = QBEWarehouseMutation.Create(self.tableNameField.stringValue, QBERasterData(data: [], columnNames: self.columns))

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
		createButton.enabled = !working && !self.tableNameField.stringValue.isEmpty && (!(self.warehouse?.hasFixedColumns ?? true) || self.columns.count > 0)
		addColumnButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		removeColumnButton.enabled = !working && (self.warehouse?.hasFixedColumns ?? false)
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
		self.tableView.reloadData()
	}

	@IBAction func tableNameDidChange(sender: NSObject) {
		self.updateView()
	}

	override func viewWillAppear() {
		self.updateView()
	}

	func job(job: AnyObject, didProgress: Double) {
	}
}