/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Cocoa
import WarpCore
import WarpConduit

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
		
		if let u = self.userField?.stringValue, u != step.user {
			step.user = u
			changed = true
		}
		else if let u = self.passwordField?.stringValue, u != step.password.stringValue {
			step.password.stringValue = u
			changed = true
		}
		
		if let u = self.hostField?.stringValue, u != step.host {
			if let url = URL(string: u), url.scheme != nil {
				step.user = url.user ?? step.user
				step.host = url.host ?? step.host
				step.port = (url as NSURL).port?.intValue ?? step.port
			}
			else {
				step.host = u
			}
			changed = true
		}
		
		if let u = self.portField?.stringValue, Int(u) != step.port {
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

		self.userField?.stringValue = step.user 
		self.passwordField?.stringValue = step.password.stringValue ?? ""
		self.hostField?.stringValue = step.host 
		self.portField?.stringValue = "\(step.port)"

		self.infoProgress?.isHidden = false
		self.infoLabel?.stringValue = NSLocalizedString("Trying to connect...", comment: "")
		self.infoIcon?.image = nil
		self.infoIcon?.isHidden = true
		self.infoProgress?.startAnimation(nil)

		self.createTableButton?.isEnabled = false

		checkConnectionJob!.async {
			let database = QBEMySQLDatabase(host: self.step.hostToConnectTo, port: self.step.port, user: self.step.user, password: self.step.password.stringValue ?? "", database: self.step.databaseName)
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
