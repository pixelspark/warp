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

/** QBESecret represents a secret (usually a password) stored in the OS X Keychain. After initialization use the `stringValue`
property to set or get the password/secret. Note that this may block: the Keychain will sometimes ask the user whether
the app is allowed to access the Keychain item. If you need to store binary secret data, use the `data` property. */
public class QBESecret: Equatable, CustomStringConvertible {
	let serviceName: String
	let accountName: String
	let friendlyName: String

	public static func secretsForService(_ serviceType: String) -> [QBESecret] {
		let q: [String : Any] = [
			kSecClass as String: kSecClassGenericPassword,
			//kSecAttrService as String: serviceType,
            kSecReturnAttributes as String: kCFBooleanTrue!,
			kSecReturnRef as String: kCFBooleanTrue!,
			kSecMatchLimit as String: kSecMatchLimitAll
		]

		var result: AnyObject?
		let status = withUnsafeMutablePointer(to: &result) {
			SecItemCopyMatching(q as CFDictionary, UnsafeMutablePointer($0))
		}

		if status == errSecSuccess {
			if let items = result as? [[String: AnyObject]] {
				var services: [QBESecret] = []
				for item in items {
					if	let sn = item[kSecAttrService as String] as? String,
						let serviceURL = URL(string: sn) ,
						let accountName = item[kSecAttrAccount as String] as? String,
						serviceURL.scheme == serviceType {
						services.append(QBESecret(serviceType: serviceType, host: serviceURL.host!, port: (serviceURL as NSURL).port!.intValue, account: accountName, friendlyName: sn))
					}
				}
				return services
			}
			else {
				return []
			}
		}
		return []
	}

	/** The service type is a short identifier of the kind of service this secret is associated with, e.g. 'mysql'. The
	host is the name of the remote computer where the service is located (either a domain name or IP address), or simply
	'localhost' if the secret is on the local computer (note that QBESecret will not attempt to resolve domain names). The
	port is the TCP/UDP port number of the service, or 0 if this is not relevant for this service. The friendly name is
	a localized string meant to clarify the contents of the key to the user (it is also shown in the Keychain Access app
	and any dialogs presented to the user during key lookup. */
	init(serviceType: String, host: String, port: Int, account: String, friendlyName: String) {
		self.serviceName = "\(serviceType)://\(host):\(port)"
		self.accountName = account
		self.friendlyName = friendlyName
	}

	/** If you want to construct a QBESecret for something else than a service, use this initializer. The `serviceName` 
	uniquely identifies the key. When using the other initializer, the serviceName will be a URL, but this is not 
	required. */
	init(serviceName: String, accountName: String, friendlyName: String) {
		self.serviceName = serviceName
		self.friendlyName = friendlyName
		self.accountName = accountName
	}

	private var query: [String: Any] {
		return [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: serviceName,
			kSecAttrAccount as String: accountName,
			kSecAttrGeneric as String: accountName
		]
	}

	public var url: URL? {
		if var url = URLComponents(string: self.serviceName) {
			url.user = self.accountName
			return url.url
		}
		return nil
	}

	public var data: Data? {
		get {
			var q = self.query
			q[kSecReturnData as String] = kCFBooleanTrue
			q[kSecMatchLimit as String] = kSecMatchLimitOne

			var result: AnyObject?
			let status = withUnsafeMutablePointer(to: &result) {
				SecItemCopyMatching(q as CFDictionary, UnsafeMutablePointer($0))
			}
			return status == noErr ? (result as? Data) : nil
		}
		set(newValue) {
			_ = setData(newValue)
		}
	}

	public func setData(_ data: Data?, update: Bool = false) -> Fallible<Void> {
		var q = self.query

		if let d = data {
			let status: OSStatus
			if update {
				let change: [String: Any] = [
					kSecValueData as String: d,
					kSecAttrLabel as String: friendlyName
				]
				status = SecItemUpdate(q as CFDictionary, change as CFDictionary)
			}
			else {
				q[kSecValueData as String] = d
				q[kSecAttrLabel as String] = friendlyName
				q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
				status = SecItemAdd(q as CFDictionary, nil)
			}

			if status == noErr {
				return .success(())
			}
			else if status == errSecDuplicateItem && !update {
				// TODO Update existing item
				return self.setData(data, update: true)
			}
			else {
				return .failure("unknown error: \(status)")
			}
		}
		else {
			let s = SecItemDelete(query as CFDictionary)
			if s == noErr {
				return .success(())
			}
			else {
				return .failure("SecItemDelete failed: \(s)")
			}
		}
	}

	/** Deletes the secret key from the Keychain. Getting `stringValue` or `data` after calling `delete` will return nil.
	Setting `stringValue` or `data` after calling delete will set a new secret. */
	public func delete() -> Fallible<Void> {
		return setData(nil)
	}

	var stringValue: String? {
		get {
			if let data = self.data {
				return String(data: data, encoding: String.Encoding.utf8)
			}
			return nil
		}
		set(newValue) {
			let data = newValue?.data(using: String.Encoding.utf8)
			_ = setData(data)
		}
	}

	public var description: String {
		return "\(self.accountName) @ \(self.serviceName)"
	}

	public static func ==(lhs: QBESecret, rhs: QBESecret) -> Bool {
		return lhs.accountName == rhs.accountName && lhs.serviceName == rhs.serviceName
	}
}

#if os(macOS)

internal class QBESecretsDataSource: NSObject, NSComboBoxDataSource {
	let serviceType: String
	var secrets: [QBESecret] = []

	init(serviceType: String) {
		self.serviceType = serviceType
	}

	@objc func comboBox(_ aComboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
		return self.secrets[index].url ?? ""
	}

	@objc func numberOfItems(in aComboBox: NSComboBox) -> Int {
		self.secrets = QBESecret.secretsForService(self.serviceType)
		return self.secrets.count
	}
}

#endif
