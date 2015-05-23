import Foundation
import Alamofire

private class QBEPrestoSQLDialect: QBEStandardSQLDialect {
	override func unaryToSQL(type: QBEFunction, var args: [String]) -> String? {
		switch type {
		case .Concat:
			/** Presto doesn't support CONCAT'ing more than two arguments. Therefore, we need to nest them. **/
			if args.count == 1 {
				return args.first!
			}
			if args.count > 1 {
				var sql = args.last
				args.removeLast()
				for a in reverse(args) {
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

private class QBEPrestoStream: NSObject, QBEStream {
	let url: NSURL
	let sql: String
	let catalog: String
	let schema: String
	
	private var buffer: [QBETuple] = []
	private var columns: [QBEColumn]?
	private var stopped: Bool = false
	private var started: Bool = false
	private var nextURI: NSURL?
	private var columnsFuture: QBEFuture<[QBEColumn]>! = nil
	
	init(url: NSURL, sql: String, catalog: String, schema: String) {
		self.url = url
		self.sql = sql
		self.schema = schema
		self.catalog = catalog
		self.nextURI = self.url.URLByAppendingPathComponent("/v1/statement")
		super.init()
		
		let c = { [unowned self] (job: QBEJob, callback: ([QBEColumn]) -> ()) -> () in
			self.awaitColumns(job) {
				callback(self.columns ?? [])
			}
		}
		
		self.columnsFuture = QBEFuture<[QBEColumn]>(c)
	}
	
	/** Request the next batch of result data from Presto. **/
	private func request(job: QBEJob, callback: () -> ()) {
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
			
			QBELog("Presto requesting \(endpoint)")
			Alamofire.request(request).responseJSON(options: NSJSONReadingOptions.allZeros, completionHandler: { (request, response, data, error) -> Void in
				if let res = response {
					// Status code 503 means that we should wait a bit
					if res.statusCode == 503 {
						let queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(100 * NSEC_PER_MSEC)), queue) {
							callback()
						}
						return
					}
					
					// Any status code other than 200 means trouble
					if res.statusCode != 200 {
						QBELog("Presto errored: \(res.statusCode)")
						self.stopped = true
						return
					}
				
					if let e = error {
						QBELog("Presto request error: \(e)")
						self.stopped = true
						return
					}
					
					// Let's see if the response got something useful
					if let d = data as? [String: AnyObject] {
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
								self.columns = []
								
								for columnSpec in columns {
									if let columnInfo = columnSpec as? [String: AnyObject] {
										if let name = columnInfo["name"] as? String {
											self.columns!.append(QBEColumn(name))
										}
									}
								}
							}
						}
							
						// Does the response contain any data?
						if let data = d["data"] as? [AnyObject] {
							job.time("Fetch Presto", items: data.count, itemType: "row") {
								var templateRow: [QBEValue] = []
								for row in data {
									if let rowArray = row as? [AnyObject] {
										for cell in rowArray {
											if let value = cell as? NSNumber {
												templateRow.append(QBEValue(value.doubleValue))
											}
											else if let value = cell as? String {
												templateRow.append(QBEValue(value))
											}
											else if let value = cell as? NSNull {
												templateRow.append(QBEValue.EmptyValue)
											}
											else {
												templateRow.append(QBEValue.InvalidValue)
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
					self.stopped = true
					self.nextURI = nil
				}
				
				callback()
			})
		}
	}
	
	private func awaitColumns(job: QBEJob, callback: () -> ()) {
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
	
	func fetch(job: QBEJob, consumer: QBESink) {
		request(job) {
			let rows = self.buffer
			self.buffer.removeAll(keepCapacity: true)
			consumer(ArraySlice(rows), !self.stopped)
		}
	}
	
	func columnNames(job: QBEJob, callback: ([QBEColumn]) -> ()) {
		self.columnsFuture.get(callback)
	}
	
	func clone() -> QBEStream {
		return QBEPrestoStream(url: self.url, sql: self.sql, catalog: self.catalog, schema: self.schema)
	}
}

private class QBEPrestoDatabase: QBESQLDatabase {
	let url: NSURL
	let schema: String
	let catalog: String
	
	init(url: NSURL, catalog: String, schema: String) {
		self.url = url
		self.catalog = catalog
		self.schema = schema
		super.init(dialect: QBEPrestoSQLDialect())
	}
	
	func query(sql: String) -> QBEPrestoStream? {
		return QBEPrestoStream(url: url, sql: sql, catalog: catalog, schema: schema)
	}
	
	var tableNames: [String]? { get {
		return []
	} }
}

private class QBEPrestoData: QBESQLData {
	private let db: QBEPrestoDatabase
	
	class func tableData(job: QBEJob, db: QBEPrestoDatabase, tableName: String, callback: (QBEPrestoData?) -> ()) {
		let sql = "SELECT * FROM \(db.dialect.tableIdentifier(tableName))"
		
		if let result = db.query(sql) {
			result.columnNames(job) { (columns) -> () in
				callback(QBEPrestoData(db: db, fragment: QBESQLFragment(table: tableName, dialect: db.dialect), columns: columns))
			}
		}
		else {
			callback(nil)
		}
	}
	
	init(db: QBEPrestoDatabase, fragment: QBESQLFragment, columns: [QBEColumn]) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBEPrestoData(db: self.db, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> QBEStream {
		return db.query(self.sql.sqlSelect(nil).sql) ?? QBEEmptyStream()
	}
}

class QBEPrestoSourceStep: QBEStep {
	var catalogName: String? { didSet { switchDatabase() } }
	var schemaName: String? { didSet { switchDatabase() } }
	var tableName: String? { didSet { switchDatabase() } }
	var url: String? { didSet { switchDatabase() } }
	
	private var db: QBEPrestoDatabase?
	
	init(url: String? = nil) {
		self.url = url ?? "http://localhost:8080"
		self.catalogName = "default"
		self.schemaName = "default"
		super.init(previous: nil)
		switchDatabase()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.catalogName = (aDecoder.decodeObjectForKey("catalogName") as? String)
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String)
		self.schemaName = (aDecoder.decodeObjectForKey("schemaName") as? String)
		self.url = (aDecoder.decodeObjectForKey("url") as? String)
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.url, forKey: "url")
		coder.encodeObject(self.catalogName, forKey: "catalog")
		coder.encodeObject(self.schemaName, forKey: "schema")
		coder.encodeObject(self.tableName, forKey: "table")
		super.encodeWithCoder(coder)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Presto table", comment: "")
		}
		
		if let tn = tableName {
			return String(format: NSLocalizedString("Table '%@' from Presto server",comment: ""), tn)
		}
		
		return NSLocalizedString("Table from Presto server", comment: "")
	}
	
	private func switchDatabase() {
		self.db = nil
		
		if let urlString = self.url,
		   let url = NSURL(string: urlString),
		   let catalog = self.catalogName,
		   let schema = self.schemaName {
			db = QBEPrestoDatabase(url: url, catalog: catalog, schema: schema)
		}
	}
	
	override func fullData(job: QBEJob, callback: (QBEData) -> ()) {
		if let d = db, tableName = self.tableName {
			QBEPrestoData.tableData(job, db: d, tableName: tableName, callback: { (data) -> () in
				if let d = data {
					callback(d)
				}
				else {
					callback(QBERasterData())
				}
			})
		}
		else {
			callback(QBERasterData())
		}
	}
	
	func catalogNames(job: QBEJob, callback: (Set<String>) -> ()) {
		if let stream = db?.query("SHOW CATALOGS") {
			QBEStreamData(source: stream).unique(QBESiblingExpression(columnName: QBEColumn("Catalog")), job: job, callback: { (tableNames) -> () in
				let tableNameStrings = Set(map(tableNames, {return $0.stringValue ?? ""}))
				callback(tableNameStrings)
			})
		}
	}
	
	func schemaNames(job: QBEJob, callback: (Set<String>) -> ()) {
		if let stream = db?.query("SHOW SCHEMAS") {
			QBEStreamData(source: stream).unique(QBESiblingExpression(columnName: QBEColumn("Schema")), job: job, callback: { (tableNames) -> () in
				let tableNameStrings = Set(map(tableNames, {return $0.stringValue ?? ""}))
				callback(tableNameStrings)
			})
		}
	}
	
	func tableNames(job: QBEJob, callback: (Set<String>) -> ()) {
		if let stream = db?.query("SHOW TABLES") {
			QBEStreamData(source: stream).unique(QBESiblingExpression(columnName: QBEColumn("Table")), job: job, callback: { (tableNames) -> () in
				let tableNameStrings = Set(map(tableNames, {return $0.stringValue ?? ""}))
				callback(tableNameStrings)
			})
		}
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.random(maxInputRows))
		})
	}
}
