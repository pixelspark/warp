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

class QBEPrestoSourceStep: QBEStep {
	var catalogName: String = "default" { didSet { switchDatabase() } }
	var schemaName: String = "default" { didSet { switchDatabase() } }
	var tableName: String = "default" { didSet { switchDatabase() } }
	var url: String = "http://localhost:8080" { didSet { switchDatabase() } }
	
	private var db: PrestoDatabase?

	required init() {
		super.init()
	}
	
	init(url: String?) {
		super.init()
		self.url = url ?? self.url
		switchDatabase()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		self.catalogName = aDecoder.decodeString(forKey: "catalog") ?? self.catalogName
		self.tableName = aDecoder.decodeString(forKey: "table") ?? self.catalogName
		self.schemaName = aDecoder.decodeString(forKey: "schema") ?? self.catalogName
		self.url = (aDecoder.decodeObject(forKey: "url") as? String) ?? self.url
		switchDatabase()
	}
	
	override func encode(with coder: NSCoder) {
		coder.encode(self.url, forKey: "url")
		coder.encode(self.catalogName, forKey: "catalog")
		coder.encode(self.schemaName, forKey: "schema")
		coder.encode(self.tableName, forKey: "table")
		super.encode(with: coder)
	}
	
	private func explanation(_ locale: Language) -> String {
		return String(format: NSLocalizedString("Table '%@' from Presto server",comment: ""), tableName)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Table [#] from schema [#] in catalog [#] on Presto server [#]".localized,
		   QBESentenceDynamicOptionsToken(value: self.tableName, provider: { (callback) -> () in
				let job = Job(.userInitiated)
				self.tableNames(job, callback: { (result) in
					switch result {
					case .success(let tables):
						callback(.success(Array(tables)))

					case .failure(let e):
						callback(.failure(e))
					}
				})

			}, callback: { (newTable) -> () in
				self.tableName = newTable
			}),

		   QBESentenceDynamicOptionsToken(value: self.schemaName, provider: { (callback) -> () in
				let job = Job(.userInitiated)
				self.schemaNames(job, callback: { (result) in
					switch result {
					case .success(let tables):
						callback(.success(Array(tables)))

					case .failure(let e):
						callback(.failure(e))
					}
				})

				}, callback: { (newSchema) -> () in
					self.schemaName = newSchema
			}),

		   QBESentenceDynamicOptionsToken(value: self.catalogName, provider: { (callback) -> () in
				let job = Job(.userInitiated)
				self.catalogNames(job, callback: { (result) in
					switch result {
					case .success(let catalogs):
						callback(.success(Array(catalogs)))

					case .failure(let e):
						callback(.failure(e))
					}
				})

				}, callback: { (newCatalog) -> () in
					self.catalogName = newCatalog
			}),

			QBESentenceTextToken(value: self.url, callback: { (newURL) -> (Bool) in
				if !newURL.isEmpty {
					self.url = newURL
					return true
				}
				return false
			})
		)
	}
	
	private func switchDatabase() {
		self.db = nil
		
		if !self.url.isEmpty {
			if let url = URL(string: self.url) {
				db = PrestoDatabase(url: url, catalog: catalogName, schema: schemaName)
			}
		}
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let d = db, !self.tableName.isEmpty {
			PrestoDataset.tableDataset(job, db: d, tableName: tableName, schemaName: schemaName, catalogName: catalogName, callback: { (fd) -> () in
				callback(fd.use({return $0}))
			})
		}
		else {
			callback(.failure(NSLocalizedString("No database and/or table name have been set.", comment: "")))
		}
	}
	
	func catalogNames(_ job: Job, callback: @escaping (Fallible<Set<String>>) -> ()) {
		if let d = db {
			StreamDataset(source: d.query("SHOW CATALOGS")).unique(Sibling(Column("Catalog")), job: job) { (catalogNamesFallible) -> () in
				callback(catalogNamesFallible.use({(tn) -> (Set<String>) in return Set(tn.map({return $0.stringValue ?? ""})) }))
			}
		}
		else {
			callback(.failure(NSLocalizedString("No database and/or table name have been set.", comment: "")))
		}
	}
	
	func schemaNames(_ job: Job, callback: @escaping (Fallible<Set<String>>) -> ()) {
		if let stream = db?.query("SHOW SCHEMAS") {
			StreamDataset(source: stream).unique(Sibling(Column("Schema")), job: job, callback: { (schemaNamesFallible) -> () in
				callback(schemaNamesFallible.use({(sn) in Set(sn.map({return $0.stringValue ?? ""})) }))
			})
		}
	}
	
	func tableNames(_ job: Job, callback: @escaping (Fallible<Set<String>>) -> ()) {
		if let stream = db?.query("SHOW TABLES") {
			StreamDataset(source: stream).unique(Sibling(Column("Table")), job: job, callback: { (tableNamesFallible) -> () in
				callback(tableNamesFallible.use({(tn) in Set(tn.map({return $0.stringValue ?? ""})) }))
			})
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			// Other SQL data sources use random rows, but that doesn't work well with Presto
			callback(fd.use({$0.limit(maxInputRows)}))
		})
	}
}
