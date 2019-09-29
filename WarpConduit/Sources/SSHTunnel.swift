import Foundation
import WarpCore

private class SSHClient {
	fileprivate let mutex = Mutex()

	init() {
		trace("initing sshclient")
		if libssh2_init(0) != 0 {
			fatalError("failed to initialize libssh2")
		}
		trace("libssh2_init")
	}
}

private  extension sockaddr_storage {
	func asAddr() -> sockaddr {
		var temp = self
		let addr = withUnsafePointer(to: &temp) {
			return UnsafeRawPointer($0)
		}
		return addr.assumingMemoryBound(to: sockaddr.self).pointee
	}
}

public enum SSHAuthentication: Equatable {
	case none
	case key(file: URL?, passphrase: String)
	case password(String)
}

public struct SSHListeningAddress {
	public var host: String
	public var port: Int
}

fileprivate class SSHTunneledConnection: NSObject {
	private weak var parent: SSHForwardingSocket?
	private let channel: OpaquePointer
	private let socket: Int32
	private let downstreamSource: DispatchSourceRead
	private let upstreamSource: DispatchSourceRead
	private static let readBufferSize = 4096
	private var closed = false
	private var readBuffer: UnsafeMutablePointer<CChar> = UnsafeMutablePointer<CChar>.allocate(capacity: SSHTunneledConnection.readBufferSize)

	init?(parent: SSHForwardingSocket, socket: Int32, destination: String, port destinationPort: Int) {
		self.parent = parent
		self.socket = socket

		// Create read source on socket (for upstream, we just listen in on the upstream tunnel connection; event handler will be fired spuriously)
		self.downstreamSource = DispatchSource.makeReadSource(fileDescriptor: socket, queue: DispatchQueue.global(qos: .default))
		self.upstreamSource = DispatchSource.makeReadSource(fileDescriptor: parent.session.socket!, queue: DispatchQueue.global(qos: .default))

		// Need to set blocking mode first, because otherwise channel creation will fail for some reason...
		let session = parent.session.session
		libssh2_session_set_blocking(session, 1)

		// Create a forward channel
		if let ch = destination.withCString({ (destString: UnsafePointer<Int8>) -> (OpaquePointer?) in
			return libssh2_channel_direct_tcpip_ex(session, destString, Int32(destinationPort), "127.0.0.1".cString(using: .ascii), 22)
		}) {
			// Restore non-blocking mode
			libssh2_session_set_blocking(session, 0)
			self.channel = ch
		}
		else {
			// Restore non-blocking mode, report error
			libssh2_session_set_blocking(session, 0)
			var message: UnsafeMutablePointer<Int8>? = nil
			libssh2_session_last_error(session, &message, nil, 0)
			WarpCore.trace("Cannot create channel forward, closing accepted connection (\(String(cString: message!)))")
			if Darwin.close(socket) != 0 {
				WarpCore.trace("Could not close socket; errno=\(errno)")
			}
			return nil
		}

		libssh2_channel_set_blocking(self.channel, 0) // make the channel non-blocking

		// Set SO_NOSIGPIPE (as per https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/UsingSocketsandSocketStreams.html)
		var sockopt: Int = 1
		setsockopt(self.socket, SOL_SOCKET, SO_NOSIGPIPE, &sockopt, UInt32(MemoryLayout<Int>.size))

		super.init()

		self.downstreamSource.setEventHandler(handler: DispatchWorkItem(block: { [weak self] in
			self?.pumpUp()
		}))

		self.upstreamSource.setEventHandler(handler: DispatchWorkItem(block: { [weak self]  in
			self?.pumpDown()
		}))

		self.downstreamSource.resume()
		self.upstreamSource.resume()
	}

	private func trace(_ message: String) {
		WarpCore.trace("[\(self.parent?.session.session.hashValue ?? 0), \(self.channel.hashValue)] \(message)")
	}

	/** Read data from downstream, send to upstream. */
	private func pumpUp() {
		self.parent?.session.mutex.locked { () -> () in
			let len = recv(socket, self.readBuffer, SSHTunneledConnection.readBufferSize, 0)
			if len == 0 {
				// Client disconnected
				trace("Client disconnected")
				self.close()
			}
			else if len < 0 {
				trace("Read error on downstream socket: \(len)")
			}
			else {
				var written = 0;
				while written < len {
					let w = libssh2_channel_write_ex(self.channel, 0, self.readBuffer.advanced(by: written), len - written)
					if w == Int(LIBSSH2_ERROR_EAGAIN) {
						continue;
					}
					else if w < 0 {
						trace("Upstream write error: \(w)")
					}
					written += w
				}
			}

			libssh2_channel_flush_ex(self.channel, LIBSSH2_CHANNEL_FLUSH_ALL)
			self.pumpDown()
		}
	}

	/** Read data from upstream, send to downstream. */
	private func pumpDown() {
		self.parent?.session.mutex.locked {
			while true {
				let res = libssh2_channel_read_ex(self.channel, 0, self.readBuffer, SSHTunneledConnection.readBufferSize)
				if res == Int(LIBSSH2_ERROR_EAGAIN) {
					return
				}
				else if res < 0 {
					if res == Int(LIBSSH2_ERROR_CHANNEL_CLOSED) {
						trace("channel closed")
					}
					else {
						trace("Read error on upstream socket")
					}
				}
				else if res == 0 {
					return
				}
				else {
					var written = 0;
					while written < res {
						let w = send(self.socket, self.readBuffer.advanced(by: written), res - written, 0)
						if w == -1 {
							trace("Downstream write error: \(w)")
							self.close()
							return
						}
						written += w
					}
				}
			}
		}
	}

	private func close() {
		self.parent?.session.mutex.locked {
			if !self.closed {
				let id = "[\(self.parent?.session.session.hashValue ?? 0), \(self.channel.hashValue)]"
				self.closed = true
				self.downstreamSource.cancel()
				self.upstreamSource.cancel()
				if Darwin.close(socket) != 0 {
					trace("\(id) Could not close socket; errno=\(errno)")
				}
				self.readBuffer.deallocate()

				let channel = self.channel

				libssh2_channel_close(channel)
				libssh2_channel_free(channel)
				trace("\(id) Channel destroyed")
				self.parent?.channelClosed(self)
			}
		}
	}

	deinit {
		trace("Channel deinit")
		self.close()
	}
}

fileprivate class SSHForwardingSocket {
	fileprivate let session: SSHSession
	private let destination: String
	private let destinationPort: Int
	private let socket: Int32
	private let accepterSource: DispatchSourceRead
	fileprivate let address: SSHListeningAddress
	private static let isLittleEndian: Bool = Int(littleEndian: 42) == 42
	private var connections: [SSHTunneledConnection] = []

	init?(session: SSHSession, destination: String, port: Int) {
		self.destination = destination
		self.destinationPort = port
		self.session = session

		self.socket = Darwin.socket(PF_INET, SOCK_STREAM, 0);
		if self.socket == -1 {
			return nil
		}

		// Set socket options
		var sockopt: Int = 1
		guard setsockopt(self.socket, SOL_SOCKET, SO_REUSEADDR, &sockopt, UInt32(MemoryLayout<Int>.size)) == 0 else { close(self.socket); return nil }
		guard setsockopt(self.socket, SOL_SOCKET, SO_NOSIGPIPE, &sockopt, UInt32(MemoryLayout<Int>.size)) == 0 else { close(self.socket); return nil }

		// Obtain an address
		var hints = addrinfo(
			ai_flags: AI_PASSIVE,
			ai_family: AF_INET,
			ai_socktype: SOCK_STREAM,
			ai_protocol: 0,
			ai_addrlen: 0,
			ai_canonname: nil,
			ai_addr: nil,
			ai_next: nil)

		var targetInfo: UnsafeMutablePointer<addrinfo>?
		let status: Int32 = getaddrinfo("127.0.0.1", nil, &hints, &targetInfo)

		if status != 0 {
			return nil
		}

		if bind(socket, targetInfo!.pointee.ai_addr, targetInfo!.pointee.ai_addrlen) == -1 {
			trace("bind() failed \(errno): \(String(cString:strerror(errno)))")
			freeaddrinfo(targetInfo!)
		}

		freeaddrinfo(targetInfo!)

		if listen(self.socket, SOMAXCONN) == -1 {
			trace("Not listening... \(errno)")
			return nil
		}

		// Get bound address
		let bound = sockaddr_storage()
		var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
		var boundAddress = bound.asAddr()
		if getsockname(self.socket, &boundAddress, &length) != 0 {
			return nil
		}

		// Get bound port
		if boundAddress.sa_family == sa_family_t(AF_INET) {
			var addr = sockaddr_in()
			memcpy(&addr, &boundAddress, Int(MemoryLayout<sockaddr_in>.size))
			let ip = String(cString: inet_ntoa(addr.sin_addr))
			let port: Int32
			if SSHForwardingSocket.isLittleEndian {
				port = Int32(UInt16(addr.sin_port).byteSwapped)
			}
			else {
				port = Int32(UInt16(addr.sin_port))
			}

			self.address = SSHListeningAddress(host: ip, port: Int(port))
		}
		else {
			return nil // Invalid family (IPv6?)
		}

		if fcntl(self.socket, F_SETFL, O_NONBLOCK) == -1 {
			trace("Error performing fcntl(F_SETFL, O_NONBLOCK) on socket")
		}

		self.accepterSource = DispatchSource.makeReadSource(fileDescriptor: self.socket, queue: DispatchQueue.global(qos: .default))
		self.accepterSource.setEventHandler(handler: self.handleConnection)
		self.accepterSource.setCancelHandler(handler: self.handleCancel)
		self.accepterSource.resume()

		trace("Listening on forwarding socket \(self.socket) port=\(port)")
	}

	deinit {
		trace("Closing forwarding socket \(self.socket)")
		close(self.socket)
	}

	fileprivate func channelClosed(_ channel: SSHTunneledConnection) {
		self.connections.remove(channel)
	}

	private func handleCancel() {
		trace("Accepter source cancelled")
	}

	private func handleConnection() {
		var acceptedAddress = sockaddr_in()
		var acceptedAddressSize = socklen_t(MemoryLayout<sockaddr_in>.size)

		let forwardSocket = withUnsafeMutablePointer(to: &acceptedAddress) {
			return accept(self.socket, UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self), &acceptedAddressSize)
		}

		trace("Accepted connection from \(String(describing: inet_ntoa(acceptedAddress.sin_addr))), now requesting a channel")
		self.session.mutex.locked {
			if let tc = SSHTunneledConnection(parent: self, socket: forwardSocket, destination: self.destination, port: self.destinationPort) {
				self.connections.append(tc)
			}
		}
	}
}

fileprivate class SSHSession {
	private static let client = SSHClient()
	fileprivate let session: OpaquePointer
	fileprivate var socket: Int32? = nil
	public var hostFingerprint: Data? = nil
	fileprivate let mutex = Mutex()

	init?() {
		let _ = SSHSession.client

		let session = SSHSession.client.mutex.locked {
			return libssh2_session_init_ex(nil, nil, nil, nil)
		}

		if let s = session {
			self.session = s
		}
		else {
			return nil
		}
	}

	/** Connect to the SSH server at the other end (perform handshake and request host key). The socket provided will be
	owned by SSHSession and will be freed by it on deinit. When returning successfully, the hostFingerprint variable is
	set and contains the host key. This function should only be called once. */
	fileprivate func connect(socket: Int32, callback: @escaping (Fallible<Void>) -> ()) {
		self.mutex.locked { () -> () in 
			assert(self.hostFingerprint == nil && self.socket == nil, "already connected or attempted to connect")
			self.socket = socket
			let err = libssh2_session_handshake(self.session, socket)
			if err != 0 {
				let msg = String(format: "SSH handshake failed: %@".localized, err)
				return callback(.failure(msg))
			}

			// Obtain host fingerprint
			if let fingerprint = libssh2_hostkey_hash(self.session, LIBSSH2_HOSTKEY_HASH_SHA1) {
				self.hostFingerprint = Data(bytes: fingerprint, count: 20)
				return callback(.success(()))
			}
			else {
				return callback(.failure("Could not obtain host fingerprint".localized))
			}
		}
	}

	fileprivate func login(username: String, authentication: SSHAuthentication, callback: @escaping (Fallible<Void>) -> ()) {
		self.mutex.locked { () -> () in
			if let uname = username.data(using: .ascii) {
				uname.withUnsafeBytes { (unameBytes : UnsafePointer<Int8>) -> () in
					if let userAuthList = libssh2_userauth_list(self.session, unameBytes, UInt32(uname.count)) {
						let str = String(cString: userAuthList)

						switch authentication {
						case .none:
							// No authentication needed, just go on
							return callback(.success(()))

						case .password(let password):
							if !str.contains("password") {
								let err = String(format: "Password authentication is not supported by the server. It only supports %@.".localized, str)
								return callback(.failure(err))
							}

							if let pw = password.data(using: .ascii) {
								pw.withUnsafeBytes { (pwBytes: UnsafePointer<Int8>) -> () in
									let err = libssh2_userauth_password_ex(self.session, unameBytes, UInt32(pw.count), pwBytes, UInt32(pw.count), nil)
									if err != 0 {
										let msg = String(format: "Password authentication failed: %@".localized, err)
										return callback(.failure(msg))
									}
									else {
										return callback(.success(()))
									}
								}
							}
							else {
								return callback(.failure("password is not ascii"))
							}

						case .key(file: let keyFile, passphrase: let keyPassphrase):
							if !str.contains("publickey") {
								let err = String(format: "Public key authentication is not supported by the server. It only supports: %@.".localized, str)
								return callback(.failure(err))
							}

							if let u = keyFile {
								self.authenticateUsingKey(u, passphrase: keyPassphrase, username: username, callback: callback)
							}
							else {
								return callback(.failure("No key file selected".localized))
							}

						}
					}
					else {
						return callback(.failure("Could not obtain supported authentication mechanisms".localized))
					}
				}
			}
			else {
				return callback(.failure("The provided username is not ASCII".localized))
			}
		}
	}

	private var lastError: String? {
		return self.mutex.locked { () -> String? in
			var message: UnsafeMutablePointer<Int8>? = nil
			libssh2_session_last_error(self.session, &message, nil, 0)
			if let m = message {
				return String(cString: m)
			}
			return nil
		}
	}

	fileprivate func authenticateUsingKey(_ keyFile: URL, passphrase: String, username: String, callback: @escaping (Fallible<Void>) -> ()) {
		self.mutex.locked { () -> () in
			let keyFilePath = keyFile.path
			if let uname = username.data(using: .ascii) {
				uname.withUnsafeBytes { (unameBytes : UnsafePointer<Int8>) -> () in
					let err = libssh2_userauth_publickey_fromfile_ex(self.session, unameBytes, UInt32(uname.count), nil, keyFilePath, passphrase)
					if err != 0 {
						switch err {
						case LIBSSH2_ERROR_ALLOC: return callback(.failure("memory allocation failed during key authentication"))
						case LIBSSH2_ERROR_SOCKET_SEND: return callback(.failure("Unable to send data on socket during key authentication"))
						case LIBSSH2_ERROR_SOCKET_TIMEOUT: return callback(.failure("Socket timeout during key authentication"))
						case LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED: return callback(.failure("The username/public key combination was invalid."))
						case LIBSSH2_ERROR_AUTHENTICATION_FAILED: return callback(.failure("Authentication using the supplied public key was not accepted."))
						default:
							return callback(.failure("An unknown error occurred during key authentication: \(self.lastError ?? "(unknown)")"))
						}
					}
					else {
						return callback(.success(()))
					}
				}
			}
			else {
				return callback(.failure("provided username is not ASCII"))
			}
		}
	}

	fileprivate func tunnel(destination: String, port: Int, callback: @escaping (Fallible<SSHForwardingSocket>) -> ()) {
		self.mutex.locked {
			if let socket = SSHForwardingSocket(session: self, destination: destination, port: port) {
				callback(.success(socket))
			}
			else {
				callback(.failure("Could not create forwarding socket"))
			}
		}
	}

	deinit {
		let session = self.session

		if let s = socket {
			close(s)
		}

		self.mutex.locked {
			trace("Closing session \(session)")
			libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "Bye ".cString(using: .ascii), "".cString(using: .ascii))
			libssh2_session_free(session)
		}
	}
}

public class SSHTunnel {
	private var session: SSHSession? = nil
	private var currentConfiguration: SSHConfiguration? = nil
	private var listeningSocket: SSHForwardingSocket? = nil
	private let mutex = Mutex()

	public init() {
	}

	deinit {
		trace("SSH tunnel deinit")
	}

	public func connect(job: Job, configuration: SSHConfiguration, host: String, port: Int, callback: @escaping (Fallible<SSHListeningAddress>) -> ()) {
		self.mutex.locked { () -> () in 
			if let ea = listeningSocket, let current = self.currentConfiguration, current == configuration {
				// Current tunnel will do
				job.async {
					return callback(.success(ea.address))
				}
			}
			else {
				// Close existing tunnel
				self.session = nil
				self.listeningSocket = nil
				self.currentConfiguration = configuration

				// Do we need a tunnel at all?
				if !configuration.enabled {
					job.async {
						return callback(.success(SSHListeningAddress(host: host, port: port)))
					}
					return
				}

				job.async {
					// Open the secure connection
					configuration.connect { result in
						switch result {
						case .success(let session):
							self.mutex.locked {
								self.session = session
							}

							// Configure the tunnel
							session.tunnel(destination: host, port: port) { result in
								switch result {
								case .success(let ls):
									self.mutex.locked {
										self.listeningSocket = ls
									}

									job.async {
										callback(.success(ls.address))
									}

								case .failure(let e):
									callback(.failure(e))
								}
							}

						case .failure(let e):
							self.mutex.locked {
								self.currentConfiguration = nil
							}

							callback(.failure(e))
						}
					}
				}
			}
		}
	}
}

/** Stores tunnel configuration details. */
public class SSHConfiguration: NSObject, NSCoding {
	public let mutex = Mutex()
	public var enabled: Bool = false
	public var host: String
	public var port: Int
	public var username: String
	public var authentication: SSHAuthentication = .none
	public var hostFingerprint: Data? = nil

	public override init() {
		self.host = "example.com"
		self.port = 22
		self.username = "admin"
		super.init()
	}

	required public init?(coder aDecoder: NSCoder) {
		host = aDecoder.decodeString(forKey: "host") ?? "example.com"
		port = aDecoder.decodeInteger(forKey: "port")
		username = aDecoder.decodeString(forKey: "username") ?? "admin"
		if let hostBase64 = aDecoder.decodeString(forKey: "hostFingerprint") {
			hostFingerprint = Data(base64Encoded: hostBase64)
		}

		enabled = aDecoder.decodeBool(forKey: "enabled")

		let auth = aDecoder.decodeString(forKey: "authentication") ?? "password"
		if auth == "password" {
			// Password should be fetched from keychain by user
			self.authentication = .password("")
		}
		else if auth == "key" {
			self.authentication = .key(file: nil, passphrase: "")
		}

		super.init()

		if port <= 0 || port > 65535 {
			port = 22
		}
	}

	public func encode(with aCoder: NSCoder) {
		aCoder.encodeString(username, forKey: "username")
		aCoder.encodeString(host, forKey: "host")
		aCoder.encode(port, forKey: "port")
		aCoder.encode(self.enabled, forKey: "enabled")

		if let hf = hostFingerprint {
			aCoder.encodeString(hf.base64EncodedString(), forKey: "hostFingerprint")
		}

		switch authentication {
		case .password:
			// The password itself should be saved by the user of this class (e.g. to keychain)
			aCoder.encodeString("password", forKey: "authentication")
		case .key(file: _, passphrase: _):
			aCoder.encodeString("key", forKey: "authentication")
		case .none: break
		}
	}

	/** Test the connection, return errors. This will save the host fingerprints if there isn't one saved yet. */
	public func test(callback: @escaping (String?) -> ()) {
		self.connect { result in
			switch result {
			case .success(_):
				callback(nil)

			case .failure(let e):
				callback(e)
			}
		}
	}

	fileprivate func connect(callback: @escaping (Fallible<SSHSession>) -> ()) {
		var hints = addrinfo(
			ai_flags: AI_PASSIVE,
			ai_family: AF_UNSPEC,
			ai_socktype: SOCK_STREAM,
			ai_protocol: IPPROTO_TCP,
			ai_addrlen: 0,
			ai_canonname: nil,
			ai_addr: nil,
			ai_next: nil)

		self.mutex.locked { () -> () in
			var info: UnsafeMutablePointer<addrinfo>? = nil
			let err = getaddrinfo(host, String(port), &hints, &info)
			if err == 0 {
				defer { freeaddrinfo(info) }
				let sock = socket(info!.pointee.ai_family, info!.pointee.ai_socktype, info!.pointee.ai_protocol);
				if sock == -1 {
					return callback(.failure("Could not create socket"))
				}

				// FIXME: set a timeout here (possibly set the socket to non-blocking mode, use select() to detect connection
				let err = Darwin.connect(sock, info!.pointee.ai_addr, info!.pointee.ai_addrlen)
				if err == 0 {
					if let sess = SSHSession() {
						sess.connect(socket: sock) { result in
							switch result {
							case .success():
								// Check host key fingerprint
								sess.mutex.locked { () -> () in
									self.mutex.locked {
										if let hf = self.hostFingerprint {
											if hf == sess.hostFingerprint! {
												// Host fingerprint is OK, time to authenticate
												sess.login(username: self.username, authentication: self.authentication) { result in
													switch result {
													case .success():
														return callback(.success(sess))

													case .failure(let e):
														return callback(.failure(e))
													}
												}
											}
											else {
												// Host fingerprint not OK
												let friendly = sess.hostFingerprint!.map { String(format: "%02hhx", $0) }.joined(separator: ":")
												let err = String(format: "The fingerprint saved for this host does not match the fingerprint provided by the host: %@".localized, friendly)
												return callback(.failure(err))
											}
										}
										else {
											// We don't have a host fingerprint yet! Save and fail
											sess.mutex.locked { () -> () in 
												let friendly = sess.hostFingerprint!.map { String(format: "%02hhx", $0) }.joined(separator: ":")
												self.mutex.locked {
													self.hostFingerprint = sess.hostFingerprint
												}

												let err = String(format: "No host fingerprint was set; please verify that the fingerprint '%@' is correct, and reconnect.".localized, friendly)
												return callback(.failure(err))
											}
										}
									}
								}

							case .failure(let e):
								return callback(.failure(e))
							}
						}
					}
					else {
						return callback(.failure("Could not start SSH session".localized))
					}
				}
				else {
					if let s = strerror(err) {
						let cs = String(cString: s)
						return callback(.failure(cs))
					}
					return callback(.failure("connect failed: \(err)"))
				}
			}
			else {
				if let s = strerror(err) {
					let cs = String(cString: s)
					return callback(.failure(cs))
				}
				return callback(.failure("getaddrinfo failed: \(err)"))
			}
		}
	}
}

public func == (lhs: SSHAuthentication, rhs: SSHAuthentication) -> Bool {
	switch (lhs, rhs) {
	case (.none, .none):
		return true

	case (.password(let s), .password(let h)):
		return s == h

	default:
		return false
	}
}

public func == (lhs: SSHConfiguration, rhs: SSHConfiguration) -> Bool {
	return
		lhs.enabled == rhs.enabled &&
		lhs.host == rhs.host &&
		lhs.hostFingerprint == rhs.hostFingerprint &&
		lhs.username == rhs.username &&
		lhs.authentication == rhs.authentication
}

internal extension String {
	var localized: String {
		let bundle = Bundle(for: SSHTunnel.self)
		return NSLocalizedString(self, tableName: nil, bundle: bundle, value: self, comment: "")
	}
}
