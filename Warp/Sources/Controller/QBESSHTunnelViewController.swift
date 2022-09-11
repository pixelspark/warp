import Foundation
import Cocoa
import WarpCore
import WarpConduit

class QBESSHTunnelViewController: NSViewController {
	@IBOutlet var hostField: NSTextField!
	@IBOutlet var userField: NSTextField!
	@IBOutlet var passwordField: NSTextField!
	@IBOutlet var keyLabel: NSTextField!
	@IBOutlet var chooseKeyButton: NSButton!
	@IBOutlet var passwordRadio: NSButton!
	@IBOutlet var keyRadio: NSButton!
	@IBOutlet var testButton: NSButton!
	@IBOutlet var enabledCheck: NSButton!
	@IBOutlet var portField: NSTextField!
	@IBOutlet var okButton: NSButton!
	@IBOutlet var fingerprintField: NSTextField!
	@IBOutlet var passphraseField: NSTextField!

	private var testing = false

	public var configuration: SSHConfiguration = SSHConfiguration()

	override func viewDidAppear() {
		super.viewDidAppear()
		self.updateView()
		self.view.window!.title = "SSH tunnel".localized
	}

	@IBAction func ok(_ sender: AnyObject) {
		self.configuration.saveSecretsToKeychain()
		self.dismiss(sender)
	}

	@IBAction func test(_ sender: AnyObject) {
		if self.testing {
			return
		}

		// Catch the latest edits
		self.fieldsChanged(sender)
		self.testing = true
		self.updateView()

		let job = Job(.userInitiated)
		job.async {
			self.configuration.mutex.locked {
				if self.configuration.enabled {
					self.configuration.test { error in
						asyncMain {
							if let e = error {
								NSAlert.showSimpleAlert("Testing SSH tunnel connection".localized, infoText: e, style: .critical, window: self.view.window)
							}
							else {
								NSAlert.showSimpleAlert("Testing SSH tunnel connection".localized, infoText: "The tunnel could succesfully be established.".localized, style: .warning, window: self.view.window)
							}

							self.testing = false
							self.updateView()
						}
					}
				}
			}
		}
	}

	@IBAction func chooseKeyFile(_ sender: AnyObject) {
		let openPanel = NSOpenPanel()
		openPanel.canChooseFiles = true
		//////no.allowedFileTypes = token.allowedFileTypes
		openPanel.beginSheetModal(for: self.view.window!, completionHandler: { (result: NSApplication.ModalResponse) -> Void in
			if result == NSApplication.ModalResponse.OK {
				if let url = openPanel.url {
					self.configuration.mutex.locked {
						switch self.configuration.authentication {
						case .password(_):
							self.configuration.authentication = .key(file: url, passphrase: "")
						case .key(file: _, passphrase: let p):
							self.configuration.authentication = .key(file: url, passphrase: p)
						case .none:
							self.configuration.authentication = .key(file: url, passphrase: "")
						}
					}
				}
			}
			self.updateView()
		})
	}

	@IBAction func fieldsChanged(_ sender: AnyObject) {
		self.configuration.mutex.locked {
			self.configuration.host = self.hostField.stringValue
			self.configuration.port = max(1, min(self.portField.integerValue, 65535))
			self.configuration.username = self.userField.stringValue

			switch self.configuration.authentication {
			case .none:
				break
			case .password(_):
				self.configuration.authentication = .password(self.passwordField.stringValue)

			case .key(file: let f, passphrase: _):
				self.configuration.authentication = .key(file: f, passphrase: self.passphraseField.stringValue)
			}

			// Parse host key
			let chars = Array(self.fingerprintField.stringValue)
			if chars.isEmpty {
				self.configuration.hostFingerprint = nil
			}
			else {
				var error = false
				let numbers = stride(from: 0, to: chars.count, by: 3).map() { (idx: Int) -> UInt8 in
					let res = strtoul(String(chars[idx ..< Swift.min(idx + 2, chars.count)]), nil, 16)
					if res > UInt(UInt8.max) {
						error = true
						return UInt8(0)
					}
					return UInt8(res)
				}

				if !error {
					self.configuration.hostFingerprint = Data(numbers)
				}
				else {
					NSAlert.showSimpleAlert("The host fingerprint is invalid".localized, infoText: "", style: .warning, window: self.view.window)
				}
			}
		}
		self.updateView()
	}

	@IBAction func togglePassword(_ sender: AnyObject) {
		self.configuration.mutex.locked {
			self.configuration.authentication = .password(self.passwordField.stringValue)
		}
		self.updateView()
	}

	@IBAction func toggleKeyFile(_ sender: AnyObject) {
		self.configuration.mutex.locked {
			self.configuration.authentication = .none
		}
		self.updateView()
	}

	@IBAction func toggleEnabled(_ sender: AnyObject) {
		self.configuration.mutex.locked {
			self.configuration.enabled = (self.enabledCheck.state) == NSControl.StateValue.on
		}
		self.updateView()
	}

	func viewWillAppear(animated: Bool) {
		self.updateView()
	}

	func updateView() {
		assertMainThread()

		self.configuration.mutex.locked {
			self.enabledCheck.state = self.configuration.enabled ? NSControl.StateValue.on : NSControl.StateValue.off
			self.hostField.isEnabled = self.configuration.enabled
			self.userField.isEnabled = self.configuration.enabled
			self.passwordRadio.isEnabled = self.configuration.enabled
			self.keyRadio.isEnabled = self.configuration.enabled
			self.portField.isEnabled = self.configuration.enabled
			self.testButton.isEnabled = self.configuration.enabled && !self.testing
			self.keyLabel.isEnabled = false

			switch self.configuration.authentication {
			case .none:
				self.keyRadio.state = NSControl.StateValue.on
				self.passwordRadio.state = NSControl.StateValue.off
				self.passwordField.stringValue = ""
				self.passphraseField.stringValue = ""
				self.passwordField.isEnabled = false
				self.passphraseField.isEnabled = self.configuration.enabled
				self.chooseKeyButton.isEnabled = self.configuration.enabled
				self.keyLabel.stringValue = ""

			case .key(file: let f, passphrase: let p):
				self.keyRadio.state = NSControl.StateValue.on
				self.passwordRadio.state = NSControl.StateValue.off
				self.passwordField.stringValue = ""
				self.passphraseField.stringValue = p
				self.passwordField.isEnabled = false
				self.passphraseField.isEnabled = self.configuration.enabled
				self.chooseKeyButton.isEnabled = self.configuration.enabled
				self.keyLabel.stringValue = f?.lastPathComponent ?? ""

			case .password(let p):
				self.keyRadio.state = NSControl.StateValue.off
				self.passwordRadio.state = NSControl.StateValue.on
				self.passwordField.stringValue = p
				self.passphraseField.stringValue = ""
				self.passwordField.isEnabled = self.configuration.enabled
				self.passphraseField.isEnabled = self.configuration.enabled
				self.chooseKeyButton.isEnabled = false
				self.keyLabel.stringValue = ""
			}

			// Fill fields
			self.hostField.stringValue = self.configuration.host
			self.userField.stringValue = self.configuration.username
			self.portField.integerValue = self.configuration.port

			if let hf = self.configuration.hostFingerprint {
				self.fingerprintField.stringValue = hf.map { String(format: "%02hhx", $0) }.joined(separator: ":")
			}
			else {
				self.fingerprintField.stringValue = ""
			}
		}
	}
}
