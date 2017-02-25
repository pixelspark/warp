/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

extension RangeReplaceableCollection where Index : Comparable {
	mutating func removeAtIndices<S : Sequence>(_ indices: S) where S.Iterator.Element == Index {
		indices.sorted().lazy.reversed().forEach{ remove(at: $0) }
	}
}

protocol QBEAlterTableViewDelegate: NSObjectProtocol {
	func alterTableView(_ view: QBEAlterTableViewController, didAlterTable: MutableDataset?)
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
	var definition: DatasetDefinition = DatasetDefinition(columns: [])
	var warehouse: Warehouse? = nil
	var mutableDataset: MutableDataset? = nil
	var warehouseName: String? = nil
	var createJob: Job? = nil

	var isAltering: Bool { return mutableDataset != nil }

	required init() {
		super.init(nibName: "QBEAlterTableViewController", bundle: nil)!
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	@IBAction func addColumn(_ sender: NSObject) {
		var i = 1
		while true {
			let newName = Column(String(format: NSLocalizedString("Column_%d", comment: ""), self.definition.columns.count + i))
			if !self.definition.columns.contains(newName) {
				self.definition.columns.append(newName)
				self.tableView.reloadData()
				self.updateView()
				return
			}
			i += 1
		}
	}

	@IBAction func delete(_ sender: AnyObject?) {
		self.removeColumn(sender)
	}

	func validate(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return self.validateUserInterfaceItem(item)
	}

	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		switch item.action {
		case .some(#selector(QBEAlterTableViewController.delete(_:))):
			return tableView.selectedRowIndexes.count > 0
		default:
			return false
		}
	}

	@IBAction func removeColumn(_ sender: AnyObject?) {
		let si = tableView.selectedRowIndexes
		self.definition.columns.removeAtIndices(si)
		self.tableView.deselectAll(sender)
		self.tableView.reloadData()
		self.updateView()
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
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

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
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
						alert.alertStyle = .warning
						alert.beginSheetModal(for: w, completionHandler: nil)
					}
				}
			default: return
			}
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return self.definition.columns.count
	}

	@IBAction func createOrAlterTable(_ sender: NSObject) {
		if isAltering {
			self.alterTable(sender)
		}
		else {
			self.createTable(sender)
		}
	}

	private func alterTable(_ sender: NSObject) {
		assert(self.createJob == nil, "Cannot start two create table jobs at the same time")

		if let md = self.mutableDataset {
			let mutation = DatasetMutation.alter(self.definition)

			if md.canPerformMutation(mutation.kind) {
				self.createJob = Job(.userInitiated)
				self.updateView()
				self.progressView.startAnimation(sender)

				md.performMutation(mutation, job: self.createJob!) { result in
					asyncMain {
						self.createJob = nil
						self.updateView()
						self.progressView.stopAnimation(sender)

						switch result {
						case .success:
							self.delegate?.alterTableView(self, didAlterTable: md)
							self.dismiss(sender)

						case .failure(let e):
							NSAlert.showSimpleAlert(NSLocalizedString("Could not change this table", comment: ""), infoText: e, style: .critical, window: self.view.window)
						}
					}
				}
			}
		}
	}

	private func createTable(_ sender: NSObject) {
		assert(self.createJob == nil, "Cannot start two create table jobs at the same time")
		if let dwh = warehouse {
			let tableName = self.tableNameField.stringValue
			if tableName.isEmpty && dwh.hasNamedTables {
				return
			}
			let mutation = WarehouseMutation.create(self.tableNameField.stringValue, RasterDataset(data: [], columns: self.definition.columns))

			if dwh.canPerformMutation(mutation.kind) {
				self.createJob = Job(.userInitiated)
				self.updateView()
				self.progressView.startAnimation(sender)
				dwh.performMutation(mutation, job: self.createJob!, callback: { (result) -> () in
					asyncMain {
						self.createJob = nil
						self.progressView.stopAnimation(sender)

						switch result {
						case .success(let d):
							self.delegate?.alterTableView(self, didAlterTable: d)
							self.dismiss(sender)

						case .failure(let e):
							let a = NSAlert()
							a.messageText = NSLocalizedString("Cannot create this table", comment: "")
							a.informativeText = e
							a.alertStyle = .critical
							if let w = self.view.window {
								a.beginSheetModal(for: w, completionHandler: { (response) -> Void in
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
					a.beginSheetModal(for: w, completionHandler: { (response) -> Void in
						self.dismiss(sender)
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
		cancelButton.isEnabled = !working
		createButton.isEnabled = !working && (isAltering || !needTableName || !self.tableNameField.stringValue.isEmpty) && (!(self.warehouse?.hasFixedColumns ?? true) || !self.definition.columns.isEmpty)
		addColumnButton.isEnabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		removeColumnButton.isEnabled = !working && (self.warehouse?.hasFixedColumns ?? false) && !self.definition.columns.isEmpty && tableView.selectedRowIndexes.count > 0
		removeAllColumnsButton.isEnabled = !working && (self.warehouse?.hasFixedColumns ?? false) && !self.definition.columns.isEmpty && tableView.selectedRowIndexes.count > 0
		tableView.isEnabled = !working && (self.warehouse?.hasFixedColumns ?? false)
		progressView.isHidden = !working
		progressLabel.isHidden = !working
		tableNameField.isEnabled = !working && !isAltering && needTableName
		createButton.title = NSLocalizedString(self.isAltering ? "Modify table" : "Create table", comment: "")

		if let title = self.warehouseName {
			self.titleLabel.stringValue = String(format: NSLocalizedString(isAltering ? "Modify table %@" : "Create a new table in %@.", comment: ""), title)
		}
		else {
			self.titleLabel.stringValue = NSLocalizedString(isAltering ? "Modify table" : "Create a new table", comment: "")
		}
	}

	override func controlTextDidChange(_ obj: Notification) {
		self.updateView()
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		self.updateView()
	}

	@IBAction func tableNameDidChange(_ sender: NSObject) {
		self.updateView()
	}

	@IBAction func removeAllColumns(_ sender: NSObject) {
		self.definition.columns.removeAll()
		self.tableView.reloadData()
		self.updateView()
	}

	override func viewWillAppear() {
		// Are we going to create a table? Then check if the pasteboard has a table definition for us we can propose
		if self.definition.columns.isEmpty && (self.warehouse?.hasFixedColumns ?? false) {
			let pb = NSPasteboard(name: DatasetDefinition.pasteboardName)
			if let data = pb.data(forType: DatasetDefinition.pasteboardName), let def = NSKeyedUnarchiver.unarchiveObject(with: data) as? DatasetDefinition {
				self.definition = def
			}
		}

		self.tableView.reloadData()
		self.updateView()
	}

	func job(_ job: AnyObject, didProgress: Double) {
	}
}
