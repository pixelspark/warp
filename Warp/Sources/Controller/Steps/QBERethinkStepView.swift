import Foundation
import WarpCore
import Rethink

internal class QBERethinkStepView: QBEConfigurableStepViewControllerFor<QBERethinkSourceStep>, NSTableViewDataSource, NSTableViewDelegate, QBEAlterTableViewDelegate {
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var addColumnTextField: NSTextField!
	@IBOutlet var serverField: NSTextField!
	@IBOutlet var portField: NSTextField!
	@IBOutlet var authenticationKeyField: NSTextField!
	@IBOutlet var usernameField: NSTextField!
	@IBOutlet var passwordField: NSTextField!
	@IBOutlet var infoLabel: NSTextField?
	@IBOutlet var infoProgress: NSProgressIndicator?
	@IBOutlet var infoIcon: NSImageView?
	@IBOutlet var createTableButton: NSButton?
	@IBOutlet var authenticationTypeSwitch: NSSegmentedControl?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBERethinkStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}

	private var checkConnectionJob: Job? = nil { willSet {
		if let o = checkConnectionJob {
			o.cancel()
		}
	} }

	private func updateView() {
		self.checkConnectionJob = Job(.userInitiated)

		tableView?.reloadData()
		self.serverField?.stringValue = self.step.server
		self.portField?.stringValue = "\(self.step.port)"
		self.authenticationKeyField?.stringValue = self.step.authenticationKey ?? ""
		self.usernameField?.stringValue = self.step.username

		if let d = self.step.password.stringValue {
			self.passwordField?.stringValue = d
		}
		else {
			self.passwordField?.stringValue = ""
		}

		self.authenticationTypeSwitch?.selectedSegment = self.step.useUsernamePasswordAuthentication ? 0 : 1
		self.authenticationKeyField?.isEnabled = !self.step.useUsernamePasswordAuthentication
		self.usernameField?.isEnabled = self.step.useUsernamePasswordAuthentication
		self.passwordField?.isEnabled = self.step.useUsernamePasswordAuthentication

		self.infoProgress?.isHidden = false
		self.infoLabel?.stringValue = NSLocalizedString("Trying to connect...", comment: "")
		self.infoIcon?.image = nil
		self.infoIcon?.isHidden = true
		self.createTableButton?.isEnabled = false
		self.infoProgress?.startAnimation(nil)

		if let url = self.step.url {
			checkConnectionJob!.async {
				R.connect(url) { err, connection in
					if let e = err {
						asyncMain {
							self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e.localizedDescription)
							self.infoIcon?.image = NSImage(named: "SadIcon")
							self.infoProgress?.isHidden = true
							self.infoIcon?.isHidden = false
						}
						return
					}

					R.now().run(connection) { res in
						asyncMain {
							self.infoProgress?.stopAnimation(nil)
							if case .error(let e) = res {
								self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
								self.infoIcon?.image = NSImage(named: "SadIcon")
								self.createTableButton?.isEnabled = false
								self.infoProgress?.isHidden = true
								self.infoIcon?.isHidden = false
							}
							else {
								self.infoLabel?.stringValue = NSLocalizedString("Connected!", comment: "")
								self.infoIcon?.image = NSImage(named: "CheckIcon")
								self.createTableButton?.isEnabled = true
								self.infoProgress?.isHidden = true
								self.infoIcon?.isHidden = false
							}
						}
					}
				}
			}
		}
	}

	func alterTableView(_ view: QBEAlterTableViewController, didAlterTable table: MutableDataset?) {
		if let s = table as? QBERethinkMutableDataset {
			self.step.table = s.tableName
			self.step.database = s.databaseName
			self.step.server = s.url.host ?? self.step.server
			self.step.port = s.url.port ?? self.step.port
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
			self.updateView()
		}
	}

	@IBAction func createTable(_ sender: NSObject) {
		if let mutableDataset = self.step.mutableDataset {
			let vc = QBEAlterTableViewController()
			vc.warehouse = mutableDataset.warehouse
			vc.delegate = self
			vc.warehouseName = String(format: NSLocalizedString("RethinkDB database '%@'", comment: ""), self.step.database)
			self.presentViewControllerAsModalWindow(vc)
		}
	}

	@IBAction func updateFromFields(_ sender: NSObject) {
		var change = false

		if self.serverField.stringValue != self.step.server {
			self.step.server = self.serverField.stringValue
			change = true
		}

		if self.portField.integerValue != self.step.port {
			let p = self.portField.integerValue
			if p>0 && p<65536 {
				self.step.port = p
				change = true
			}
		}

		let useUserPass = self.authenticationTypeSwitch!.selectedSegment == 0
		if useUserPass != self.step.useUsernamePasswordAuthentication {
			self.step.useUsernamePasswordAuthentication = useUserPass
			change = true
		}
		else if let u = self.passwordField?.stringValue, u != step.password.stringValue {
			step.password.stringValue = u
			change = true
		}

		if self.usernameField.stringValue != self.step.username {
			self.step.username = self.usernameField.stringValue
			change = true
		}

		if self.authenticationKeyField.stringValue != self.step.authenticationKey {
			self.step.authenticationKey = self.authenticationKeyField.stringValue
			change = true
		}

		if change {
			self.updateView()
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return step.columns.count
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		step.columns[row] = Column(object as! String)
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
	}

	internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		if let tc = tableColumn {
			if tc.identifier == "column" {
				return step.columns[row].name
			}
		}
		return nil
	}

	@IBAction func addColumn(_ sender: NSObject) {
		let s = self.addColumnTextField.stringValue
		if !s.isEmpty {
			if !step.columns.contains(Column(s)) {
				step.columns.append(Column(s))
				self.updateView()
				self.delegate?.configurableView(self, didChangeConfigurationFor: step)
			}
		}
		self.addColumnTextField.stringValue = ""
	}

	@IBAction func removeColumns(_ sender: NSObject) {
		if let sr = self.tableView?.selectedRow, sr >= 0 && sr != NSNotFound && sr < self.step.columns.count {
			self.step.columns.remove(at: sr)
			self.updateView()
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
	}
}
