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

class QBECockroachSourceStep: QBEStep {
	var tableName: String = ""
	var host: String = "localhost"
	var user: String = "postgres"
	var databaseName: String = "information_schema"
	var port: Int = 26257

	var password: QBESecret {
		return QBESecret(serviceType: "cockroach", host: host, port: port, account: user, friendlyName: String(format: NSLocalizedString("User %@ at CockroachDB server %@ (port %d)", comment: ""), user, host, port))
	}

	init(host: String, port: Int, user: String, database: String,  tableName: String) {
		self.host = host
		self.user = user
		self.port = port
		self.databaseName = database
		self.tableName = tableName
		super.init()
	}

	required init() {
		super.init()
	}

	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? ""
		self.host = (aDecoder.decodeObject(forKey: "host") as? String) ?? ""
		self.databaseName = (aDecoder.decodeObject(forKey: "database") as? String) ?? ""
		self.user = (aDecoder.decodeObject(forKey: "user") as? String) ?? ""
		self.port = Int(aDecoder.decodeInteger(forKey: "port"))
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(tableName, forKey: "tableName")
		coder.encode(host, forKey: "host")
		coder.encode(user, forKey: "user")
		coder.encode(databaseName, forKey: "database")
		coder.encode(port , forKey: "port")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .neutral, .read:
			template = "Load table [#] in CockroachDB database [#]"

		case .write:
			template = "Write to table [#] in CockroachDB database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			   QBESentenceDynamicOptionsToken(value: self.tableName , provider: { (callback) -> () in
					if let d = self.database {
						d.tables(self.databaseName) { tablesFallible in
							switch tablesFallible {
							case .success(let tables):
								callback(.success(tables))

							case .failure(let e):
								callback(.failure(e))
							}
						}
					}
					else {
						callback(.failure(NSLocalizedString("Could not connect to database", comment: "")))
					}
				}, callback: { (newTable) -> () in
					self.tableName = newTable
				}),
			   QBESentenceDynamicOptionsToken(value: self.databaseName , provider: { (callback) -> () in
					if let d = self.database {
						d.databases { dbFallible in
							switch dbFallible {
							case .success(let dbs):
								callback(.success(dbs))

							case .failure(let e):
								callback(.failure(e))
							}
						}
					}
					else {
						callback(.failure(NSLocalizedString("Could not connect to database", comment: "")))
					}
				}, callback: { (newDatabase) -> () in
				self.databaseName = newDatabase
				})
		)
	}

	internal var database: CockroachDatabase? {
		/* For PostgreSQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. Cockroach
		does not use UNIX sockets. To avoid issues we rewrite localhost here to 127.0.0.1 in order to force access 
		through TCP/IP. */
		let ha = (host == "localhost") ? "127.0.0.1" : host
		return CockroachDatabase(host: ha, port: port, user: user, password: self.password.stringValue ?? "", database: databaseName)
	}

	override func mutableDataset(_ job: Job, callback: @escaping (Fallible<MutableDataset>) -> ()) {
		if let d = self.database, !tableName.isEmpty {
			return callback(.success(CockroachMutableDataset(database: d, schemaName: nil, tableName: tableName)))
		}
		return callback(.failure("No table selected".localized))
	}

	var warehouse: Warehouse? {
		if let d = self.database {
			return SQLWarehouse(database: d, schemaName: nil)
		}
		return nil
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		job.async {
			if let s = self.database {
				// Check whether the connection details are right
				s.connect { res in
					switch res {
					case .success(_):
						if !self.tableName.isEmpty {
							callback(CockroachDataset.create(database: s, tableName: self.tableName).use({ return $0.coalesced }))
						}
						else {
							callback(.failure(NSLocalizedString("No database or table selected", comment: "")))
						}

					case .failure(let e):
						callback(.failure(e))
					}
				}
			}
			else {
				callback(.failure(NSLocalizedString("No database or table selected", comment: "")))
			}
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}
}
