import Foundation

private let SQLITE_TRANSIENT = sqlite3_destructor_type(COpaquePointer(bitPattern:-1))

internal class QBESQLiteResult {
	let resultSet: COpaquePointer
	let db: QBESQLiteDatabase
	
	init(resultSet: COpaquePointer, db: QBESQLiteDatabase) {
		self.resultSet = resultSet
		self.db = db
	}
	
	init?(sql: String, db: QBESQLiteDatabase) {
		self.db = db
		self.resultSet = nil
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
	func run(parameters: [QBEValue]? = nil) -> Bool {
		// If there are parameters, bind them
		var ret = true
		
		dispatch_sync(QBESQLiteDatabase.sharedQueue) {
			if let p = parameters {
				var i = 0
				for value in p {
					var result = SQLITE_OK
					switch value {
						case .StringValue(let s):
							// This, apparently, is super-slow, because Swift needs to convert its string to UTF-8.
							result = sqlite3_bind_text(self.resultSet, CInt(i+1), s, -1, SQLITE_TRANSIENT)
						
						case .IntValue(let x):
							result = sqlite3_bind_int64(self.resultSet, CInt(i+1), sqlite3_int64(x))
						
						case .DoubleValue(let d):
							result = sqlite3_bind_double(self.resultSet, CInt(i+1), d)
						
						case .BoolValue(let b):
							result = sqlite3_bind_int(self.resultSet, CInt(i+1), b ? 1 : 0)
						
						case .InvalidValue:
							result = sqlite3_bind_null(self.resultSet, CInt(i+1))
						
						case .EmptyValue:
							result = sqlite3_bind_null(self.resultSet, CInt(i+1))
					}
					
					if result != SQLITE_OK {
						println("SQLite error on parameter bind: \(self.db.lastError)")
						ret = false
					}
					
					i++
				}
			}
		
			let result = sqlite3_step(self.resultSet)
			if result != SQLITE_ROW && result != SQLITE_DONE {
				println("SQLite error running statement: \(self.db.lastError)")
				ret = false
			}
			
			if sqlite3_clear_bindings(self.resultSet) != SQLITE_OK {
				println("SQLite: failed to clear parameter bindings: \(self.db.lastError)")
				ret = false
			}
			
			if sqlite3_reset(self.resultSet) != SQLITE_OK {
				println("SQLite: could not reset statement: \(self.db.lastError)")
				ret = false
			}
		}
		return ret
	}
	
	var columnCount: Int { get {
		return Int(sqlite3_column_count(resultSet))
	} }
	
	 var columnNames: [QBEColumn] { get {
		let count = sqlite3_column_count(resultSet)
		return (0..<count).map({QBEColumn(String.fromCString(sqlite3_column_name(self.resultSet, $0))!)})
	} }

	func sequence(locale: QBELocale?) -> SequenceOf<QBERow> {
		return SequenceOf<QBERow>(QBESQLiteResultSequence(result: self, locale: locale))
	}
}

internal class QBESQLiteResultSequence: SequenceType {
	let result: QBESQLiteResult
	let locale: QBELocale?
	typealias Generator = QBESQLiteResultGenerator
	
	init(result: QBESQLiteResult, locale: QBELocale?) {
		self.locale = locale
		self.result = result
	}
	
	func generate() -> Generator {
		return QBESQLiteResultGenerator(self.result, locale: self.locale)
	}
}

internal class QBESQLiteResultGenerator: GeneratorType {
	typealias Element = [QBEValue]
	let result: QBESQLiteResult
	var lastStatus: Int32 = SQLITE_OK
	var locale: QBELocale?
	
	init(_ result: QBESQLiteResult, locale: QBELocale?) {
		self.result = result
		self.locale = locale
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
				let string = (String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx))))!)
				if let l = self.locale {
					return l.valueForLocalString(string)
				}
				return QBEValue(string)
				
			default:
				return QBEValue.InvalidValue
			}
		}
	}
}

internal class QBESQLiteDatabase: QBESQLDatabase {
	class var sharedQueue : dispatch_queue_t {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : dispatch_queue_t? = nil
		}
		dispatch_once(&Static.onceToken) {
			Static.instance = dispatch_queue_create("QBESQLiteDatabase.Queue", DISPATCH_QUEUE_SERIAL)
			dispatch_set_target_queue(Static.instance, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
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
		super.init(dialect: QBESQLiteDialect())
		
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
			for name in names.sequence(nil) {
				nameStrings.append(name[0].stringValue!)
			}
			return nameStrings
		}
		return nil
	} }
}

internal class QBESQLiteDialect: QBEStandardSQLDialect {
	override func binaryToSQL(type: QBEBinary, first: String, second: String) -> String? {
		switch type {
			/** For 'contains string', the default implementation uses "a LIKE '%b%'" syntax. Using INSTR is probably a
			bit faster on SQLite. **/
			case .ContainsString: return "INSTR(LOWER(\(second)), LOWER(\(first)))>0"
			case .ContainsStringStrict: return "INSTR(\(second), \(first))>0"
			
			// FIXME: REGEXP can be supported using a UDF in SQLite; see https://www.sqlite.org/lang_expr.html
			case .MatchesRegex: return nil
			case .MatchesRegexStrict: return nil
			default:
				return super.binaryToSQL(type, first: first, second: second)
		}
	}
	
	override func aggregationToSQL(aggregation: QBEAggregation) -> String? {
		// QBEFunction.Count only counts numeric values
		if aggregation.reduce == QBEFunction.Count {
			if let expressionSQL = self.expressionToSQL(aggregation.map) {
				return "SUM(CASE WHEN TYPEOF(\(expressionSQL)) IN('integer', 'real')) THEN 1 ELSE 0 END)"
			}
			return nil
		}
		
		return super.aggregationToSQL(aggregation)
	}
}

class QBESQLiteData: QBESQLData {
	private let db: QBESQLiteDatabase
	private let locale: QBELocale?

	private convenience init(db: QBESQLiteDatabase, tableName: String, locale: QBELocale?) {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName))"
		let result = db.query(query)
		
		self.init(db: db, sql: query, columns: result?.columnNames ?? [], locale: locale)
	}
	
	private init(db: QBESQLiteDatabase, sql: String, columns: [QBEColumn], locale: QBELocale?) {
		self.db = db
		self.locale = locale
		super.init(sql: sql, dialect: db.dialect, columns: columns)
	}
	
	override func apply(sql: String, resultingColumns: [QBEColumn]) -> QBEData {
		return QBESQLiteData(db: self.db, sql: sql, columns: resultingColumns, locale: locale)
	}
	
	override func stream() -> QBEStream {
		if let result = self.db.query(self.sql) {
			return QBESequenceStream(SequenceOf<QBERow>(result.sequence(locale)), columnNames: result.columnNames)
		}
		return QBEEmptyStream()
	}
}

class QBESQLiteCachedData: QBEProxyData {
	private let database: QBESQLiteDatabase
	private let tableName: String
	private var stream: QBEStream?
	private var insertStatement: QBESQLiteResult?
	private(set) var isCached: Bool = false
	private let locale: QBELocale?
	let cacheJob: QBEJob
	
	init(source: QBEData, locale: QBELocale?) {
		database = QBESQLiteDatabase(path: "", readOnly: false)!
		tableName = "cache"
		self.locale = locale
		cacheJob = QBEJob()
		super.init(data: source)
		
		let dialect = database.dialect
		
		// Create a table to cache this dataset
		QBEAsyncBackground {
			source.columnNames { (columns) -> () in
				let columnSpec = columns.map({(column) -> String in
					let colString = dialect.columnIdentifier(column)
					return "\(colString) VARCHAR"
				}).implode(", ")!
				
				let sql = "CREATE TABLE \(dialect.tableIdentifier(self.tableName)) (\(columnSpec))"
				if let q = self.database.query(sql) {
					q.run()
					
					self.stream = source.stream()
					
					// We do not need to wait for this cached data to be written to disk
					let dialect = self.database.dialect
					self.database.query("PRAGMA synchronous = OFF")?.run()
					self.database.query("PRAGMA journal_mode = MEMORY")?.run()
					self.database.query("BEGIN TRANSACTION")?.run()
					
					// Prepare the insert-statement
					let values = columns.map({(m) -> String in return "?"}).implode(",") ?? ""
					self.insertStatement = self.database.query("INSERT INTO \(dialect.tableIdentifier(self.tableName)) VALUES (\(values))")
					
					self.stream?.fetch(self.ingest, job: self.cacheJob)
				}
			}
		}
	}
	
	deinit {
		cacheJob.cancel()
	}
	
	private func ingest(rows: ArraySlice<QBERow>, hasMore: Bool) {
		assert(!isCached, "Cannot ingest more rows after data has already been cached")
		if hasMore && !cacheJob.cancelled {
			self.stream?.fetch(self.ingest, job: cacheJob)
		}
		
		QBETime("SQLite insert", rows.count, "rows") {
			if let statement = self.insertStatement {
				for row in rows {
					statement.run(parameters: row)
				}
			}
		}
		
		if !hasMore {
			// Swap out the original source with our new cached source
			println("Done caching, swapping out")
			self.database.query("END TRANSACTION")?.run()
			self.data.columnNames({ (columns) -> () in
				let sql = "SELECT * FROM \(self.database.dialect.tableIdentifier(self.tableName))"
				self.data = QBESQLiteData(db: self.database, sql: sql, columns: columns, locale: self.locale)
				self.isCached = true
			})
		}
	}
}

class QBESQLiteSourceStep: QBEStep {
	var file: QBEFileReference? { didSet {
		oldValue?.url?.stopAccessingSecurityScopedResource()
		file?.url?.startAccessingSecurityScopedResource()
		switchDatabase()
	} }
	
	var tableName: String?
	var db: QBESQLiteDatabase?
	
	init?(url: NSURL) {
		self.file = QBEFileReference.URL(url)
		super.init(previous: nil)
		switchDatabase()
	}
	
	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	private func switchDatabase() {
		self.db = nil
		self.tableName = nil
		
		if let url = file?.url {
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
			
			if let first = self.db?.tableNames?.first {
				self.tableName = first
			}
		}
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("SQLite table", comment: "")
		}
		
		return String(format: NSLocalizedString("Load table %@ from SQLite-database '%@'", comment: ""), self.tableName ?? "", self.file?.url?.lastPathComponent ?? "")
	}
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		if let d = db {
			callback(QBECoalescedData(QBESQLiteData(db: d, tableName: self.tableName ?? "", locale: QBEAppDelegate.sharedInstance.locale)))
		}
		else {
			callback(QBERasterData())
		}
	}
	
	override func exampleData(job: QBEJob?, callback: (QBEData) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.random(100))
		})
	}
	
	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? ""
		
		let u = aDecoder.decodeObjectForKey("fileURL") as? NSURL
		let b = aDecoder.decodeObjectForKey("fileBookmark") as? NSData
		self.file = QBEFileReference.create(u, b)
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(file?.url, forKey: "fileURL")
		coder.encodeObject(file?.bookmark, forKey: "fileBookmark")
		coder.encodeObject(tableName, forKey: "tableName")
	}
	
	override func willSaveToDocument(atURL: NSURL) {
		self.file = self.file?.bookmark(atURL)
	}
	
	override func didLoadFromDocument(atURL: NSURL) {
		self.file = self.file?.resolve(atURL)
		if let url = self.file?.url {
			url.startAccessingSecurityScopedResource()
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
		}
	}
}
