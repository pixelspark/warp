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

class QBEMySQLSourceStep: QBEStep {
	var tableName: String? = nil
	var host: String = "localhost"
	var user: String = "root"
	var databaseName: String? = nil
	var port: Int = 3306

	var password: QBESecret {
		return QBESecret(serviceType: "mysql", host: host, port: port, account: user, friendlyName: String(format: NSLocalizedString("User %@ at MySQL server %@ (port %d)", comment: ""), user, host, port))
	}
	
	init(host: String, port: Int, user: String, database: String?, tableName: String?) {
		self.host = host
		self.user = user
		self.port = port
		self.databaseName = database
		self.tableName = tableName
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

		let host = (aDecoder.decodeObject(forKey: "host") as? String) ?? self.host
		let user = (aDecoder.decodeObject(forKey: "user") as? String) ?? self.user
		let port = Int(aDecoder.decodeInteger(forKey: "port"))

		if let pw = aDecoder.decodeString(forKey:"password") {
			self.password.stringValue = pw
		}

		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? self.tableName
		self.databaseName = (aDecoder.decodeObject(forKey: "database") as? String) ?? self.databaseName
		self.user = user
		self.host = host
		self.port = port
	}

	required init() {
	    super.init()
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(tableName, forKey: "tableName")
		coder.encode(host, forKey: "host")
		coder.encode(user, forKey: "user")
		coder.encode(databaseName, forKey: "database")
		coder.encode(port, forKey: "port")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .neutral, .read: template = "Load table [#] from MySQL database [#]"
		case .write: template = "Write to table [#] in MySQL database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceDynamicOptionsToken(value: self.tableName ?? "", provider: { (callback) -> () in
				let d = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
				switch d.connect() {
				case .success(let con):
					con.tables { tablesFallible in
						switch tablesFallible {
						case .success(let tables):
							callback(.success(tables))

						case .failure(let e):
							callback(.failure(e))
						}
					}

				case .failure(let e):
					callback(.failure(e))
				}
			}, callback: { (newTable) -> () in
					self.tableName = newTable
			}),

			QBESentenceDynamicOptionsToken(value: self.databaseName ?? "", provider: { callback in
				/* Connect without selecting a default database, because the database currently selected may not exists
				(and then we get an error, and can't select another database). */
				let d = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: nil)
				switch d.connect() {
				case .success(let con):
					con.databases { dbFallible in
						switch dbFallible {
							case .success(let dbs):
								callback(.success(dbs))

							case .failure(let e):
								callback(.failure(e))
						}
					}

				case .failure(let e):
					callback(.failure(e))
				}
			}, callback: { (newDatabase) -> () in
				self.databaseName = newDatabase
			})
		)
	}

	internal var hostToConnectTo: String {
		/* For MySQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. This does
		not work from a sandboxed application unless special privileges are obtained. To avoid confusion we rewrite
		localhost here to 127.0.0.1 in order to force access through TCP/IP. */
		return (host == "localhost") ? "127.0.0.1" : host
	}

	override var mutableDataset: MutableDataset? { get {
		if let tn = self.tableName, !tn.isEmpty {
			let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
			return QBEMySQLMutableDataset(database: s, schemaName: nil, tableName: tn)
		}
		return nil
	} }

	var warehouse: Warehouse? {
		let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
		return SQLWarehouse(database: s, schemaName: nil)
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		job.async {
			// First check whether the connection details are right
			let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
			switch  s.connect() {
			case .success(_):
				if let dbn = self.databaseName, !dbn.isEmpty {
					if let tn = self.tableName, !tn.isEmpty {
						let md = QBEMySQLDataset.create(s, tableName: tn)
						callback(md.use { $0.coalesced })
					}
					else {
						callback(.failure(NSLocalizedString("Please select a table.", comment: "")))
					}
				}
				else {
					callback(.failure(NSLocalizedString("Please select a database.", comment: "")))
				}
			case .failure(let e):
				callback(.failure(e))
			}
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		job.async {
			// First check whether the connection details are right
			let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
			switch  s.connect() {
			case .success(let con):
				if let dbn = self.databaseName, !dbn.isEmpty, let tn = self.tableName, !tn.isEmpty {
					con.constraints(fromTable: tn, inDatabase: dbn) { result in
						switch result {
						case .success(let constraints):
							let steps = constraints.map { constraint -> QBERelatedStep in
								let sourceStep = QBEMySQLSourceStep(host: self.host, port: self.port, user: self.user, database: constraint.referencedDatabase, tableName: constraint.referencedTable)
								let joinExpression = Comparison(first: Sibling(Column(constraint.column)), second: Foreign(Column(constraint.referencedColumn)), type: .equal)
								return QBERelatedStep.joinable(step: sourceStep, type: .leftJoin, condition: joinExpression)
							}
							return callback(.success(steps))

						case .failure(let e):
							return callback(.failure(e))
						}
					}
				}
				else {
					return callback(.failure("No database or table selected".localized))
				}

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}
