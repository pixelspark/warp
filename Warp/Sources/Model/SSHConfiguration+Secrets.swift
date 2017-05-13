import Foundation
import WarpConduit
import WarpCore

extension SSHConfiguration {
	private var passwordSecret: QBESecret {
		return QBESecret(serviceType: "ssh", host: self.host, port: self.port, account: self.username, friendlyName: "SSH \(self.username)@\(self.host):\(self.port)")
	}

	private var passphraseSecret: QBESecret? {
		switch self.authentication {
		case .key(file: _, passphrase: _):
			// TODO: this should really be saved per-key, not per-host. But at this point we do not 'know' the real key file name (could be security-scoped bookmark)
			return QBESecret(serviceType: "ssh-key", host: self.host, port: self.port, account: self.username, friendlyName: "SSH key for \(self.username)@\(self.host):\(self.port)")

		default:
			return nil
		}
	}

	func saveKeyFileReference(relativeToDocumentURL doc: URL?) -> QBEFileReference? {
		return self.mutex.locked { () -> QBEFileReference? in
			switch self.authentication {
			case .key(file: let u, passphrase: _):
				return QBEFileReference.absolute(u).persist(doc)
			default:
				return nil
			}
		}
	}

	func loadKeyFileReference(_ ref: QBEFileReference, relativeToDocumentURL doc: URL?) {
		if let url = ref.resolve(doc)?.url {
			self.mutex.locked {
				switch self.authentication {
				case .key(file: _, passphrase: let p):
					self.authentication = .key(file: url, passphrase: p)
				default:
					break
				}
			}
		}
	}

	func saveSecretsToKeychain() {
		self.mutex.locked {
			switch self.authentication {
			case .password(let p):
				if let d = p.data(using: .utf8) {
					switch self.passwordSecret.setData(d) {
					case .success(_):
						break

					case .failure(let e):
						trace("Could not save password for SSH configuration \(self.passwordSecret.friendlyName) to keychain: \(e)")
					}
				}

			case .key(file: _, passphrase: let p):
				if let ps = self.passphraseSecret {
					if let ds = p.data(using: .utf8) {
						switch ps.setData(ds) {
						case .success(_):
							break

						case .failure(let e):
							trace("Could not save passphase for SSH configuration \(self.passwordSecret.friendlyName) to keychain: \(e)")
						}
					}
				}

			case .none:
				break
			}
		}
	}

	func loadSecretsFromKeychain() {
		self.mutex.locked {
			switch self.authentication {
			case .password(_):
				if let d = self.passwordSecret.data, let s = String(data: d, encoding: .utf8) {
					self.authentication = .password(s)
				}

			case .key(file: let f, passphrase: _):
				if let ps = self.passphraseSecret, let d = ps.data, let s = String(data: d, encoding: .utf8) {
					self.authentication = .key(file: f, passphrase: s)
				}

			case .none:
				break
			}
		}
	}
}
