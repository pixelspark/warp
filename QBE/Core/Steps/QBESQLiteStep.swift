import Foundation

internal class QBESQLiteResult {
	let resultSet: COpaquePointer
	let db: QBESQLiteDatabase
	
	static func create(sql: String, db: QBESQLiteDatabase) -> QBEFallible<QBESQLiteResult> {
		var resultSet: COpaquePointer = nil
		QBELog("SQL \(sql)")
		if !db.perform({sqlite3_prepare_v2(db.db, sql, -1, &resultSet, nil)}) {
			return .Failure(db.lastError)
		}
		else {
			return .Success(QBESQLiteResult(resultSet: resultSet, db: db))
		}
	}
	
	init(resultSet: COpaquePointer, db: QBESQLiteDatabase) {
		self.resultSet = resultSet
		self.db = db
	}
	
	deinit {
		sqlite3_finalize(resultSet)
	}
	
	/** Run is used to execute statements that do not return data (e.g. UPDATE, INSERT, DELETE, etc.). It can optionally
	be fed with parameters which will be bound before query execution. */
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
							result = sqlite3_bind_text(self.resultSet, CInt(i+1), s, -1, sqlite3_transient_destructor)
						
						case .IntValue(let x):
							result = sqlite3_bind_int64(self.resultSet, CInt(i+1), sqlite3_int64(x))
						
						case .DoubleValue(let d):
							result = sqlite3_bind_double(self.resultSet, CInt(i+1), d)
						
						case .DateValue(let d):
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

	func sequence() -> AnySequence<QBETuple> {
		return AnySequence<QBETuple>(QBESQLiteResultSequence(result: self))
	}
}

internal class QBESQLiteResultSequence: SequenceType {
	let result: QBESQLiteResult
	typealias Generator = QBESQLiteResultGenerator
	
	init(result: QBESQLiteResult) {
		self.result = result
	}
	
	func generate() -> Generator {
		return QBESQLiteResultGenerator(self.result)
	}
}

internal class QBESQLiteResultGenerator: GeneratorType {
	typealias Element = QBETuple
	let result: QBESQLiteResult
	var lastStatus: Int32 = SQLITE_OK
	
	init(_ result: QBESQLiteResult) {
		self.result = result
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
				if let type = String.fromCString(sqlite3_column_decltype(self.result.resultSet, Int32(idx))) {
					if type.hasPrefix("BOOL") {
						return QBEValue(intValue != 0)
					}
				}
				return QBEValue(intValue)
				
			case SQLITE_TEXT:
				if let string = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx)))) {
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
				sqlite3_result_text(context, s, -1, sqlite3_transient_destructor)
				
			case .IntValue(let s):
				sqlite3_result_int64(context, Int64(s))
				
			case .DoubleValue(let d):
				sqlite3_result_double(context, d)
			
			case .DateValue(let d):
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
		self.url = NSURL(fileURLWithPath: path).absoluteString
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
	
	func query(sql: String) -> QBEFallible<QBESQLiteResult> {
		return QBESQLiteResult.create(sql, db: self)
	}
	
	var tableNames: QBEFallible<[String]> { get {
		let names = query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC")
		
		return names.use({(ns) -> [String] in
			var nameStrings: [String] = []
			for name in ns.sequence() {
				nameStrings.append(name[0].stringValue!)
			}
			return nameStrings
		})
	} }
}

func ==(lhs: QBESQLiteDatabase, rhs: QBESQLiteDatabase) -> Bool {
	return lhs.db == rhs.db || (lhs.url == rhs.url && lhs.url != nil && rhs.url != nil)
}

internal class QBESQLiteDialect: QBEStandardSQLDialect {
	// SQLite does not support column names with '"' in them.
	override func columnIdentifier(column: QBEColumn, table: String?, schema: String?, database: String?) -> String {
		return super.columnIdentifier(QBEColumn(column.name.stringByReplacingOccurrencesOfString("\"", withString: "", options: NSStringCompareOptions(), range: nil)), table: table, schema: schema, database: database)
	}
	
	override func binaryToSQL(type: QBEBinary, first: String, second: String) -> String? {
		let result: String?
		switch type {
			/** For 'contains string', the default implementation uses "a LIKE '%b%'" syntax. Using INSTR is probably a
			bit faster on SQLite. */
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
	
	static func create(db: QBESQLiteDatabase, tableName: String) -> QBEFallible<QBESQLiteData> {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		switch db.query(query) {
			case .Success(let result):
				return .Success(QBESQLiteData(db: db, fragment: QBESQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: result.columnNames))
				
			case .Failure(let error):
				return .Failure(error)
		}
	}
	
	private init(db: QBESQLiteDatabase, fragment: QBESQLFragment, columns: [QBEColumn]) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBESQLiteData(db: self.db, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> QBEStream {
		return QBESQLiteStream(data: self) ?? QBEEmptyStream()
	}
	
	private func result() -> QBEFallible<QBESQLiteResult> {
		return self.db.query(self.sql.sqlSelect(nil).sql)
	}
	
	override func isCompatibleWith(other: QBESQLData) -> Bool {
		if let os = other as? QBESQLiteData {
			return os.db == self.db
		}
		return false
	}
}

/**
Stream that lazily queries and streams results from an SQLite query. */
class QBESQLiteStream: QBEStream {
	private var resultStream: QBEStream?
	private let data: QBESQLiteData
	
	init(data: QBESQLiteData) {
		self.data = data
	}
	
	private func stream() -> QBEStream {
		if resultStream == nil {
			switch data.result() {
				case .Success(let result):
					resultStream = QBESequenceStream(AnySequence<QBETuple>(result.sequence()), columnNames: result.columnNames)
					
				case .Failure(let error):
					resultStream = QBEErrorStream(error)
			}
		}
		
		return resultStream!
	}
	
	func fetch(job: QBEJob, consumer: QBESink) {
		return stream().fetch(job, consumer: consumer)
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		return stream().columnNames(job, callback: callback)
	}
	
	func clone() -> QBEStream {
		return QBESQLiteStream(data: data)
	}
}

/**
Cache a given QBEData data set in a SQLite table. Loading the data set into SQLite is performed asynchronously in the
background, and the SQLite-cached data set is swapped with the original one at completion transparently. The cache is
placed in a shared, temporary 'cache' database (sharedCacheDatabase) so that cached tables can efficiently be joined by
SQLite. Users of this class can set a completion callback if they want to wait until caching has finished. */
class QBESQLiteCachedData: QBEProxyData {
	private let database: QBESQLiteDatabase
	private let tableName: String
	private var stream: QBEStream?
	private var insertStatement: QBESQLiteResult?
	private(set) var isCached: Bool = false
	var completion: ((QBEFallible<QBESQLiteCachedData>) -> ())? = nil
	let cacheJob: QBEJob
	
	private class var sharedCacheDatabase : QBESQLiteDatabase {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : QBESQLiteDatabase? = nil
		}
		
		dispatch_once(&Static.onceToken) {
			Static.instance = QBESQLiteDatabase(path: "", readOnly: false)
			Static.instance!.query("PRAGMA synchronous = OFF").require {(r) -> () in
				r.run()
				Static.instance!.query("PRAGMA journal_mode = MEMORY").require {(s) -> () in
					s.run()
				}
			}
		}
		return Static.instance!
	}
	
	init(source: QBEData, job: QBEJob? = nil, completion: ((QBEFallible<QBESQLiteCachedData>) -> ())? = nil) {
		self.completion = completion
		database = QBESQLiteCachedData.sharedCacheDatabase
		tableName = "cache_\(String.randomStringWithLength(32))"
		cacheJob = job ?? QBEJob(.Background)
		super.init(data: source)
		
		let dialect = database.dialect
		
		// Start caching
		cacheJob.async {
			source.columnNames(self.cacheJob) { (columns) -> () in
				switch columns {
					case .Success(let cns):
						let columnSpec = cns.map({(column) -> String in
							
							let colString = dialect.columnIdentifier(column, table: nil, schema: nil, database: nil)
							return "\(colString) VARCHAR"
						}).implode(", ")
						
						let sql = "CREATE TABLE \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) (\(columnSpec))"
						switch self.database.query(sql) {
							case .Success(let createQuery):
								createQuery.run()
								self.stream = source.stream()
							
								// Prepare the insert-statement
								let values = cns.map({(m) -> String in return "?"}).implode(",") ?? ""
								switch self.database.query("INSERT INTO \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) VALUES (\(values))") {
									case .Success(let insertStatement):
										self.insertStatement = insertStatement
										self.stream?.fetch(self.cacheJob, consumer: self.ingest)
										
									case .Failure(let error):
										completion?(.Failure(error))
								}
							
							case .Failure(let error):
								completion?(.Failure(error))
						}
					
					case .Failure(let error):
						completion?(.Failure(error))
				}
			}
		}
	}
	
	deinit {
		cacheJob.cancel()
		self.database.query("DROP TABLE \(self.database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))")
	}
	
	private func ingest(rows: QBEFallible<ArraySlice<QBETuple>>, hasMore: Bool) {
		assert(!isCached, "Cannot ingest more rows after data has already been cached")
		
		switch rows {
			case .Success(let r):
				if hasMore && !cacheJob.cancelled {
					self.stream?.fetch(cacheJob, consumer: self.ingest)
				}
				
				cacheJob.time("SQLite insert", items: r.count, itemType: "rows") {
					if let statement = self.insertStatement {
						for row in r {
							statement.run(row)
						}
					}
				}
				
				if !hasMore {
					// Swap out the original source with our new cached source
					self.cacheJob.log("Done caching, swapping out")
					self.data.columnNames(cacheJob) { [unowned self] (columns) -> () in
						switch columns {
							case .Success(let cns):
								self.data = QBESQLiteData(db: self.database, fragment: QBESQLFragment(table: self.tableName, schema: nil, database: nil, dialect: self.database.dialect), columns: cns)
								self.isCached = true
								self.completion?(.Success(self))
								self.completion = nil
								
							case .Failure(let error):
								self.completion?(.Failure(error))
								self.completion = nil
						}
					}
				}
			
			case .Failure(let errMessage):
				self.completion?(.Failure(errMessage))
				self.completion = nil
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
				self.db?.tableNames.maybe {(tns) in
					self.tableName = tns.first
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
	
	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let d = db {
			callback(QBESQLiteData.create(d, tableName: self.tableName ?? "").use({return QBECoalescedData($0)}))
		}
		else {
			callback(.Failure(NSLocalizedString("a SQLite database could not be found.", comment: "")))
		}
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.use {(x) -> QBEData in
				return x.random(maxInputRows)
			})
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
