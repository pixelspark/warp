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

extension QBEPostgresSourceStep: QBEFormConfigurableStep {
	var shouldConfigure: Bool { return true }

	var form: Form {
		let form = Form()

		let passwordRow = PasswordRow() { row in
			row.title = "Password".localized
			row.value = self.password.stringValue
		}.onChange { self.password.stringValue = $0.value ?? "" };

		form +++ Section("Server".localized)
			<<< TextRow(){ row in
				row.title = "Host name".localized
				row.value = self.host
				row.placeholder = "localhost".localized
				row.onChange { self.host = $0.value ?? "localhost" }
				row.cellSetup({ (cell, row) in
					cell.textField.autocapitalizationType = .none
				})
			}
			<<< IntRow(){ row in
				row.title = "Port".localized
				row.value = self.port
				row.placeholder = "5432".localized
				row.onChange { self.port = $0.value ?? 5432 }
			}
			<<< TextRow() { row in
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
		self.modalPresentationStyle = .pageSheet

		self.navigationItem.title = "Settings".localized
		self.navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.done(_:))), animated: false)
		

		form = configurable.form
		form.delegate = self
	}

	@IBAction func done(_ sender: AnyObject?) {
		self.delegate?.configurableFormViewController(self, hasChangedConfigurable: configurable)
		self.dismiss(animated: true)
	}

	/*override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
		super.valueHasBeenChanged(for: row, oldValue: oldValue, newValue: newValue)
	}*/
}
