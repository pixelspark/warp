/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit
import Eureka
import WarpCore
import WarpConduit

protocol QBEFormConfigurable {
	var form: Form { get }
}

protocol QBEFormConfigurableStep: QBEFormConfigurable {
	var shouldConfigure: Bool { get }
}

extension QBEMySQLSourceStep: QBEFormConfigurableStep {
	var shouldConfigure: Bool { return true }

	var form: Form {
		let form = Form()

		let passwordRow = PasswordRow("password") { row in
			row.title = "Password".localized
			row.value = self.password.stringValue
			}.onChange { self.password.stringValue = $0.value ?? "" };

		form +++ Section("Server".localized)
			<<< TextRow("host") { row in
				row.title = "Host name".localized
				row.value = self.host
				row.placeholder = "localhost".localized
				row.onChange { self.host = $0.value ?? "localhost" }
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
					cell.textField.autocorrectionType = .no
				})
			}
			<<< IntRow("port") { row in
				row.title = "Port".localized
				row.value = self.port
				row.placeholder = "3306".localized
				row.onChange { self.port = $0.value ?? 3306 }
			}
			<<< TextRow("user") { row in
				row.title = "User name".localized
				row.value = self.user
				row.placeholder = "root"
				row.onChange {
					self.user = $0.value ?? "root"
					passwordRow.value = self.password.stringValue
				}
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
					cell.textField.autocorrectionType = .no
				})
			}
			<<< passwordRow

		form +++ Section("")
			<<< PushRow<QBESecret>() { pr in
				pr.options = QBESecret.secretsForService("mysql")
				pr.noValueDisplayText = "Recent servers".localized

				pr.onChange { pr in
					if let secret = pr.value {
						self.user = secret.accountName
						self.host = secret.url?.host ?? self.host
						self.port = secret.url?.port ?? self.port

						pr.value = nil
						form.setValues([
							"host": secret.url?.host ?? self.host,
							"port": secret.url?.port ?? self.port,
							"user": secret.accountName,
							"password": self.password.stringValue
						])
						form.allRows.forEach { $0.updateCell() }
					}
				}
			}

		return form
	}
}


extension QBEPostgresSourceStep: QBEFormConfigurableStep {
	var shouldConfigure: Bool { return true }

	var form: Form {
		let form = Form()

		let passwordRow = PasswordRow("password") { row in
			row.title = "Password".localized
			row.value = self.password.stringValue
		}.onChange { self.password.stringValue = $0.value ?? "" };

		form +++ Section("Server".localized)
			<<< TextRow("host") { row in
				row.title = "Host name".localized
				row.value = self.host
				row.placeholder = "localhost".localized
				row.onChange { self.host = $0.value ?? "localhost" }
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
				})
			}
			<<< IntRow("port") { row in
				row.title = "Port".localized
				row.value = self.port
				row.placeholder = "5432".localized
				row.onChange { self.port = $0.value ?? 5432 }
			}
			<<< TextRow("user") { row in
				row.title = "User name".localized
				row.value = self.user
				row.placeholder = "postgres".localized
				row.onChange {
					self.user = $0.value ?? "postgres"
					passwordRow.value = self.password.stringValue
				}
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
				})
			}
			<<< passwordRow

		form +++ Section("")
			<<< PushRow<QBESecret>() { pr in
				pr.options = QBESecret.secretsForService("postgres")
				pr.noValueDisplayText = "Recent servers".localized

				pr.onChange { pr in
					if let secret = pr.value {
						self.user = secret.accountName
						self.host = secret.url?.host ?? self.host
						self.port = secret.url?.port ?? self.port

						pr.value = nil
						form.setValues([
							"host": secret.url?.host ?? self.host,
							"port": secret.url?.port ?? self.port,
							"user": secret.accountName,
							"password": self.password.stringValue
							])
						form.allRows.forEach { $0.updateCell() }
					}
				}
		}

		return form
	}
}

extension QBECSVSourceStep: QBEFormConfigurableStep {
	var shouldConfigure: Bool { return false }

	var form: Form {
		let form = Form()

		form +++ Section("Format".localized)
			<<< TextRow(){ row in
				row.title = "Field separator".localized
				row.value = String(Character(UnicodeScalar(self.fieldSeparator)!))
				row.onChange {
					if let v = $0.value, !v.isEmpty {
						self.fieldSeparator = v.utf16[v.utf16.startIndex]
						row.value = String(Character(UnicodeScalar(self.fieldSeparator)!))
					}
				}
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
				})
			}
			<<< SwitchRow() { row in
				row.title = "Has headers".localized
				row.value = self.hasHeaders
				row.onChange { self.hasHeaders = Bool($0.value ?? self.hasHeaders) }
			}

		return form
	}
}


protocol QBEConfigurableFormViewControllerDelegate: class {
	func configurableFormViewController(_ : QBEConfigurableFormViewController, hasChangedConfigurable: QBEFormConfigurable)
}

class QBEConfigurableFormViewController: FormViewController {
	var configurable: QBEFormConfigurable! = nil
	weak var delegate: QBEConfigurableFormViewControllerDelegate? = nil

	override func viewDidLoad() {
		super.viewDidLoad()
		self.modalPresentationStyle = .formSheet

		self.navigationItem.title = "Settings".localized
		self.navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.done(_:))), animated: false)

		if UIDevice.current.userInterfaceIdiom == .pad {
			self.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Apply".localized, style: .plain, target: self, action: #selector(self.apply(_:))), animated: false)
		}

		form = configurable.form
		form.delegate = self
	}

	@IBAction func apply(_ sender: AnyObject?) {
		self.delegate?.configurableFormViewController(self, hasChangedConfigurable: configurable)
	}

	@IBAction func done(_ sender: AnyObject?) {
		self.delegate?.configurableFormViewController(self, hasChangedConfigurable: configurable)
		self.dismiss(animated: true)
	}

	/*override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
		super.valueHasBeenChanged(for: row, oldValue: oldValue, newValue: newValue)
	}*/
}
