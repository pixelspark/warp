import Foundation
import WarpCore

private class QBESQLiteResult {
	let resultSet: COpaquePointer
	let db: QBESQLiteConnection
	
	static func create(sql: String, db: QBESQLiteConnection) -> QBEFallible<QBESQLiteResult> {
		var resultSet: COpaquePointer = nil
		QBELog("SQL \(sql)")
		if !db.perform({sqlite3_prepare_v2(db.db, sql, -1, &resultSet, nil)}) {
			return .Failure(db.lastError)
		}
		else {
			return .Success(QBESQLiteResult(resultSet: resultSet, db: db))
		}
	}
	
	init(resultSet: COpaquePointer, db: QBESQLiteConnection) {
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

	func sequence() -> AnySequence<QBEFallible<QBETuple>> {
		return AnySequence<QBEFallible<QBETuple>>(QBESQLiteResultSequence(result: self))
	}
}

private class QBESQLiteResultSequence: SequenceType {
	let result: QBESQLiteResult
	typealias Generator = QBESQLiteResultGenerator
	
	init(result: QBESQLiteResult) {
		self.result = result
	}
	
	func generate() -> Generator {
		return QBESQLiteResultGenerator(self.result)
	}
}

private class QBESQLiteResultGenerator: GeneratorType {
	typealias Element = QBEFallible<QBETuple>
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
				item = .Success(self.row)
				return SQLITE_OK
			}
			else if self.lastStatus == SQLITE_DONE {
				return SQLITE_OK
			}
			else {
				item = .Failure(self.result.db.lastError)
				return self.lastStatus
			}
		})
		
		return item
	}

	var row: QBETuple {
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

private class QBESQLiteConnection: NSObject, QBESQLConnection {
	var url: String?
	let db: COpaquePointer
	let dialect: QBESQLDialect = QBESQLiteDialect()
	let presenters: [QBEFilePresenter]

	init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		let url = NSURL(fileURLWithPath: path)
		self.url = url.absoluteString

		/* Writing to SQLite requires access to a journal file (usually it has the same name as the database itself, but
		with the 'sqlite-journal' file extension). In order to gain access to these 'related' files, we need to tell the
		system we are using the database. */
		self.presenters = url == nil ? [] : ["sqlite-journal", "sqlite-shm", "sqlite-wal", "sqlite-conch"].map { return QBEFileCoordinator.sharedInstance.present(url, secondaryExtension: $0) }
		super.init()

		dispatch_set_target_queue(self.ownQueue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))

		if !perform({sqlite3_open_v2(path, &self.db, flags, nil) }) {
			return nil
		}

		/* By default, SQLite does not implement various mathematical SQL functions such as SIN, COS, TAN, as well as
		certain aggregates such as STDEV. RegisterExtensionFunctions plugs these into the database. */
		RegisterExtensionFunctions(self.db)

		/* Create the 'WARP_*' user-defined functions in SQLite. When called, it looks up the native implementation of a
		QBEFunction/QBEBinary whose raw value name is equal to the first parameter. It applies the function to the other parameters
		and returns the result to SQLite. */
		SQLiteCreateFunction(self.db, QBESQLiteConnection.sqliteUDFFunctionName, -1, true, QBESQLiteConnection.sqliteUDFFunction)
		SQLiteCreateFunction(self.db, QBESQLiteConnection.sqliteUDFBinaryName, 3, true, QBESQLiteConnection.sqliteUDFBinary)
	}

	deinit {
		perform({sqlite3_close(self.db)})
	}
	
	private static let sharedQueue = dispatch_queue_create("nl.pixelspark.Warp.QBESQLiteConnection.Queue", DISPATCH_QUEUE_SERIAL)
	private let ownQueue : dispatch_queue_t = dispatch_queue_create("nl.pixelspark.Warp.QBESQLiteConnection.Queue", DISPATCH_QUEUE_SERIAL)
	
	private var queue: dispatch_queue_t { get {
		switch sqlite3_threadsafe() {
			case 0:
				/* SQLite was compiled without any form of thread-safety, so all requests to it need to go through the 
				shared SQLite queue */
				return QBESQLiteConnection.sharedQueue
			
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
	
	func query(sql: String) -> QBEFallible<QBESQLiteResult> {
		return QBESQLiteResult.create(sql, db: self)
	}

	func run(sql: [String], job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		for q in sql {
			switch query(q) {
				case .Success(let c):
					if !c.run() {
						callback(.Failure(self.lastError))
						return
					}

				case .Failure(let e):
					callback(.Failure(e))
					return
			}
		}
		callback(.Success())
	}
	
	var tableNames: QBEFallible<[String]> { get {
		let names = query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC")
		
		return names.use({(ns) -> [String] in
			var nameStrings: [String] = []
			for name in ns.sequence() {
				switch name {
				case .Success(let n):
					nameStrings.append(n[0].stringValue!)

				case .Failure(_):
					// Ignore
					break
				}

			}
			return nameStrings
		})
	} }
}

private func ==(lhs: QBESQLiteConnection, rhs: QBESQLiteConnection) -> Bool {
	return lhs.db == rhs.db || (lhs.url == rhs.url && lhs.url != nil && rhs.url != nil)
}

private class QBESQLiteDialect: QBEStandardSQLDialect {
	// SQLite does not support changing column definitions using an ALTER statement
	override var supportsChangingColumnDefinitionsWithAlter: Bool { return false }

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
			return "\(QBESQLiteConnection.sqliteUDFBinaryName)('\(type.rawValue)',\(second), \(first))"
		}
		return result
	}
	
	override func unaryToSQL(type: QBEFunction, args: [String]) -> String? {
		let result: String?
		switch type {
			case .Concat:
				result = args.joinWithSeparator(" || ")
			
			default:
				result = super.unaryToSQL(type, args: args)
		}
		
		if result != nil {
			return result
		}
		
		/* If a function cannot be implemented in SQL, we should fall back to our special UDF function to call into the 
		native implementation */
		let value = args.joinWithSeparator(", ")
		return "\(QBESQLiteConnection.sqliteUDFFunctionName)('\(type.rawValue)',\(value))"
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
	private let db: QBESQLiteConnection
	
	static private func create(db: QBESQLiteConnection, tableName: String) -> QBEFallible<QBESQLiteData> {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		switch db.query(query) {
			case .Success(let result):
				return .Success(QBESQLiteData(db: db, fragment: QBESQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: result.columnNames))
				
			case .Failure(let error):
				return .Failure(error)
		}
	}
	
	private init(db: QBESQLiteConnection, fragment: QBESQLFragment, columns: [QBEColumn]) {
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
					resultStream = QBESequenceStream(AnySequence<QBEFallible<QBETuple>>(result.sequence()), columnNames: result.columnNames)
					
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

private class QBESQLiteWriterSession {
	private let database: QBESQLiteConnection
	private let tableName: String
	private let source: QBEData

	private var job: QBEJob? = nil
	private var stream: QBEStream?
	private var insertStatement: QBESQLiteResult?
	private var completion: ((QBEFallible<Void>) -> ())?

	init(data source: QBEData, toDatabase database: QBESQLiteConnection, tableName: String) {
		self.database = database
		self.tableName = tableName
		self.source = source
	}

	func start(job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		let dialect = database.dialect
		self.completion = callback
		self.job = job

		job.async {
			self.source.columnNames(job) { (columns) -> () in
				switch columns {
				case .Success(let cns):
					// Create SQL field specifications for the columns
					let columnSpec = cns.map({ (column) -> String in
						let colString = dialect.columnIdentifier(column, table: nil, schema: nil, database: nil)
						return "\(colString) VARCHAR"
					}).joinWithSeparator(", ")

					// Create destination table
					let sql = "CREATE TABLE \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) (\(columnSpec))"
					switch self.database.query(sql) {
					case .Success(let createQuery):
						createQuery.run()
						self.stream = self.source.stream()

						// Prepare the insert-statement
						let values = cns.map({(m) -> String in return "?"}).joinWithSeparator(",")
						switch self.database.query("INSERT INTO \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) VALUES (\(values))") {
						case .Success(let insertStatement):
							self.insertStatement = insertStatement
							/** SQLite inserts are fastest when they are grouped in a transaction (see docs).
							A transaction is started here and is ended in self.ingest. */
							self.database.query("BEGIN").require { r in
								r.run()
								// TODO: use QBEStreamPuller to do this with more threads simultaneously
								self.stream?.fetch(job, consumer: self.ingest)
							}

						case .Failure(let error):
							callback(.Failure(error))
						}

					case .Failure(let error):
						callback(.Failure(error))
					}

				case .Failure(let error):
					callback(.Failure(error))
				}
			}
		}
	}

	private func ingest(rows: QBEFallible<Array<QBETuple>>, streamStatus: QBEStreamStatus) {
		switch rows {
		case .Success(let r):
			if streamStatus == .HasMore && !self.job!.cancelled {
				self.stream?.fetch(self.job!, consumer: self.ingest)
			}

			job!.time("SQLite insert", items: r.count, itemType: "rows") {
				if let statement = self.insertStatement {
					for row in r {
						statement.run(row)
					}
				}
			}

			if streamStatus == .Finished {
				// First end the transaction started in init
				self.database.query("COMMIT").require { c in
					if !c.run() {
						self.job!.log("COMMIT of SQLite data failed \(self.database.lastError)! not swapping")
						self.completion!(.Failure(self.database.lastError))
						self.completion = nil
						return
					}
					else {
						self.completion!(.Success())
						self.completion = nil
					}
				}
			}

		case .Failure(let errMessage):
			// Roll back the transaction that was started in init.
			self.database.query("ROLLBACK").require { c in
				c.run()
				self.completion!(.Failure(errMessage))
				self.completion = nil
			}
		}
	}
}

class QBESQLiteWriter: NSObject, QBEFileWriter, NSCoding {
	enum Mode: String {
		case Overwrite = "overwrite"
		// TODO implement Append mode. Note however that the table structure might be different, so we need to deal with taht
	}

	var mode: Mode = .Overwrite
	var tableName: String

	static func explain(fileExtension: String, locale: QBELocale) -> String {
		return NSLocalizedString("SQLite database", comment: "")
	}

	static var fileTypes: Set<String> { get { return Set(["sqlite"]) } }

	required init(locale: QBELocale, title: String?) {
		tableName = "data"
	}

	required init?(coder aDecoder: NSCoder) {
		tableName = aDecoder.decodeStringForKey("tableName") ?? "data"
		if let sm = aDecoder.decodeStringForKey("mode"), let m = Mode(rawValue: sm) {
			mode = m
		}
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeString(tableName, forKey: "tableName")
		aCoder.encodeString(mode.rawValue, forKey: "mode")
	}

	func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		if let p = file.path, let database = QBESQLiteConnection(path: p) {
			// We must disable the WAL because the sandbox doesn't allow us to write to the WAL file (created separately)
			database.query("PRAGMA journal_mode = MEMORY").require { s in
				s.run()

				switch mode {
				case .Overwrite:
					database.query("DROP TABLE IF EXISTS \(database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))").require { s in
						s.run()
						QBESQLiteWriterSession(data: data, toDatabase: database, tableName: self.tableName).start(job, callback: callback)
					}
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("Could not write to SQLite database file", comment: "")));
		}
	}

	func sentence(locale: QBELocale) -> QBESentence? {
		let modeOptions = [
			Mode.Overwrite.rawValue: NSLocalizedString("(over)write", comment: "")
		];

		return QBESentence(format: NSLocalizedString("[#] data to table [#]", comment: ""),
			QBESentenceOptions(options: modeOptions, value: self.mode.rawValue, callback: { (newMode) -> () in
				self.mode = Mode(rawValue: newMode)!
			}),
			QBESentenceTextInput(value: self.tableName, callback: { [weak self] (newTableName) -> (Bool) in
				self?.tableName = newTableName
				return true
			})
		)
	}
}

/**
Cache a given QBEData data set in a SQLite table. Loading the data set into SQLite is performed asynchronously in the
background, and the SQLite-cached data set is swapped with the original one at completion transparently. The cache is
placed in a shared, temporary 'cache' database (sharedCacheDatabase) so that cached tables can efficiently be joined by
SQLite. Users of this class can set a completion callback if they want to wait until caching has finished. */
class QBESQLiteCachedData: QBEProxyData {
	private let database: QBESQLiteConnection
	private let tableName: String
	private(set) var isCached: Bool = false
	private let cacheJob: QBEJob
	
	private class var sharedCacheDatabase : QBESQLiteConnection {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : QBESQLiteConnection? = nil
		}
		
		dispatch_once(&Static.onceToken) {
			Static.instance = QBESQLiteConnection(path: "", readOnly: false)
			/** Because this database is created anew, we can set its encoding. As the code reading strings from SQLite
			uses UTF-8, set the database's encoding to UTF-8 so that no unnecessary conversions have to take place. */
			Static.instance!.query("PRAGMA encoding = \"UTF-8\"").require { e in
				e.run()
				Static.instance!.query("PRAGMA synchronous = OFF").require { r in
					r.run()
					Static.instance!.query("PRAGMA journal_mode = MEMORY").require { s in
						s.run()
					}
				}
			}
		}
		return Static.instance!
	}
	
	init(source: QBEData, job: QBEJob? = nil, completion: ((QBEFallible<QBESQLiteCachedData>) -> ())? = nil) {
		database = QBESQLiteCachedData.sharedCacheDatabase
		tableName = "cache_\(String.randomStringWithLength(32))"
		self.cacheJob = job ?? QBEJob(.Background)
		super.init(data: source)
		
		QBESQLiteWriterSession(data: source, toDatabase: database, tableName: tableName).start(cacheJob) { (result) -> () in
			switch result {
			case .Success:
				// Swap out the original source with our new cached source
				self.cacheJob.log("Done caching, swapping out")
				self.data.columnNames(self.cacheJob) { [unowned self] (columns) -> () in
					switch columns {
					case .Success(let cns):
						self.data = QBESQLiteData(db: self.database, fragment: QBESQLFragment(table: self.tableName, schema: nil, database: nil, dialect: self.database.dialect), columns: cns)
						self.isCached = true
						completion?(.Success(self))

					case .Failure(let error):
						completion?(.Failure(error))
					}
				}
			case .Failure(let e):
				completion?(.Failure(e))
			}
		}
	}

	deinit {
		cacheJob.cancel()
		self.database.query("DROP TABLE \(self.database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))")
	}
}

class QBESQLiteDatabase: QBESQLDatabase {
	let url: NSURL
	let readOnly: Bool
	let dialect: QBESQLDialect = QBESQLiteDialect()
	let databaseName: String? = nil

	init(url: NSURL, readOnly: Bool) {
		self.url = url
		self.readOnly = readOnly
	}

	func connect(callback: (QBEFallible<QBESQLConnection>) -> ()) {
		if let c = QBESQLiteConnection(path: self.url.path!, readOnly: self.readOnly) {
			callback(.Success(c))
		}
		else {
			callback(.Failure("Could not connect to SQLite database"))
		}
	}

	func dataForTable(table: String, schema: String?, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if schema != nil {
			callback(.Failure("SQLite does not support schemas"))
			return
		}

		if let con = QBESQLiteConnection(path: self.url.path!, readOnly: self.readOnly) {
			switch QBESQLiteData.create(con, tableName: table) {
			case .Success(let d): callback(.Success(d))
			case .Failure(let e): callback(.Failure(e))
			}
		}
		else {
			callback(.Failure("Could not connect to SQLite database"))
		}
	}
}

class QBESQLiteDataWarehouse: QBESQLDataWarehouse {
	override init(database: QBESQLDatabase, schemaName: String?) {
		super.init(database: database, schemaName: schemaName)
	}

	override func canPerformMutation(mutation: QBEWarehouseMutation) -> Bool {
		switch mutation {
		case .Create(_, _):
			// A read-only database cannot be mutated
			let db = self.database as! QBESQLiteDatabase
			return !db.readOnly
		}
	}
}

class QBESQLiteMutableData: QBESQLMutableData {
	override var warehouse: QBEDataWarehouse { return QBESQLiteDataWarehouse(database: self.database, schemaName: self.schemaName) }
}

class QBESQLiteSourceStep: QBEStep {
	var file: QBEFileReference? = nil { didSet {
		oldValue?.url?.stopAccessingSecurityScopedResource()
		file?.url?.startAccessingSecurityScopedResource()
		switchDatabase()
	} }
	
	var tableName: String? = nil
	private var db: QBESQLiteConnection? = nil

	required init() {
		super.init()
	}
	
	init?(url: NSURL) {
		self.file = QBEFileReference.URL(url)
		super.init()
		switchDatabase()
	}
	
	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	private func switchDatabase() {
		self.db = nil
		
		if let url = file?.url {
			self.db = QBESQLiteConnection(path: url.path!, readOnly: true)
			
			if self.tableName == nil {
				self.db?.tableNames.maybe {(tns) in
					self.tableName = tns.first
				}
			}
		}
	}

	override func sentence(locale: QBELocale, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .Read, .Neutral: template = "Load table [#] from SQLite database [#]"
		case .Write: template = "Write to table [#] in SQLite database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceList(value: self.tableName ?? "", provider: { [weak self] (cb) -> () in
				if let d = self?.db {
					cb(d.tableNames)
				}
			}, callback: { [weak self] (newTable) -> () in
				self?.tableName = newTable
			}),
			QBESentenceFile(file: self.file, allowedFileTypes: ["org.sqlite.v3"], callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}
	
	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let d = db {
			callback(QBESQLiteData.create(d, tableName: self.tableName ?? "").use({return $0.coalesced}))
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
			self.db = QBESQLiteConnection(path: url.path!, readOnly: true)
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

	override var mutableData: QBEMutableData? {
		if let u = self.file?.url, let tn = tableName {
			return QBESQLiteMutableData(database: QBESQLiteDatabase(url: u, readOnly: false), schemaName: nil, tableName: tn)
		}
		return nil
	}
	
	override func didLoadFromDocument(atURL: NSURL) {
		self.file = self.file?.resolve(atURL)
		if let url = self.file?.url {
			url.startAccessingSecurityScopedResource()
			self.db = QBESQLiteConnection(path: url.path!, readOnly: true)
		}
	}
}
