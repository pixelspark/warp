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
import WarpConduit
import Rethink

class QBERethinkSourceStep: QBEStep {
	var database: String = "test"
	var table: String = "test"
	var server: String = "localhost"
	var port: Int = 28015
	var username: String = "admin"
	var useUsernamePasswordAuthentication = true
	var authenticationKey: String? = nil
	var columns: OrderedSet<Column> = []

	var password: QBESecret {
		return QBESecret(serviceType: "rethinkdb", host: server, port: port, account: username, friendlyName:
			String(format: NSLocalizedString("User %@ at RethinkDB server %@ (port %d)", comment: ""), username, server, port))
	}

	required override init(previous: QBEStep?) {
		super.init()
	}

	required init() {
		super.init()
	}

	required init(coder aDecoder: NSCoder) {
		self.server = aDecoder.decodeString(forKey:"server") ?? "localhost"
		self.table = aDecoder.decodeString(forKey:"table") ?? "test"
		self.database = aDecoder.decodeString(forKey:"database") ?? "test"
		self.port = max(1, min(65535, aDecoder.decodeInteger(forKey: "port")));

		let authenticationKey = aDecoder.decodeString(forKey:"authenticationKey")
		self.authenticationKey = authenticationKey
		self.username = aDecoder.decodeString(forKey:"username") ?? "admin"
		self.useUsernamePasswordAuthentication = aDecoder.containsValue(forKey: "useUsernamePasswordAuthentication") ?
			aDecoder.decodeBool(forKey: "useUsernamePasswordAuthentication") :
			(authenticationKey == nil || authenticationKey!.isEmpty)

		let cols = (aDecoder.decodeObject(forKey: "columns") as? [String]) ?? []
		self.columns = OrderedSet<Column>(cols.map { return Column($0) })
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encodeString(self.server, forKey: "server")
		coder.encodeString(self.database, forKey: "database")
		coder.encodeString(self.table, forKey: "table")
		coder.encode(self.port, forKey: "port")
		coder.encode(NSArray(array: self.columns.map { return $0.name }), forKey: "columns")
		coder.encode(self.useUsernamePasswordAuthentication, forKey: "useUsernamePasswordAuthentication")
		if self.useUsernamePasswordAuthentication {
			coder.encodeString(self.username, forKey: "username")
		}
		else {
			if let s = self.authenticationKey {
				coder.encodeString(s, forKey: "authenticationKey")
			}
		}
	}

	internal var url: URL? { get {
		if let u = self.authenticationKey, !u.isEmpty && !self.useUsernamePasswordAuthentication {
			let urlString = "rethinkdb://\(u.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlUserAllowed)!)@\(self.server.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!):\(self.port)"
			return URL(string: urlString)
		}
		else {
			let urlString = "rethinkdb://\(self.server.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!):\(self.port)"
			return URL(string: urlString)
		}
	} }

	private func sourceDataset(_ callback: @escaping (Fallible<Dataset>) -> ()) {
		if let u = url {
			let table = R.db(self.database).table(self.table)
			let password: String
			if useUsernamePasswordAuthentication {
				password = self.password.stringValue ?? ""
			}
			else {
				password = ""
			}

			if self.columns.count > 0 {
				let q = table.withFields(self.columns.map { return R.expr($0.name) })
				callback(.success(RethinkDataset(url: u, query: q, columns: self.columns.count > 0 ? self.columns : nil)))
			}
			else {
				// Username and password are ignored when using V0_4. The authentication key will be in the URL for V0_4 (if set)
				R.connect(u, user: self.username, password: password, version: (self.useUsernamePasswordAuthentication ? .v1_0 : .v0_4), callback: { (err, connection) -> () in
					if let e = err {
						callback(.failure(e.localizedDescription))
						return
					}

					table.indexList().run(connection) { response in
						if case .Value(let indices) = response, let indexList = indices as? [String] {
							callback(.success(RethinkDataset(url: u, query: table, columns: !self.columns.isEmpty ? self.columns : nil, indices: Set(indexList.map { return Column($0) }))))
						}
						else {
							// Carry on without indexes
							callback(.success(RethinkDataset(url: u, query: table, columns: !self.columns.isEmpty ? self.columns : nil, indices: nil)))
						}
					}
				})
			}
		}
		else {
			callback(.failure(NSLocalizedString("The location of the RethinkDB server is invalid.", comment: "")))
		}
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		sourceDataset(callback)
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		sourceDataset { t in
			switch t {
			case .failure(let e): callback(.failure(e))
			case .success(let d): callback(.success(d.limit(maxInputRows)))
			}
		}
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .read, .neutral: template = "Read table [#] from RethinkDB database [#]"
		case .write: template = "Write to table [#] in RethinkDB database [#]";
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceDynamicOptionsToken(value: self.table, provider: { pc in
				R.connect(self.url!, callback: { (err, connection) in
					if err != nil {
						pc(.failure(err!.localizedDescription))
						return
					}

					R.db(self.database).tableList().run(connection) { (response) in
						/* While it is not strictly necessary to close the connection explicitly, we do it here to keep 
						a reference to the connection, as to keep the connection alive until the query returns. */
						connection.close()
						if case .error(let e) = response {
							pc(.failure(e))
							return
						}

						if let v = response.value as? [String] {
							pc(.success(v))
						}
						else {
							pc(.failure("invalid list received"))
						}
					}
				})
				}, callback: { (newTable) -> () in
					self.table = newTable
				}),


			QBESentenceDynamicOptionsToken(value: self.database, provider: { pc in
				R.connect(self.url!, callback: { (err, connection) in
					if err != nil {
						pc(.failure(err!.localizedDescription))
						return
					}

					R.dbList().run(connection) { (response) in
						/* While it is not strictly necessary to close the connection explicitly, we do it here to keep
						a reference to the connection, as to keep the connection alive until the query returns. */
						connection.close()
						if case .error(let e) = response {
							pc(.failure(e))
							return
						}

						if let v = response.value as? [String] {
							pc(.success(v))
						}
						else {
							pc(.failure("invalid list received"))
						}
					}
				})
			}, callback: { (newDatabase) -> () in
				self.database = newDatabase
			})
		)
	}

	override var mutableDataset: MutableDataset? {
		if let u = self.url, !self.table.isEmpty {
			return RethinkMutableDataset(url: u, databaseName: self.database, tableName: self.table)
		}
		return nil
	}
}
