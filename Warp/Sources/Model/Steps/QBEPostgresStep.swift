/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

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

class QBEPostgresSourceStep: QBEStep {
	var tableName: String = ""
	var host: String = "localhost"
	var user: String = "postgres"
	var databaseName: String = "postgres"
	var schemaName: String = "public"
	var port: Int = 5432
	let defaultSchemaName = "public"

	var password: QBESecret {
		return QBESecret(serviceType: "postgres", host: host, port: port, account: user, friendlyName: String(format: NSLocalizedString("User %@ at PostgreSQL server %@ (port %d)", comment: ""), user, host, port))
	}
	
	init(host: String, port: Int, user: String, database: String,  schemaName: String, tableName: String) {
		self.host = host
		self.user = user
		self.port = port
		self.databaseName = database
		self.tableName = tableName
		self.schemaName = schemaName
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
		self.schemaName = aDecoder.decodeString(forKey:"schema") ?? ""
		super.init(coder: aDecoder)

		if let pw = (aDecoder.decodeObject(forKey: "password") as? String) {
			self.password.stringValue = pw
		}
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(tableName, forKey: "tableName")
		coder.encode(host, forKey: "host")
		coder.encode(user, forKey: "user")
		coder.encode(databaseName, forKey: "database")
		coder.encode(port , forKey: "port")
		coder.encodeString(schemaName , forKey: "schema")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .neutral, .read:
			template = "Load table [#] from schema [#] in PostgreSQL database [#]"

		case .write:
			template = "Write to table [#] in schema [#] in PostgreSQL database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceDynamicOptionsToken(value: self.tableName , provider: { (callback) -> () in
				if let d = self.database {
					d.tables(self.databaseName , schemaName: self.schemaName ) { tablesFallible in
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

			QBESentenceDynamicOptionsToken(value: self.schemaName, provider: { (callback) -> () in
				if let d = self.database {
					d.schemas(self.databaseName ) { schemaFallible in
						switch schemaFallible {
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
			}, callback: { (newSchema) -> () in
					self.schemaName = newSchema
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
	
	internal var database: PostgresDatabase? {
		/* For PostgreSQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. This does
		not work from a sandboxed application unless special privileges are obtained. To avoid confusion we rewrite
		localhost here to 127.0.0.1 in order to force access through TCP/IP. */
		let ha = (host == "localhost") ? "127.0.0.1" : host
		return PostgresDatabase(host: ha, port: port, user: user, password: self.password.stringValue ?? "", database: databaseName)
	}

	override var mutableDataset: MutableDataset? {
		if let d = self.database, !tableName.isEmpty && !schemaName.isEmpty {
			return PostgresMutableDataset(database: d, schemaName: schemaName, tableName: tableName)
		}
		return nil
	}

	var warehouse: Warehouse? {
		if let d = self.database, !schemaName.isEmpty {
			return SQLWarehouse(database: d, schemaName: schemaName)
		}
		return nil
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		job.async {
			if let s = self.database {
				// Check whether the connection details are right
				switch s.connect() {
				case .success(_):
					if !self.tableName.isEmpty {
						callback(PostgresDataset.create(database: s, tableName: self.tableName, schemaName: self.schemaName).use({ return $0.coalesced }))
					}
					else {
						callback(.failure(NSLocalizedString("No database or table selected", comment: "")))
					}

				case .failure(let e):
					callback(.failure(e))
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
