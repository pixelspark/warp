import Foundation
import Alamofire
import WarpCore

private class QBEPrestoSQLDialect: StandardSQLDialect {
	override func unaryToSQL(type: Function, var args: [String]) -> String? {
		switch type {
		case .Concat:
			/** Presto doesn't support CONCAT'ing more than two arguments. Therefore, we need to nest them. */
			if args.count == 1 {
				return args.first!
			}
			if args.count > 1 {
				var sql = args.last
				args.removeLast()
				for a in Array(args.reverse()) {
					sql = "CONCAT(\(a), \(sql))"
				}
				return sql
			}
			return nil
			
		default:
			return super.unaryToSQL(type, args: args)
		}
	}
	
	private override func forceNumericExpression(expression: String) -> String {
		return "TRY_CAST(\(expression) AS DOUBLE)"
	}
	
	private override func forceStringExpression(expression: String) -> String {
		return "CAST(\(expression) AS VARCHAR)"
	}
}

private class QBEPrestoStream: NSObject, Stream {
	let url: NSURL
	let sql: String
	let catalog: String
	let schema: String
	
	private var buffer: [Tuple] = []
	private var columns: Fallible<[Column]>?
	private var stopped: Bool = false
	private var started: Bool = false
	private var nextURI: NSURL?
	private var columnsFuture: Future<Fallible<[Column]>>! = nil
	
	init(url: NSURL, sql: String, catalog: String, schema: String) {
		self.url = url
		self.sql = sql
		self.schema = schema
		self.catalog = catalog
		self.nextURI = self.url.URLByAppendingPathComponent("/v1/statement")
		super.init()
		
		let c = { [weak self] (job: Job, callback: (Fallible<[Column]>) -> ()) -> () in
			self?.awaitColumns(job) {
				callback(self?.columns ?? .Failure(NSLocalizedString("Could not load column names from Presto.", comment: "")))
			}
		}
		
		self.columnsFuture = Future<Fallible<[Column]>>(c)
	}
	
	/** Request the next batch of result data from Presto. */
	private func request(job: Job, callback: () -> ()) {
		if stopped {
			callback()
			return
		}
		
		if let endpoint = self.nextURI {
			let request = NSMutableURLRequest(URL: endpoint)
			request.setValue("Warp", forHTTPHeaderField: "User-Agent")
		
			if !started {
				// Initial request
				started = true
				request.HTTPMethod = "POST"
				request.setValue("Warp", forHTTPHeaderField: "X-Presto-User")
				request.setValue("Warp", forHTTPHeaderField: "X-Presto-Source")
				request.setValue(self.catalog, forHTTPHeaderField: "X-Presto-Catalog")
				request.setValue(self.schema, forHTTPHeaderField: "X-Presto-Schema")
				
				if let sqlData = sql.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false) {
					request.HTTPBody = sqlData
				}
			}
			else {
				// Follow-up request
				request.HTTPMethod = "GET"
			}
			
			job.log("Presto requesting \(endpoint)")
			Alamofire.request(request).responseJSON(options: [], completionHandler: { response in
				if response.result.isSuccess {
					// Let's see if the response got something useful
					if let d = response.result.value as? [String: AnyObject] {
						// Get progress data from response
						if let stats = d["stats"] as? [String: AnyObject] {
							if let completedSplits = stats["completedSplits"] as? Int,
								let queuedSplits = stats["queuedSplits"] as? Int {
									let progress = Double(completedSplits) / Double(completedSplits + queuedSplits)
									job.reportProgress(progress, forKey: self.hash)
							}
						}

						// Does the response tell us where to look next?
						if let nu = (d["nextUri"] as? String) {
							self.nextURI = NSURL(string: nu)
						}
						else {
							self.nextURI = nil
							self.stopped = true
						}

						// Does the response include column information?
						if self.columns == nil {
							if let columns = d["columns"] as? [AnyObject] {
								var newColumns: [Column] = []

								for columnSpec in columns {
									if let columnInfo = columnSpec as? [String: AnyObject] {
										if let name = columnInfo["name"] as? String {
											newColumns.append(Column(name))
										}
									}
								}
								self.columns = .Success(newColumns)
							}
						}

						// Does the response contain any data?
						if let data = d["data"] as? [AnyObject] {
							job.time("Fetch Presto", items: data.count, itemType: "row") {
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
												templateRow.append(Value.EmptyValue)
											}
											else {
												templateRow.append(Value.InvalidValue)
											}
										}
									}
									self.buffer.append(templateRow)
									templateRow.removeAll(keepCapacity: true)
								}
							}
						}
					}
					else {
						self.nextURI = nil
						self.stopped = true
					}
				}
				else {
					if response.response?.statusCode == 503 {
						// Status code 503 means that we should wait a bit
						let queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(100 * NSEC_PER_MSEC)), queue) {
							callback()
						}
						return
					}
					else {
						// Any status code other than 200 means trouble
						job.log("Presto errored: \(response.response?.statusCode) \(response.result.error)")
						self.stopped = true
						self.nextURI = nil
						callback()
						return
					}
				}
			})
		}
	}
	
	private func awaitColumns(job: Job, callback: () -> ()) {
		request(job) {
			if self.columns == nil && !self.stopped {
				job.async {
					self.awaitColumns(job, callback: callback)
				}
			}
			else {
				callback()
			}
		}
	}
	
	func fetch(job: Job, consumer: Sink) {
		request(job) {
			let rows = self.buffer
			self.buffer.removeAll(keepCapacity: true)
			consumer(.Success(Array(rows)), self.stopped ? .Finished : .HasMore)
		}
	}
	
	func columns(job: Job, callback: (Fallible<[Column]>) -> ()) {
		self.columnsFuture.get(job, callback)
	}
	
	func clone() -> Stream {
		return QBEPrestoStream(url: self.url, sql: self.sql, catalog: self.catalog, schema: self.schema)
	}
}

private class QBEPrestoDatabase {
	let url: NSURL
	let schema: String
	let catalog: String
	let dialect: SQLDialect = QBEPrestoSQLDialect()
	
	init(url: NSURL, catalog: String, schema: String) {
		self.url = url
		self.catalog = catalog
		self.schema = schema
	}
	
	func query(sql: String) -> QBEPrestoStream {
		return QBEPrestoStream(url: url, sql: sql, catalog: catalog, schema: schema)
	}

	func run(var sql: [String], job: Job, callback: (Fallible<Void>) -> ()) {
		let mutex = Mutex() // To protect the list of queryes

		// TODO check for memory leaks
		var consume: (() -> ())? = nil
		consume = { () -> () in
			mutex.locked {
				let q = sql.removeFirst()
				let stream = self.query(q)
				stream.fetch(job) { (res, _) -> () in
					mutex.locked {
						if case .Failure(let e) = res {
							callback(.Failure(e))
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

private class QBEPrestoData: SQLData {
	private let db: QBEPrestoDatabase
	
	class func tableData(job: Job, db: QBEPrestoDatabase, tableName: String, callback: (Fallible<QBEPrestoData>) -> ()) {
		let sql = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		
		db.query(sql).columns(job) { (columns) -> () in
			callback(columns.use({return QBEPrestoData(db: db, fragment: SQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: $0)}))
		}
	}
	
	init(db: QBEPrestoDatabase, fragment: SQLFragment, columns: [Column]) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(fragment: SQLFragment, resultingColumns: [Column]) -> Data {
		return QBEPrestoData(db: self.db, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> Stream {
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
		self.catalogName = (aDecoder.decodeObjectForKey("catalogName") as? String) ?? self.catalogName
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? self.tableName
		self.schemaName = (aDecoder.decodeObjectForKey("schemaName") as? String) ?? self.schemaName
		self.url = (aDecoder.decodeObjectForKey("url") as? String) ?? self.url
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.url, forKey: "url")
		coder.encodeObject(self.catalogName, forKey: "catalog")
		coder.encodeObject(self.schemaName, forKey: "schema")
		coder.encodeObject(self.tableName, forKey: "table")
		super.encodeWithCoder(coder)
	}
	
	private func explanation(locale: Locale) -> String {
		return String(format: NSLocalizedString("Table '%@' from Presto server",comment: ""), tableName)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		// TODO make an interactive sentence
		return QBESentence([QBESentenceText(self.explanation(locale))])
	}
	
	private func switchDatabase() {
		self.db = nil
		
		if !self.url.isEmpty {
			if let url = NSURL(string: self.url) {
				db = QBEPrestoDatabase(url: url, catalog: catalogName, schema: schemaName)
			}
		}
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let d = db where !self.tableName.isEmpty {
			QBEPrestoData.tableData(job, db: d, tableName: tableName, callback: { (fd) -> () in
				callback(fd.use({return $0}))
			})
		}
		else {
			callback(.Failure(NSLocalizedString("No database and/or table name have been set.", comment: "")))
		}
	}
	
	func catalogNames(job: Job, callback: (Fallible<Set<String>>) -> ()) {
		if let d = db {
			StreamData(source: d.query("SHOW CATALOGS")).unique(Sibling(columnName: Column("Catalog")), job: job) { (catalogNamesFallible) -> () in
				callback(catalogNamesFallible.use({(tn) -> (Set<String>) in return Set(tn.map({return $0.stringValue ?? ""})) }))
			}
		}
		else {
			callback(.Failure(NSLocalizedString("No database and/or table name have been set.", comment: "")))
		}
	}
	
	func schemaNames(job: Job, callback: (Fallible<Set<String>>) -> ()) {
		if let stream = db?.query("SHOW SCHEMAS") {
			StreamData(source: stream).unique(Sibling(columnName: Column("Schema")), job: job, callback: { (schemaNamesFallible) -> () in
				callback(schemaNamesFallible.use({(sn) in Set(sn.map({return $0.stringValue ?? ""})) }))
			})
		}
	}
	
	func tableNames(job: Job, callback: (Fallible<Set<String>>) -> ()) {
		if let stream = db?.query("SHOW TABLES") {
			StreamData(source: stream).unique(Sibling(columnName: Column("Table")), job: job, callback: { (tableNamesFallible) -> () in
				callback(tableNamesFallible.use({(tn) in Set(tn.map({return $0.stringValue ?? ""})) }))
			})
		}
	}
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}
}
