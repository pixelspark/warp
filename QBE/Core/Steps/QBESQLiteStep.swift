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
		QBELog("SQL \(sql)")
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
		
		dispatch_sync(self.db.queue) {
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
						QBELog("SQLite error on parameter bind: \(self.db.lastError)")
						ret = false
					}
					
					i++
				}
			}
		
			let result = sqlite3_step(self.resultSet)
			if result != SQLITE_ROW && result != SQLITE_DONE {
				QBELog("SQLite error running statement: \(self.db.lastError)")
				ret = false
			}
			
			if sqlite3_clear_bindings(self.resultSet) != SQLITE_OK {
				QBELog("SQLite: failed to clear parameter bindings: \(self.db.lastError)")
				ret = false
			}
			
			if sqlite3_reset(self.resultSet) != SQLITE_OK {
				QBELog("SQLite: could not reset statement: \(self.db.lastError)")
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

	func sequence(locale: QBELocale?) -> SequenceOf<QBETuple> {
		return SequenceOf<QBETuple>(QBESQLiteResultSequence(result: self, locale: locale))
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
	typealias Element = QBETuple
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
				if let string = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx)))) {
					if let l = self.locale {
						return l.valueForLocalString(string)
					}
					return QBEValue(string)
				}
				else {
					return QBEValue.InvalidValue
				}
				
			default:
				return QBEValue.InvalidValue
			}
		}
	}
}

internal class QBESQLiteDatabase: QBESQLDatabase {
	internal var url: String?
	let db: COpaquePointer
	
	private class var sharedQueue : dispatch_queue_t {
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
	
	private var ownQueue : dispatch_queue_t {
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
	
	private var queue: dispatch_queue_t { get {
		switch sqlite3_threadsafe() {
			case 0:
				/* SQLite was compiled without any form of thread-safety, so all requests to it need to go through the 
				shared SQLite queue */
				return QBESQLiteDatabase.sharedQueue
			
			default:
				/* SQLite is (at least) thread safe (i.e. a single connection may be used by a single thread; concurrently
				other threads may use different connections). */
				return ownQueue
		}
	} }
	
	
	private var lastError: String {
		 return String.fromCString(sqlite3_errmsg(self.db)) ?? ""
	}
	
	private func perform(op: () -> Int32) -> Bool {
		var ret: Bool = true
		dispatch_sync(queue) {() -> () in
			let code = op()
			if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW {
				QBELog("SQLite error \(code): \(self.lastError)")
				ret = false
			}
		}
		return ret
	}
	
	private static func sqliteValueToValue(value: COpaquePointer) -> QBEValue {
		switch sqlite3_value_type(value) {
			case SQLITE_NULL:
				return QBEValue.EmptyValue
			
			case SQLITE_FLOAT:
				return QBEValue.DoubleValue(sqlite3_value_double(value))
			
			case SQLITE_TEXT:
				return QBEValue.StringValue(String.fromCString(UnsafePointer<CChar>(sqlite3_value_text(value)))!)
			
			case SQLITE_INTEGER:
				return QBEValue.IntValue(Int(sqlite3_value_int64(value)))
			
			default:
				return QBEValue.InvalidValue
		}
	}
	
	private static func sqliteResult(context: COpaquePointer, result: QBEValue) {
		switch result {
			case .InvalidValue:
				sqlite3_result_null(context)
				
			case .EmptyValue:
				sqlite3_result_null(context)
				
			case .StringValue(let s):
				sqlite3_result_text(context, s, -1, SQLITE_TRANSIENT)
				
			case .IntValue(let s):
				sqlite3_result_int64(context, Int64(s))
				
			case .DoubleValue(let d):
				sqlite3_result_double(context, d)
				
			case .BoolValue(let b):
				sqlite3_result_int64(context, b ? 1 : 0)
		}
	}
	
	private static let sqliteUDFFunctionName = "WARP_FUNCTION"
	private static let sqliteUDFBinaryName = "WARP_BINARY"
	
	/* This function implements the 'WARP_FUNCTION' user-defined function in SQLite. When called, it looks up the native
	implementation of a QBEFunction whose raw value name is equal to the first parameter. It applies the function to the
	other parameters and returns the result to SQLite. */
	private static func sqliteUDFFunction(context: COpaquePointer, argc: Int32,  values: UnsafeMutablePointer<COpaquePointer>) {
		assert(argc>0, "The Warp UDF should always be called with at least one parameter")
		let functionName = sqliteValueToValue(values[0]).stringValue!
		let type = QBEFunction(rawValue: functionName)!
		assert(type.isDeterministic, "Calling non-deterministic function through SQLite Warp UDF is not allowed")
		
		var args: [QBEValue] = []
		for i in 1..<argc {
			let sqliteValue = values[Int(i)]
			args.append(sqliteValueToValue(sqliteValue))
		}
		
		let result = type.apply(args)
		sqliteResult(context, result: result)
	}
	
	/* This function implements the 'WARP_BINARY' user-defined function in SQLite. When called, it looks up the native
	implementation of a QBEBinary whose raw value name is equal to the first parameter. It applies the function to the
	other parameters and returns the result to SQLite. */
	private static func sqliteUDFBinary(context: COpaquePointer, argc: Int32,  values: UnsafeMutablePointer<COpaquePointer>) {
		assert(argc==3, "The Warp_binary UDF should always be called with three parameters")
		let functionName = sqliteValueToValue(values[0]).stringValue!
		let type = QBEBinary(rawValue: functionName)!
		let first = sqliteValueToValue(values[1])
		let second = sqliteValueToValue(values[2])
		
		let result = type.apply(first, second)
		sqliteResult(context, result: result)
	}
	
	init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		self.url = NSURL(fileURLWithPath: path)?.absoluteString
		super.init(dialect: QBESQLiteDialect())
		
		if !perform({sqlite3_open_v2(path, &self.db, flags, nil) }) {
			return nil
		}
		
		/* By default, SQLite does not implement various mathematical SQL functions such as SIN, COS, TAN, as well as 
		certain aggregates such as STDEV. RegisterExtensionFunctions plugs these into the database. */
		RegisterExtensionFunctions(self.db)
		
		/* Create the 'WARP_*' user-defined functions in SQLite. When called, it looks up the native implementation of a
		QBEFunction/QBEBinary whose raw value name is equal to the first parameter. It applies the function to the other parameters
		and returns the result to SQLite. */
		SQLiteCreateFunction(self.db, QBESQLiteDatabase.sqliteUDFFunctionName, -1, true, QBESQLiteDatabase.sqliteUDFFunction)
		SQLiteCreateFunction(self.db, QBESQLiteDatabase.sqliteUDFBinaryName, 3, true, QBESQLiteDatabase.sqliteUDFBinary)
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

func ==(lhs: QBESQLiteDatabase, rhs: QBESQLiteDatabase) -> Bool {
	return lhs.db == rhs.db || (lhs.url == rhs.url && lhs.url != nil && rhs.url != nil)
}

internal class QBESQLiteDialect: QBEStandardSQLDialect {
	// SQLite does not support column names with '"' in them.
	override func columnIdentifier(column: QBEColumn, table: String?) -> String {
		return super.columnIdentifier(QBEColumn(column.name.stringByReplacingOccurrencesOfString("\"", withString: "", options: NSStringCompareOptions.allZeros, range: nil)), table: table)
	}
	
	override func binaryToSQL(type: QBEBinary, first: String, second: String) -> String? {
		let result: String?
		switch type {
			/** For 'contains string', the default implementation uses "a LIKE '%b%'" syntax. Using INSTR is probably a
			bit faster on SQLite. **/
			case .ContainsString: result = "INSTR(LOWER(\(second)), LOWER(\(first)))>0"
			case .ContainsStringStrict: result = "INSTR(\(second), \(first))>0"
			case .MatchesRegex: result = nil // Force usage of UDF here, SQLite does not implement (a REGEXP p)
			case .MatchesRegexStrict: result = nil
			case .Concatenation: result = "(\(second) || \(first))"
			
			default:
				result = super.binaryToSQL(type, first: first, second: second)
		}
		
		/* If a binary expression cannot be represented in 'normal' SQL, we can always use the special UDF function to 
		call into the native implementation */
		if result == nil {
			return "\(QBESQLiteDatabase.sqliteUDFBinaryName)('\(type.rawValue)',\(second), \(first))"
		}
		return result
	}
	
	override func unaryToSQL(type: QBEFunction, args: [String]) -> String? {
		let result: String?
		switch type {
			case .Concat:
				result = args.implode(" || ") ?? ""
			
			default:
				result = super.unaryToSQL(type, args: args)
		}
		
		if result != nil {
			return result
		}
		
		/* If a function cannot be implemented in SQL, we should fall back to our special UDF function to call into the 
		native implementation */
		let value = args.implode(", ") ?? ""
		return "\(QBESQLiteDatabase.sqliteUDFFunctionName)('\(type.rawValue)',\(value))"
	}
	
	override func aggregationToSQL(aggregation: QBEAggregation, alias: String) -> String? {
		// QBEFunction.Count only counts numeric values
		if aggregation.reduce == QBEFunction.Count {
			if let expressionSQL = self.expressionToSQL(aggregation.map, alias: alias) {
				return "SUM(CASE WHEN TYPEOF(\(expressionSQL)) IN('integer', 'real') THEN 1 ELSE 0 END)"
			}
			return nil
		}
		
		return super.aggregationToSQL(aggregation, alias: alias)
	}
}

class QBESQLiteData: QBESQLData {
	private let db: QBESQLiteDatabase
	private let locale: QBELocale?

	private convenience init(db: QBESQLiteDatabase, tableName: String, locale: QBELocale?) {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName))"
		let result = db.query(query)
		
		self.init(db: db, fragment: QBESQLFragment(table: tableName, dialect: db.dialect), columns: result?.columnNames ?? [], locale: locale)
	}
	
	private init(db: QBESQLiteDatabase, fragment: QBESQLFragment, columns: [QBEColumn], locale: QBELocale?) {
		self.db = db
		self.locale = locale
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBESQLiteData(db: self.db, fragment: fragment, columns: resultingColumns, locale: locale)
	}
	
	override func stream() -> QBEStream {
		return QBESQLiteStream(data: self) ?? QBEEmptyStream()
	}
	
	override func isCompatibleWith(other: QBESQLData) -> Bool {
		if let os = other as? QBESQLiteData {
			return os.db == self.db
		}
		return false
	}
}

/** 
QBESQLiteStream provides a stream of records from a SQLite result set. Because SQLite result can only be accessed once
sequentially, cloning of this stream requires re-executing the query.
*/
class QBESQLiteStream: QBESequenceStream {
	private let data: QBESQLiteData
	
	init?(data: QBESQLiteData) {
		self.data = data
		if let result = data.db.query(data.sql.sqlSelect(nil).sql) {
			super.init(SequenceOf<QBETuple>(result.sequence(data.locale)), columnNames: result.columnNames)
		}
		else {
			super.init(SequenceOf<QBETuple>([]), columnNames: [])
			return nil
		}
	}
	
	override func clone() -> QBEStream {
		return QBESQLiteStream(data: self.data) ?? QBEEmptyStream()
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
	
	private class var sharedCacheDatabase : QBESQLiteDatabase {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : QBESQLiteDatabase? = nil
		}
		dispatch_once(&Static.onceToken) {
			Static.instance = QBESQLiteDatabase(path: "", readOnly: false)
		}
		return Static.instance!
	}
	
	init(source: QBEData, locale: QBELocale?) {
		database = QBESQLiteCachedData.sharedCacheDatabase
		tableName = "cache_\(String.randomStringWithLength(32))"
		self.locale = locale
		cacheJob = QBEJob()
		super.init(data: source)
		
		let dialect = database.dialect
		
		// Create a table to cache this dataset
		QBEAsyncBackground { [unowned self] () -> () in
			source.columnNames { [unowned self] (columns) -> () in
				let columnSpec = columns.map({(column) -> String in
					let colString = dialect.columnIdentifier(column, table: nil)
					return "\(colString) VARCHAR"
				}).implode(", ")!
				
				let sql = "CREATE TABLE \(dialect.tableIdentifier(self.tableName)) (\(columnSpec))"
				if let q = self.database.query(sql) {
					q.run()
					self.stream = source.stream()
					
					// We do not need to wait for this cached data to be written to disk
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
		self.database.query("DROP TABLE \(self.database.dialect.tableIdentifier(self.tableName))")
	}
	
	private func ingest(rows: ArraySlice<QBETuple>, hasMore: Bool) {
		assert(!isCached, "Cannot ingest more rows after data has already been cached")
		if hasMore && !cacheJob.cancelled {
			self.stream?.fetch(self.ingest, job: cacheJob)
		}
		
		QBETime("SQLite insert", rows.count, "rows", cacheJob) {
			if let statement = self.insertStatement {
				for row in rows {
					statement.run(parameters: row)
				}
			}
		}
		
		if !hasMore {
			// Swap out the original source with our new cached source
			QBELog("Done caching, swapping out")
			self.database.query("END TRANSACTION")?.run()
			self.data.columnNames({[unowned self] (columns) -> () in
				self.data = QBESQLiteData(db: self.database, fragment: QBESQLFragment(table: self.tableName, dialect: self.database.dialect), columns: columns, locale: self.locale)
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
		
		if let url = file?.url {
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
			
			if self.tableName == nil {
				if let first = self.db?.tableNames?.first {
					self.tableName = first
				}
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
	
	override func exampleData(job: QBEJob?, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.random(maxInputRows))
		})
	}
	
	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? ""
		
		let u = aDecoder.decodeObjectForKey("fileURL") as? NSURL
		let b = aDecoder.decodeObjectForKey("fileBookmark") as? NSData
		self.file = QBEFileReference.create(u, b)
		super.init(coder: aDecoder)
		
		if let url = u {
			url.startAccessingSecurityScopedResource()
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
		}
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
