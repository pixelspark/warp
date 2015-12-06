import Foundation

/** QBESecret represents a secret (usually a password) stored in the OS X Keychain. After initialization use the `stringValue`
property to set or get the password/secret. Note that this may block: the Keychain will sometimes ask the user whether
the app is allowed to access the Keychain item. If you need to store binary secret data, use the `data` property. */
public class QBESecret {
	let serviceName: String
	let accountName: String
	let friendlyName: String

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

	private var query: [String: AnyObject] {
		return [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: serviceName,
			kSecAttrAccount as String: accountName,
			kSecAttrGeneric as String: accountName
		]
	}

	public var data: NSData? {
		get {
			var q = self.query
			q[kSecReturnData as String] = kCFBooleanTrue
			q[kSecMatchLimit as String] = kSecMatchLimitOne

			var result: AnyObject?
			let status = withUnsafeMutablePointer(&result) {
				SecItemCopyMatching(q, UnsafeMutablePointer($0))
			}
			return status == noErr ? (result as? NSData) : nil
		}
		set(newValue) {
			setData(newValue)
		}
	}

	private func setData(data: NSData?, update: Bool = false) -> Bool {
		var q = self.query

		if let d = data {
			let status: OSStatus
			if update {
				let change = [
					kSecValueData as String: d,
					kSecAttrLabel as String: friendlyName
				]
				status = SecItemUpdate(q, change)
			}
			else {
				q[kSecValueData as String] = d
				q[kSecAttrLabel as String] = friendlyName
				q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
				status = SecItemAdd(q, nil)
			}

			if status == noErr {
				return true
			}
			else if status == errSecDuplicateItem && !update {
				// TODO Update existing item
				return self.setData(data, update: true)
			}
			else {
				return false
			}
		}
		else {
			return SecItemDelete(query) == noErr
		}
	}

	/** Deletes the secret key from the Keychain. Getting `stringValue` or `data` after calling `delete` will return nil.
	Setting `stringValue` or `data` after calling delete will set a new secret. */
	public func delete() -> Bool {
		return setData(nil)
	}

	var stringValue: String? {
		get {
			if let data = self.data {
				return String(data: data, encoding: NSUTF8StringEncoding)
			}
			return nil
		}
		set(newValue) {
			let data = newValue?.dataUsingEncoding(NSUTF8StringEncoding)
			setData(data)
		}
	}
}