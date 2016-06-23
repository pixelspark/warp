import Foundation
import Cocoa
import WarpCore

internal class QBEMySQLSourceStepView: QBEConfigurableStepViewControllerFor<QBEMySQLSourceStep>, QBEAlterTableViewDelegate {
	@IBOutlet var userField: NSTextField?
	@IBOutlet var passwordField: NSTextField?
	@IBOutlet var hostField: NSComboBox?
	@IBOutlet var portField: NSTextField?
	@IBOutlet var infoLabel: NSTextField?
	@IBOutlet var infoProgress: NSProgressIndicator?
	@IBOutlet var infoIcon: NSImageView?
	@IBOutlet var createTableButton: NSButton?
	private let serviceDatasetSource = QBESecretsDataSource(serviceType: "mysql")

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEMySQLSourceStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	internal override func viewWillAppear() {
		self.hostField?.dataSource = self.serviceDatasetSource
		super.viewWillAppear()
		updateView()
	}

	func alterTableView(_ view: QBEAlterTableViewController, didAlterTable table: MutableDataset?) {
		if let s = table as? SQLMutableDataset {
			self.step.tableName = s.tableName
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
			self.updateView()
		}
	}

	@IBAction func createTable(_ sender: NSObject) {
		if let warehouse = self.step.warehouse {
			let vc = QBEAlterTableViewController()
			vc.warehouse = warehouse
			vc.delegate = self
			vc.warehouseName = String(format: NSLocalizedString("MySQL database '%@'", comment: ""), self.step.databaseName ?? "(unknown)".localized)
			self.presentViewControllerAsModalWindow(vc)
		}
	}
	
	@IBAction func updateStep(_ sender: NSObject) {
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
			if let url = URL(string: u) {
				step.user = url.user ?? step.user
				step.host = url.host ?? step.host
				step.port = (url as NSURL).port?.intValue ?? step.port
			}
			else {
				step.host = u
			}
			changed = true
		}
		
		if let u = self.portField?.stringValue where Int(u) != step.port {
			step.port = Int(u) ?? step.port
			changed = true
		}
	
		if changed {
			delegate?.configurableView(self, didChangeConfigurationFor: step)
			updateView()
		}
	}

	private var checkConnectionJob: Job? = nil { willSet {
		if let o = checkConnectionJob {
			o.cancel()
		}
	} }

	private func updateView() {
		assertMainThread()
		checkConnectionJob = Job(.userInitiated)

		self.userField?.stringValue = step.user ?? ""
		self.passwordField?.stringValue = step.password.stringValue ?? ""
		self.hostField?.stringValue = step.host ?? ""
		self.portField?.stringValue = "\(step.port ?? 3306)"

		self.infoProgress?.isHidden = false
		self.infoLabel?.stringValue = NSLocalizedString("Trying to connect...", comment: "")
		self.infoIcon?.image = nil
		self.infoIcon?.isHidden = true
		self.infoProgress?.startAnimation(nil)

		self.createTableButton?.isEnabled = false

		checkConnectionJob!.async {
			let database = QBEMySQLDatasetbase(host: self.step.hostToConnectTo, port: self.step.port, user: self.step.user, password: self.step.password.stringValue ?? "", database: self.step.databaseName)
			switch database.connect() {
			case .success(let con):
				con.serverInformation({ (fallibleInfo) -> () in
					asyncMain {
						self.infoProgress?.stopAnimation(nil)
						switch fallibleInfo {
						case .success(let v):
							self.infoLabel?.stringValue = String(format: NSLocalizedString("Connected (%@)", comment: ""),v)
							self.infoIcon?.image = NSImage(named: "CheckIcon")
							self.infoProgress?.isHidden = true
							self.infoIcon?.isHidden = false
							self.createTableButton?.isEnabled = self.step.warehouse != nil

						case .failure(let e):
							self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
							self.infoIcon?.image = NSImage(named: "SadIcon")
							self.infoProgress?.isHidden = true
							self.infoIcon?.isHidden = false
						}
					}
				})

			case .failure(let e):
				asyncMain {
					self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
					self.infoIcon?.image = NSImage(named: "SadIcon")
					self.infoProgress?.isHidden = true
					self.infoIcon?.isHidden = false
				}
			}
		}
	}
}
