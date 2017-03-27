/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Alamofire
import WarpCore

private class QBEPrestoSQLDialect: StandardSQLDialect {
	override func unaryToSQL(_ type: Function, args: [String]) -> String? {
		switch type {
		case .concat:
			/** Presto doesn't support CONCAT'ing more than two arguments. Therefore, we need to nest them. */
			if args.count == 1 {
				return args.first!
			}
			if args.count > 1 {
				var sql = args.last
				for a in Array(args.dropLast().reversed()) {
					sql = "CONCAT(\(a), \(String(describing: sql)))"
				}
				return sql
			}
			return nil
			
		default:
			return super.unaryToSQL(type, args: args)
		}
	}
	
	fileprivate override func forceNumericExpression(_ expression: String) -> String {
		return "TRY_CAST(\(expression) AS DOUBLE)"
	}
	
	fileprivate override func forceStringExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS VARCHAR)"
	}
}

private class QBEPrestoStream: NSObject, WarpCore.Stream {
	let url: URL
	let sql: String
	let catalog: String
	let schema: String
	
	private var buffer: [Tuple] = []
	private var columns: Fallible<OrderedSet<Column>>?
	private var stopped: Bool = false
	private var started: Bool = false
	private var nextURI: URL?
	private var columnsFuture: Future<Fallible<OrderedSet<Column>>>! = nil
	private var mutex = Mutex()
	
	init(url: URL, sql: String, catalog: String, schema: String) {
		self.url = url
		self.sql = sql
		self.schema = schema
		self.catalog = catalog
		self.nextURI = self.url.appendingPathComponent("/v1/statement")
		super.init()
		
		let c = { [weak self] (job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) -> () in
			self?.awaitColumns(job) { result in
				switch result {
				case .success():
					callback(self?.columns ?? .failure(NSLocalizedString("Could not load column names from Presto.", comment: "")))

				case .failure(let e):
					callback(.failure(e))
				}
			}
		}
		
		self.columnsFuture = Future<Fallible<OrderedSet<Column>>>(c)
	}
	
	/** Request the next batch of result data from Presto. */
	private func request(_ job: Job, callback: @escaping (Fallible<()>) -> ()) {
		self.mutex.locked { () -> () in
			if stopped {
				return callback(.success())
			}
			
			if let endpoint = self.nextURI {
				let request = NSMutableURLRequest(url: endpoint)
				request.setValue("Warp", forHTTPHeaderField: "User-Agent")
			
				if !started {
					// Initial request
					started = true
					request.httpMethod = "POST"
					request.setValue("Warp", forHTTPHeaderField: "X-Presto-User")
					request.setValue("Warp", forHTTPHeaderField: "X-Presto-Source")
					request.setValue(self.catalog, forHTTPHeaderField: "X-Presto-Catalog")
					request.setValue(self.schema, forHTTPHeaderField: "X-Presto-Schema")
					
					if let sqlDataset = sql.data(using: String.Encoding.utf8, allowLossyConversion: false) {
						request.httpBody = sqlDataset
					}
				}
				else {
					// Follow-up request
					request.httpMethod = "GET"
				}

				Alamofire.request(request as URLRequest).responseJSON(options: [], completionHandler: { response in
					if response.result.isSuccess {
						// Let's see if the response got something useful
						if let d = response.result.value as? [String: AnyObject] {
							// Get progress data from response
							if let stats = d["stats"] as? [String: AnyObject] {
								if let completedSplits = stats["completedSplits"] as? Int,
									let queuedSplits = stats["queuedSplits"] as? Int {
									if (completedSplits + queuedSplits) > 0 {
										let progress = Double(completedSplits) / Double(completedSplits + queuedSplits)
										job.reportProgress(progress, forKey: self.hash)
									}
								}
							}

							self.mutex.locked {
								// Does the response tell us where to look next?
								if let nu = (d["nextUri"] as? String) {
									self.nextURI = URL(string: nu)
								}
								else {
									self.nextURI = nil
									self.stopped = true
								}
							}

							// Does the response include column information?
							if self.columns == nil {
								if let columns = d["columns"] as? [AnyObject] {
									var newColumns: OrderedSet<Column> = []

									for columnSpec in columns {
										if let columnInfo = columnSpec as? [String: AnyObject] {
											if let name = columnInfo["name"] as? String {
												newColumns.append(Column(name))
											}
										}
									}
									self.columns = .success(newColumns)
								}
							}

							// Does the response contain any data?
							if let data = d["data"] as? [AnyObject] {
								job.time("Presto fetch", items: data.count, itemType: "row") {
									var templateRow: [Value] = []
									for row in data {
										if let rowArray = row as? [AnyObject] {
											for cell in rowArray {
												if let value = cell as? NSNumber {
													templateRow.append(Value(value.doubleValue))
												}
												else if let value = cell as? String {
													templateRow.append(Value(value))
												}
												else if cell is NSNull {
													templateRow.append(Value.empty)
												}
												else {
													templateRow.append(Value.invalid)
												}
											}
										}
										self.buffer.append(templateRow)
										templateRow.removeAll(keepingCapacity: true)
									}
								}
							}

							return callback(.success())
						}
						else {
							self.nextURI = nil
							self.stopped = true
							return callback(.failure("returned response has an invalid format"))
						}
					}
					else {
						if response.response?.statusCode == 503 {
							// Status code 503 means that we should wait a bit
							job.log("Presto returned status code 503, waiting for a while")
							let queue = DispatchQueue.global(qos: .userInitiated)
							queue.asyncAfter(deadline: DispatchTime.now() + 0.1) {
								callback(.success())
							}
							return
						}
						else {
							self.mutex.locked {
								// Any status code other than 200 means trouble
								self.stopped = true
								self.nextURI = nil
							}
							let ss = response.response?.statusCode ?? 0
							let ld = response.result.error?.localizedDescription ?? ""
							return callback(.failure("Presto error \(ss): \(ld))"))
						}
					}
				})
			}
		}
	}
	
	private func awaitColumns(_ job: Job, callback: @escaping (Fallible<()>) -> ()) {
		request(job) { result in
			switch result {
			case .success():
				if self.columns == nil && !self.stopped {
					job.async {
						self.awaitColumns(job, callback: callback)
					}
				}
				else {
					callback(.success())
				}
			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
	
	func fetch(_ job: Job, consumer: @escaping Sink) {
		request(job) { result in
			switch result {
			case .success():
				let (rows, stopped) = self.mutex.locked { () -> ([Tuple], Bool) in
					let rows = self.buffer
					self.buffer.removeAll(keepingCapacity: true)
					return (rows, self.stopped)
				}
				consumer(.success(Array(rows)), stopped ? .finished : .hasMore)

			case .failure(let e):
				consumer(.failure(e), .finished)
			}
		}
	}
	
	func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		let s = self
		self.columnsFuture.get(job) { result in
			// The mutex locking is just here to keep 'self' alive while columns are being fetched.
			s.mutex.locked {
				callback(result)
			}
		}
	}
	
	func clone() -> WarpCore.Stream {
		return QBEPrestoStream(url: self.url, sql: self.sql, catalog: self.catalog, schema: self.schema)
	}
}

private class QBEPrestoDatabase {
	let url: URL
	let schema: String
	let catalog: String
	let dialect: SQLDialect = QBEPrestoSQLDialect()
	
	init(url: URL, catalog: String, schema: String) {
		self.url = url
		self.catalog = catalog
		self.schema = schema
	}
	
	func query(_ sql: String) -> QBEPrestoStream {
		return QBEPrestoStream(url: url, sql: sql, catalog: catalog, schema: schema)
	}

	func run(_ sql: [String], job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		var sql = sql
		let mutex = Mutex() // To protect the list of queryes

		// TODO check for memory leaks
		var consume: (() -> ())? = nil
		consume = { () -> () in
			mutex.locked {
				let q = sql.removeFirst()
				let stream = self.query(q)
				stream.fetch(job) { (res, _) -> () in
					mutex.locked {
						if case .failure(let e) = res {
							callback(.failure(e))
						}
						else {
							job.async {
								consume?()
							}
						}
					}
				}
			}
		}

		consume!()
	}

	var tableNames: [String]? { get {
		return []
	} }
}

private class QBEPrestoDataset: SQLDataset {
	private let db: QBEPrestoDatabase
	
	class func tableDataset(_ job: Job, db: QBEPrestoDatabase, tableName: String, callback: @escaping (Fallible<QBEPrestoDataset>) -> ()) {
		let sql = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		
		db.query(sql).columns(job) { (columns) -> () in
			callback(columns.use({return QBEPrestoDataset(db: db, fragment: SQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: $0)}))
		}
	}
	
	init(db: QBEPrestoDatabase, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return QBEPrestoDataset(db: self.db, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> WarpCore.Stream {
		return db.query(self.sql.sqlSelect(nil).sql)
	}
}

class QBEPrestoSourceStep: QBEStep {
	var catalogName: String = "default" { didSet { switchDatabase() } }
	var schemaName: String = "default" { didSet { switchDatabase() } }
	var tableName: String = "default" { didSet { switchDatabase() } }
	var url: String = "http://localhost:8080" { didSet { switchDatabase() } }
	
	private var db: QBEPrestoDatabase?

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
		self.catalogName = (aDecoder.decodeObject(forKey: "catalogName") as? String) ?? self.catalogName
		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? self.tableName
		self.schemaName = (aDecoder.decodeObject(forKey: "schemaName") as? String) ?? self.schemaName
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
				db = QBEPrestoDatabase(url: url, catalog: catalogName, schema: schemaName)
			}
		}
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let d = db, !self.tableName.isEmpty {
			QBEPrestoDataset.tableDataset(job, db: d, tableName: tableName, callback: { (fd) -> () in
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
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}
}
