import Foundation
import Cocoa
import WarpCore

internal class QBEMySQLSourceStepView: QBEStepViewControllerFor<QBEMySQLSourceStep>, QBEAlterTableViewDelegate {
	@IBOutlet var userField: NSTextField?
	@IBOutlet var passwordField: NSTextField?
	@IBOutlet var hostField: NSTextField?
	@IBOutlet var portField: NSTextField?
	@IBOutlet var infoLabel: NSTextField?
	@IBOutlet var infoProgress: NSProgressIndicator?
	@IBOutlet var infoIcon: NSImageView?
	@IBOutlet var createTableButton: NSButton?

	required init?(step: QBEStep, delegate: QBEStepViewDelegate) {
		super.init(step: step, delegate: delegate, nibName: "QBEMySQLSourceStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}

	func alterTableView(view: QBEAlterTableViewController, didCreateTable: QBEMutableData?) {
		if let s = didCreateTable as? QBESQLMutableData {
			self.step.tableName = s.tableName
			self.delegate?.stepView(self, didChangeConfigurationForStep: step)
			self.updateView()
		}
	}

	@IBAction func createTable(sender: NSObject) {
		if let mutableData = self.step.mutableData {
			let vc = QBEAlterTableViewController()
			vc.warehouse = mutableData.warehouse
			vc.delegate = self
			vc.warehouseName = String(format: NSLocalizedString("MySQL database '%@'", comment: ""), self.step.databaseName)
			self.presentViewControllerAsModalWindow(vc)
		}
	}
	
	@IBAction func updateStep(sender: NSObject) {
		var changed = false
		
		if let u = self.userField?.stringValue where u != step.user {
			step.user = u
			changed = true
		}
		else if let u = self.passwordField?.stringValue where u != step.password.stringValue {
			step.password.stringValue = u
			changed = true
		}
		
		if let u = self.hostField?.stringValue where u != step.host {
			step.host = u
			changed = true
		}
		
		if let u = self.portField?.stringValue where Int(u) != step.port {
			step.port = Int(u) ?? step.port
			changed = true
		}
	
		if changed {
			delegate?.stepView(self, didChangeConfigurationForStep: step)
			updateView()
		}
	}

	private var checkConnectionJob: QBEJob? = nil { willSet {
		if let o = checkConnectionJob {
			o.cancel()
		}
	} }

	private func updateView() {
		QBEAssertMainThread()
		checkConnectionJob = QBEJob(.UserInitiated)

		self.userField?.stringValue = step.user ?? ""
		self.passwordField?.stringValue = step.password.stringValue ?? ""
		self.hostField?.stringValue = step.host ?? ""
		self.portField?.stringValue = "\(step.port ?? 3306)"

		self.infoProgress?.hidden = false
		self.infoLabel?.stringValue = NSLocalizedString("Trying to connect...", comment: "")
		self.infoIcon?.image = nil
		self.infoIcon?.hidden = true
		self.infoProgress?.startAnimation(nil)

		self.createTableButton?.enabled = false

		checkConnectionJob!.async {
			if let database = self.step.database {
				switch database.connect() {
				case .Success(let con):
					con.serverInformation({ (fallibleInfo) -> () in
						QBEAsyncMain {
							self.infoProgress?.stopAnimation(nil)
							switch fallibleInfo {
							case .Success(let v):
								self.infoLabel?.stringValue = String(format: NSLocalizedString("Connected (%@)", comment: ""),v)
								self.infoIcon?.image = NSImage(named: "CheckIcon")
								self.infoProgress?.hidden = true
								self.infoIcon?.hidden = false
								self.createTableButton?.enabled = true

							case .Failure(let e):
								self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
								self.infoIcon?.image = NSImage(named: "SadIcon")
								self.infoProgress?.hidden = true
								self.infoIcon?.hidden = false
							}
						}
					})

				case .Failure(let e):
					QBEAsyncMain {
						self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
						self.infoIcon?.image = NSImage(named: "SadIcon")
						self.infoProgress?.hidden = true
						self.infoIcon?.hidden = false
					}
				}
			}
		}
	}
}