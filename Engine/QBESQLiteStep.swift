import Foundation

private let SQLITE_TRANSIENT = sqlite3_destructor_type(COpaquePointer(bitPattern:-1))

internal class QBESQLiteResult: NSObject {
	let resultSet: COpaquePointer
	let db: QBESQLiteDatabase
	
	init(resultSet: COpaquePointer, db: QBESQLiteDatabase) {
		self.resultSet = resultSet
		self.db = db
	}
	
	init?(sql: String, db: QBESQLiteDatabase) {
		self.db = db
		self.resultSet = nil
		super.init()
		println("SQL \(sql)")
		if !self.db.perform({sqlite3_prepare_v2(self.db.db, sql, -1, &self.resultSet, nil)}) {
			return nil
		}
	}
	
	deinit {
		sqlite3_finalize(resultSet)
	}
	
	/** Run is used to execute statements that do not return data (e.g. UPDATE, INSERT, DELETE, etc.). It can optionally
	be fed with parameters which will be bound before query execution. **/
	func run(parameters: [QBEValue]? = nil) {
		// If there are parameters, bind them
		if let p = parameters {
			for i in 0..<p.count {
				let value = p[i]
				
				switch value {
					case .StringValue(let s):
						self.db.perform({sqlite3_bind_text(self.resultSet, CInt(i+1), s, -1, SQLITE_TRANSIENT)})
					
					case .IntValue(let x):
						self.db.perform({sqlite3_bind_int64(self.resultSet, CInt(i+1), sqlite3_int64(x))})
					
					case .DoubleValue(let d):
						self.db.perform({sqlite3_bind_double(self.resultSet, CInt(i+1), d)})
					
					case .BoolValue(let b):
						self.db.perform({sqlite3_bind_int(self.resultSet, CInt(i+1), b ? 1 : 0)})
					
					case .InvalidValue:
						self.db.perform({sqlite3_bind_null(self.resultSet, CInt(i+1))})
					
					case .EmptyValue:
						self.db.perform({sqlite3_bind_null(self.resultSet, CInt(i+1))})
				}
			}
		}

		self.db.perform({sqlite3_step(self.resultSet)})
		self.db.perform({sqlite3_clear_bindings(self.resultSet)})
		self.db.perform({sqlite3_reset(self.resultSet)})
	}
	
	var columnCount: Int { get {
		return Int(sqlite3_column_count(resultSet))
	} }
	
	 var columnNames: [QBEColumn] { get {
		let count = sqlite3_column_count(resultSet)
		return (0..<count).map({QBEColumn(String.fromCString(sqlite3_column_name(self.resultSet, $0))!)})
	} }
}

extension QBESQLiteResult: SequenceType {
	typealias Generator = QBESQLiteResultGenerator
	
	func generate() -> Generator {
		return QBESQLiteResultGenerator(self)
	}
}

internal class QBESQLiteResultGenerator: GeneratorType {
	typealias Element = [QBEValue]
	let result: QBESQLiteResult
	var lastStatus: Int32 = SQLITE_OK
	
	init(_ result: QBESQLiteResult) {
		(self.result) = result
	}
	
	func next() -> Element? {
		if lastStatus == SQLITE_DONE {
			return nil
		}
		
		var item: Element? = nil
		
		self.result.db.perform({
			self.lastStatus = sqlite3_step(self.result.resultSet)
			if self.lastStatus == SQLITE_ROW {
				item = self.row
				return SQLITE_OK
			}
			else if self.lastStatus == SQLITE_DONE {
				return SQLITE_OK
			}
			else {
				return self.lastStatus
			}
		})
		
		return item
	}
	
	var row: Element? {
		return (0..<result.columnNames.count).map { idx in
			switch sqlite3_column_type(self.result.resultSet, Int32(idx)) {
			case SQLITE_FLOAT:
				return QBEValue(sqlite3_column_double(self.result.resultSet, Int32(idx)))
				
			case SQLITE_NULL:
				return QBEValue.EmptyValue
				
			case SQLITE_INTEGER:
				// Booleans are represented as integers, but boolean columns are declared as BOOL columns
				let intValue = Int(sqlite3_column_int64(self.result.resultSet, Int32(idx)))
				var bool = false
				if let type = String.fromCString(sqlite3_column_decltype(self.result.resultSet, Int32(idx))) {
					if type.hasPrefix("BOOL") {
						return QBEValue(intValue != 0)
					}
				}
				return QBEValue(intValue)
				
			case SQLITE_TEXT:
				return QBEValue(String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx))))!)
				
			default:
				return QBEValue.InvalidValue
			}
		}
	}
}

internal class QBESQLiteDatabase {
	class var sharedQueue : dispatch_queue_t {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : dispatch_queue_t? = nil
		}
		dispatch_once(&Static.onceToken) {
			Static.instance = dispatch_queue_create("QBESQLiteDatabase.Queue", DISPATCH_QUEUE_SERIAL)
		}
		return Static.instance!
	}
	
	let db: COpaquePointer
	
	private var lastError: String {
		 return String.fromCString(sqlite3_errmsg(self.db)) ?? ""
	}
	
	private func perform(op: () -> Int32) -> Bool {
		var ret: Bool = true
		dispatch_sync(QBESQLiteDatabase.sharedQueue) {
			let code = op()
			if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW {
				println("SQLite error: \(self.lastError)")
				ret = false
			}
		}
		return ret
	}
	
	init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		
		if !perform({sqlite3_open_v2(path, &self.db, flags, nil) }) {
			return nil
		}
		
		/* By default, SQLite does not implement various mathematical SQL functions such as SIN, COS, TAN, as well as 
		certain aggregates such as STDEV. RegisterExtensionFunctions plugs these into the database. */
		RegisterExtensionFunctions(self.db)
	}
	
	deinit {
		perform({sqlite3_close(self.db)})
	}
	
	func query(sql: String) -> QBESQLiteResult? {
		return QBESQLiteResult(sql: sql, db: self)
	}
	
	var tableNames: [String]? { get {
		if let names = query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC") {
			var nameStrings: [String] = []
			for name in names {
				nameStrings.append(name[0].stringValue!)
			}
			return nameStrings
		}
		return nil
	} }
}

private class QBESQLiteDialect: QBEStandardSQLDialect {
}

private class QBESQLiteStream: NSObject, QBEStream {
	let data: QBESQLiteData
	let result: QBESQLiteResult?
	let generator: QBESQLiteResultGenerator?
	
	init(data: QBESQLiteData) {
		self.data = data
		result = data.db.query(data.sql)
		generator = result?.generate()
	}
	
	private func fetch(consumer: QBESink, job: QBEJob?) {
		if let g = generator {
			var done = false
			var rows :[QBERow] = []
			rows.reserveCapacity(QBEStreamDefaultBatchSize)
			
			for i in 0..<QBEStreamDefaultBatchSize {
				if let next = g.next() {
					rows.append(next)
				}
				else {
					done = true
					break
				}
			}
			
			consumer(Slice(rows), !done)
		}
		else {
			consumer([], false)
		}
	}
	
	private func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(result?.columnNames ?? [])
	}
	
	private func clone() -> QBEStream {
		return QBESQLiteStream(data: self.data)
	}
}

class QBESQLiteData: QBESQLData {
	private let db: QBESQLiteDatabase

	private convenience init(db: QBESQLiteDatabase, tableName: String) {
		let dialect = QBESQLiteDialect()
		let query = "SELECT * FROM \(dialect.tableIdentifier(tableName))"
		let result = db.query(query)
		self.init(db: db, sql: query, columns: result?.columnNames ?? [])
	}
	
	private init(db: QBESQLiteDatabase, sql: String, columns: [QBEColumn]) {
		(self.db) = (db)
		super.init(sql: sql, dialect: QBESQLiteDialect(), columns: columns)
	}
	
	override func columnNames(callback: ([QBEColumn]) -> ()) {
		if let result = self.db.query(self.sql) {
			callback(result.columnNames)
		}
		else {
			callback([])
		}
	}
	
	override func apply(sql: String, resultingColumns: [QBEColumn]) -> QBEData {
		return QBESQLiteData(db: self.db, sql: sql, columns: resultingColumns)
	}
	
	override func stream() -> QBEStream? {
		return QBESQLiteStream(data: self)
	}
	
	override func raster(callback: (QBERaster) -> (), job: QBEJob?) {
		if let result = self.db.query(self.sql) {
			let columnNames = result.columnNames
			var newRaster: [[QBEValue]] = []
			for row in result {
				newRaster.append(row)
			}
			callback(QBERaster(data: newRaster, columnNames: columnNames))
		}
		else {
			callback(QBERaster())
		}
	}
}

class QBESQLiteCachedData: QBEProxyData {
	private let database: QBESQLiteDatabase
	private let tableName: String
	private var stream: QBEStream?
	
	init(source: QBEData) {
		database = QBESQLiteDatabase(path: "", readOnly: false)!
		tableName = "cache"
		super.init(data: source)
		
		// Create a table to cache this dataset
		QBEAsyncBackground {
			source.columnNames { (columns) -> () in
				let columnSpec = columns.map({(column) -> String in
					let colString = QBESQLiteDialect().columnIdentifier(column)
					return "\(colString) VARCHAR"
				}).implode(", ")!
				
				let sql = "CREATE TABLE \(self.tableName) (\(columnSpec))"
				self.database.query(sql)!.run()
				self.stream = source.stream()
				
				// We do not need to wait for this cached data to be written to disk
				self.database.query("PRAGMA synchronous = OFF")?.run()
				self.database.query("PRAGMA journal_mode = MEMORY")?.run()
				self.database.query("BEGIN TRANSACTION")?.run()
				self.stream?.fetch(self.ingest, job: nil)
			}
		}
	}
	
	private func ingest(rows: Slice<QBERow>, hasMore: Bool) {
		self.data.columnNames({ (columns) -> () in
			QBETime("SQLite insert", rows.count, "rows") {
				let values = columns.map({(m) -> String in return "?"}).implode(",") ?? ""
				if let statement = self.database.query("INSERT INTO \(self.tableName) VALUES (\(values))") {
					for row in rows {
						statement.run(parameters: row)
					}
				}
			}
			
			if hasMore {
				self.stream?.fetch(self.ingest, job: nil)
			}
			else {
				// Swap out the original source with our new cached source
				println("Done caching, swapping out")
				self.database.query("END TRANSACTION")?.run()
				let sql = "SELECT * FROM \(self.tableName)"
				self.data = QBESQLiteData(db: self.database, sql: sql, columns: columns)
			}
		})
	}
}

class QBESQLiteSourceStep: QBEStep {
	var url: String
	var tableName: String?
	let db: QBESQLiteDatabase?
	
	init?(url: NSURL) {
		self.url = url.absoluteString ?? ""
		
		if let nsu = NSURL(string: self.url) {
			self.db = QBESQLiteDatabase(path: nsu.path!, readOnly: true)
			if let first = self.db?.tableNames?.first {
				self.tableName = first
			}
			else {
				self.tableName = nil
			}
			super.init(previous: nil)
		}
		else {
			self.db = nil
			self.tableName = nil
			super.init(previous: nil)
			return nil
		}
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("SQLite table", comment: "")
		}
		
		return String(format: NSLocalizedString("Load table %@ from SQLite-database '%@'", comment: ""), self.tableName ?? "", url)
	}
	
	override func fullData(callback: (QBEData) -> (), job: QBEJob?) {
		if let d = db {
			callback(QBESQLiteData(db: d, tableName: self.tableName ?? ""))
		}
		else {
			callback(QBERasterData())
		}
	}
	
	override func exampleData(callback: (QBEData) -> (), job: QBEJob?) {
		self.fullData({ (fd) -> () in
			callback(fd.random(100))
		}, job: job)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.url = (aDecoder.decodeObjectForKey("url") as? String) ?? ""
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? ""
		
		if let url = NSURL(string: self.url) {
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
		}
		else {
			self.db = nil
		}
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(url, forKey: "url")
		coder.encodeObject(tableName, forKey: "tableName")
	}
}
