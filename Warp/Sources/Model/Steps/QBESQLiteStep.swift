import Foundation
import WarpCore

private class QBESQLiteResult {
	let resultSet: COpaquePointer
	let db: QBESQLiteConnection
	
	static func create(sql: String, db: QBESQLiteConnection) -> Fallible<QBESQLiteResult> {
		var resultSet: COpaquePointer = nil
		trace("SQL \(sql)")
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
		db.perform { sqlite3_finalize(self.resultSet) }
	}
	
	/** Run is used to execute statements that do not return data (e.g. UPDATE, INSERT, DELETE, etc.). It can optionally
	be fed with parameters which will be bound before query execution. */
	func run(parameters: [Value]? = nil) -> Bool {
		// If there are parameters, bind them
		return self.db.mutex.locked {
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
						trace("SQLite error on parameter bind: \(self.db.lastError)")
						return false
					}
					
					i += 1
				}
			}
		
			let result = sqlite3_step(self.resultSet)
			if result != SQLITE_ROW && result != SQLITE_DONE {
				trace("SQLite error running statement: \(self.db.lastError)")
				return false
			}
			
			if sqlite3_clear_bindings(self.resultSet) != SQLITE_OK {
				trace("SQLite: failed to clear parameter bindings: \(self.db.lastError)")
				return false
			}
			
			if sqlite3_reset(self.resultSet) != SQLITE_OK {
				trace("SQLite: could not reset statement: \(self.db.lastError)")
				return false
			}

			return true
		}
	}
	
	var columnCount: Int { get {
		return self.db.mutex.locked {
			return Int(sqlite3_column_count(self.resultSet))
		}
	} }
	
	 var columns: [Column] { get {
		return self.db.mutex.locked {
			let count = sqlite3_column_count(self.resultSet)
			return (0..<count).map({Column(String.fromCString(sqlite3_column_name(self.resultSet, $0))!)})
		}
	} }

	func sequence() -> AnySequence<Fallible<Tuple>> {
		return AnySequence<Fallible<Tuple>>(QBESQLiteResultSequence(result: self))
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
	typealias Element = Fallible<Tuple>
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

	var row: Tuple {
		return self.result.db.mutex.locked {
			return (0..<result.columns.count).map { idx in
				switch sqlite3_column_type(self.result.resultSet, Int32(idx)) {
				case SQLITE_FLOAT:
					return Value(sqlite3_column_double(self.result.resultSet, Int32(idx)))
					
				case SQLITE_NULL:
					return Value.EmptyValue
					
				case SQLITE_INTEGER:
					// Booleans are represented as integers, but boolean columns are declared as BOOL columns
					let intValue = Int(sqlite3_column_int64(self.result.resultSet, Int32(idx)))
					if let type = String.fromCString(sqlite3_column_decltype(self.result.resultSet, Int32(idx))) {
						if type.hasPrefix("BOOL") {
							return Value(intValue != 0)
						}
					}
					return Value(intValue)
					
				case SQLITE_TEXT:
					if let string = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx)))) {
						return Value(string)
					}
					else {
						return Value.InvalidValue
					}
					
				default:
					return Value.InvalidValue
				}
			}
		}
	}
}

private class QBESQLiteConnection: NSObject, SQLConnection {
	var url: String?
	let db: COpaquePointer
	let dialect: SQLDialect = QBESQLiteDialect()
	let presenters: [QBEFilePresenter]

	init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		let url = NSURL(fileURLWithPath: path, isDirectory: false)
		self.url = url.absoluteString

		/* Writing to SQLite requires access to a journal file (usually it has the same name as the database itself, but
		with the 'sqlite-journal' file extension). In order to gain access to these 'related' files, we need to tell the
		system we are using the database. */
		if path.isEmpty {
			self.presenters = []
		}
		else {
			self.presenters = ["sqlite-journal", "sqlite-shm", "sqlite-wal", "sqlite-conch"].map { return QBEFileCoordinator.sharedInstance.present(url, secondaryExtension: $0) }
		}

		super.init()

		if !perform({sqlite3_open_v2(path, &self.db, flags, nil) }) {
			return nil
		}

		/* By default, SQLite does not implement various mathematical SQL functions such as SIN, COS, TAN, as well as
		certain aggregates such as STDEV. RegisterExtensionFunctions plugs these into the database. */
		RegisterExtensionFunctions(self.db)

		/* Create the 'WARP_*' user-defined functions in SQLite. When called, it looks up the native implementation of a
		Function/Binary whose raw value name is equal to the first parameter. It applies the function to the other parameters
		and returns the result to SQLite. */
		SQLiteCreateFunction(self.db, QBESQLiteConnection.sqliteUDFFunctionName, -1, true, QBESQLiteConnection.sqliteUDFFunction)
		SQLiteCreateFunction(self.db, QBESQLiteConnection.sqliteUDFBinaryName, 3, true, QBESQLiteConnection.sqliteUDFBinary)
	}

	deinit {
		perform {
			sqlite3_close(self.db)
		}
	}
	
	private static let sharedMutex = Mutex()
	private let ownMutex = Mutex()
	
	private var mutex: Mutex { get {
		switch sqlite3_threadsafe() {
			case 0:
				/* SQLite was compiled without any form of thread-safety, so all requests to it need to go through the 
				shared SQLite queue */
				return QBESQLiteConnection.sharedMutex
			
			default:
				/* SQLite is (at least) thread safe (i.e. a single connection may be used by a single thread; concurrently
				other threads may use different connections). */
				return ownMutex
		}
	} }
	
	
	private var lastError: String {
		 return String.fromCString(sqlite3_errmsg(self.db)) ?? ""
	}
	
	private func perform(op: () -> Int32) -> Bool {
		return mutex.locked {
			let code = op()
			if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW {
				trace("SQLite error \(code): \(self.lastError)")
				return false
			}
			return true
		}
	}
	
	private static func sqliteValueToValue(value: COpaquePointer) -> Value {
		return self.sharedMutex.locked {
			switch sqlite3_value_type(value) {
				case SQLITE_NULL:
					return Value.EmptyValue
				
				case SQLITE_FLOAT:
					return Value.DoubleValue(sqlite3_value_double(value))
				
				case SQLITE_TEXT:
					return Value.StringValue(String.fromCString(UnsafePointer<CChar>(sqlite3_value_text(value)))!)
				
				case SQLITE_INTEGER:
					return Value.IntValue(Int(sqlite3_value_int64(value)))
				
				default:
					return Value.InvalidValue
			}
		}
	}
	
	private static func sqliteResult(context: COpaquePointer, result: Value) {
		return self.sharedMutex.locked {
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
	}
	
	private static let sqliteUDFFunctionName = "WARP_FUNCTION"
	private static let sqliteUDFBinaryName = "WARP_BINARY"
	
	/* This function implements the 'WARP_FUNCTION' user-defined function in SQLite. When called, it looks up the native
	implementation of a Function whose raw value name is equal to the first parameter. It applies the function to the
	other parameters and returns the result to SQLite. */
	private static func sqliteUDFFunction(context: COpaquePointer, argc: Int32,  values: UnsafeMutablePointer<COpaquePointer>) {
		assert(argc>0, "The Warp UDF should always be called with at least one parameter")
		let functionName = sqliteValueToValue(values[0]).stringValue!
		let type = Function(rawValue: functionName)!
		assert(type.isDeterministic, "Calling non-deterministic function through SQLite Warp UDF is not allowed")
		
		var args: [Value] = []
		for i in 1..<argc {
			let sqliteValue = values[Int(i)]
			args.append(sqliteValueToValue(sqliteValue))
		}
		
		let result = type.apply(args)
		sqliteResult(context, result: result)
	}
	
	/* This function implements the 'WARP_BINARY' user-defined function in SQLite. When called, it looks up the native
	implementation of a Binary whose raw value name is equal to the first parameter. It applies the function to the
	other parameters and returns the result to SQLite. */
	private static func sqliteUDFBinary(context: COpaquePointer, argc: Int32,  values: UnsafeMutablePointer<COpaquePointer>) {
		assert(argc==3, "The Warp_binary UDF should always be called with three parameters")
		let functionName = sqliteValueToValue(values[0]).stringValue!
		let type = Binary(rawValue: functionName)!
		let first = sqliteValueToValue(values[1])
		let second = sqliteValueToValue(values[2])
		
		let result = type.apply(first, second)
		sqliteResult(context, result: result)
	}
	
	func query(sql: String) -> Fallible<QBESQLiteResult> {
		return QBESQLiteResult.create(sql, db: self)
	}

	func run(sql: [String], job: Job, callback: (Fallible<Void>) -> ()) {
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
	
	var tableNames: Fallible<[String]> { get {
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

private class QBESQLiteDialect: StandardSQLDialect {
	// SQLite does not support changing column definitions using an ALTER statement
	override var supportsChangingColumnDefinitionsWithAlter: Bool { return false }

	// SQLite does not support column names with '"' in them.
	override func columnIdentifier(column: Column, table: String?, schema: String?, database: String?) -> String {
		return super.columnIdentifier(Column(column.name.stringByReplacingOccurrencesOfString("\"", withString: "", options: NSStringCompareOptions(), range: nil)), table: table, schema: schema, database: database)
	}
	
	override func binaryToSQL(type: Binary, first: String, second: String) -> String? {
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
	
	override func unaryToSQL(type: Function, args: [String]) -> String? {
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
	
	override func aggregationToSQL(aggregation: Aggregator, alias: String) -> String? {
		switch aggregation.reduce {
		case .StandardDeviationPopulation, .StandardDeviationSample, .VarianceSample, .VariancePopulation:
			// These aren't supported in SQLite
			// TODO: implement as UDF
			return nil

		case .Count:
			// COUNT in SQLite counts everything, we want just the numeric values (Function.CountAll counts everything)
			if let expressionSQL = self.expressionToSQL(aggregation.map, alias: alias) {
				return "SUM(CASE WHEN TYPEOF(\(expressionSQL)) IN('integer', 'real') THEN 1 ELSE 0 END)"
			}
			return nil

		default:
			return super.aggregationToSQL(aggregation, alias: alias)
		}
	}
}

class QBESQLiteData: SQLData {
	private let db: QBESQLiteConnection
	
	static private func create(db: QBESQLiteConnection, tableName: String) -> Fallible<QBESQLiteData> {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		switch db.query(query) {
			case .Success(let result):
				return .Success(QBESQLiteData(db: db, fragment: SQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: result.columns))
				
			case .Failure(let error):
				return .Failure(error)
		}
	}
	
	private init(db: QBESQLiteConnection, fragment: SQLFragment, columns: [Column]) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(fragment: SQLFragment, resultingColumns: [Column]) -> Data {
		return QBESQLiteData(db: self.db, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> Stream {
		return QBESQLiteStream(data: self) ?? EmptyStream()
	}
	
	private func result() -> Fallible<QBESQLiteResult> {
		return self.db.query(self.sql.sqlSelect(nil).sql)
	}

	override func isCompatibleWith(other: SQLData) -> Bool {
		if let os = other as? QBESQLiteData {
			return os.db == self.db
		}
		return false
	}

	/** SQLite does not support "OFFSET" without a LIMIT clause. It does support "LIMIT -1 OFFSET x". */
	override func offset(numberOfRows: Int) -> Data {
		return self.apply(sql.sqlLimit("-1").sqlOffset("\(numberOfRows)"), resultingColumns: columns)
	}
}

/**
Stream that lazily queries and streams results from an SQLite query. */
class QBESQLiteStream: Stream {
	private var resultStream: Stream?
	private let data: QBESQLiteData
	private let mutex = Mutex()
	
	init(data: QBESQLiteData) {
		self.data = data
	}
	
	private func stream() -> Stream {
		return self.mutex.locked {
			if resultStream == nil {
				switch data.result() {
					case .Success(let result):
						resultStream = SequenceStream(AnySequence<Fallible<Tuple>>(result.sequence()), columns: result.columns)
						
					case .Failure(let error):
						resultStream = ErrorStream(error)
				}
			}
			
			return resultStream!
		}
	}
	
	func fetch(job: Job, consumer: Sink) {
		return stream().fetch(job, consumer: consumer)
	}
	
	func columns(job: Job, callback: (Fallible<[Column]>) -> ()) {
		return stream().columns(job, callback: callback)
	}
	
	func clone() -> Stream {
		return QBESQLiteStream(data: data)
	}
}

private class QBESQLiteWriterSession {
	private let database: QBESQLiteConnection
	private let tableName: String
	private let source: Data

	private var job: Job? = nil
	private var stream: Stream?
	private var insertStatement: QBESQLiteResult?
	private var completion: ((Fallible<Void>) -> ())?

	init(data source: Data, toDatabase database: QBESQLiteConnection, tableName: String) {
		self.database = database
		self.tableName = tableName
		self.source = source
	}

	func start(job: Job, callback: (Fallible<Void>) -> ()) {
		let dialect = database.dialect
		self.completion = callback
		self.job = job

		job.async {
			self.source.columns(job) { (columns) -> () in
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
								// TODO: use StreamPuller to do this with more threads simultaneously
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

	private func ingest(rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) {
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
	var tableName: String

	static func explain(fileExtension: String, locale: Locale) -> String {
		return NSLocalizedString("SQLite database", comment: "")
	}

	static var fileTypes: Set<String> { get { return Set(["sqlite"]) } }

	required init(locale: Locale, title: String?) {
		tableName = "data"
	}

	required init?(coder aDecoder: NSCoder) {
		tableName = aDecoder.decodeStringForKey("tableName") ?? "data"
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeString(tableName, forKey: "tableName")
	}

	func writeData(data: Data, toFile file: NSURL, locale: Locale, job: Job, callback: (Fallible<Void>) -> ()) {
		if let p = file.path, let database = QBESQLiteConnection(path: p) {
			// We must disable the WAL because the sandbox doesn't allow us to write to the WAL file (created separately)
			database.query("PRAGMA journal_mode = MEMORY").require { s in
				s.run()

				database.query("DROP TABLE IF EXISTS \(database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))").require { s in
					s.run()
					QBESQLiteWriterSession(data: data, toDatabase: database, tableName: self.tableName).start(job, callback: callback)
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("Could not write to SQLite database file", comment: "")));
		}
	}

	func sentence(locale: Locale) -> QBESentence? {
		return QBESentence(format: NSLocalizedString("(Over)write data to table [#]", comment: ""),
			QBESentenceTextInput(value: self.tableName, callback: { [weak self] (newTableName) -> (Bool) in
				self?.tableName = newTableName
				return true
			})
		)
	}
}

/**
Cache a given Data data set in a SQLite table. Loading the data set into SQLite is performed asynchronously in the
background, and the SQLite-cached data set is swapped with the original one at completion transparently. The cache is
placed in a shared, temporary 'cache' database (sharedCacheDatabase) so that cached tables can efficiently be joined by
SQLite. Users of this class can set a completion callback if they want to wait until caching has finished. */
class QBESQLiteCachedData: ProxyData {
	private let database: QBESQLiteConnection
	private let tableName: String
	private(set) var isCached: Bool = false
	private let mutex = Mutex()
	private let cacheJob: Job
	
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
	
	init(source: Data, job: Job? = nil, completion: ((Fallible<QBESQLiteCachedData>) -> ())? = nil) {
		database = QBESQLiteCachedData.sharedCacheDatabase
		tableName = "cache_\(String.randomStringWithLength(32))"
		self.cacheJob = job ?? Job(.Background)
		super.init(data: source)
		
		QBESQLiteWriterSession(data: source, toDatabase: database, tableName: tableName).start(cacheJob) { (result) -> () in
			switch result {
			case .Success:
				// Swap out the original source with our new cached source
				self.cacheJob.log("Done caching, swapping out")
				self.data.columns(self.cacheJob) { [unowned self] (columns) -> () in
					switch columns {
					case .Success(let cns):
						self.mutex.locked {
							self.data = QBESQLiteData(db: self.database, fragment: SQLFragment(table: self.tableName, schema: nil, database: nil, dialect: self.database.dialect), columns: cns)
							self.isCached = true
						}
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
		self.mutex.locked {
			if !self.isCached {
				cacheJob.cancel()
			}
			else {
				self.database.query("DROP TABLE \(self.database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))")
			}
		}
	}
}

class QBESQLiteDatabase: SQLDatabase {
	let url: NSURL
	let readOnly: Bool
	let dialect: SQLDialect = QBESQLiteDialect()
	let databaseName: String? = nil

	init(url: NSURL, readOnly: Bool) {
		self.url = url
		self.readOnly = readOnly
	}

	func connect(callback: (Fallible<SQLConnection>) -> ()) {
		if let c = QBESQLiteConnection(path: self.url.path!, readOnly: self.readOnly) {
			callback(.Success(c))
		}
		else {
			callback(.Failure("Could not connect to SQLite database"))
		}
	}

	func dataForTable(table: String, schema: String?, job: Job, callback: (Fallible<Data>) -> ()) {
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

class QBESQLiteDataWarehouse: SQLWarehouse {
	override init(database: SQLDatabase, schemaName: String?) {
		super.init(database: database, schemaName: schemaName)
	}

	override func canPerformMutation(mutation: WarehouseMutation) -> Bool {
		switch mutation {
		case .Create(_, _):
			// A read-only database cannot be mutated
			let db = self.database as! QBESQLiteDatabase
			return !db.readOnly
		}
	}
}

class QBESQLiteMutableData: SQLMutableData {
	override var warehouse: Warehouse { return QBESQLiteDataWarehouse(database: self.database, schemaName: self.schemaName) }

	override func identifier(job: Job, callback: (Fallible<Set<Column>?>) -> ()) {
		let s = self.database as! QBESQLiteDatabase
		s.connect { result in
			switch result {
			case .Success(let con):
				let c = con as! QBESQLiteConnection
				switch c.query("PRAGMA table_info(\(s.dialect.tableIdentifier(self.tableName, schema: self.schemaName, database: nil)))") {
				case .Success(let result):
					guard let nameIndex = result.columns.indexOf(Column("name")) else { callback(.Failure("No name column")); return }
					guard let pkIndex = result.columns.indexOf(Column("pk")) else { callback(.Failure("No pk column")); return }

					var identifiers = Set<Column>()
					for row in result.sequence() {
						switch row {
						case .Success(let r):
							if r[pkIndex] == Value(1) {
								// This column is part of the primary key
								if let name = r[nameIndex].stringValue {
									identifiers.insert(Column(name))
								}
								else {
									callback(.Failure("Invalid column name"))
									return
								}
							}

						case .Failure(let e):
							callback(.Failure(e))
							return
						}
					}

					callback(.Success(identifiers))

				case .Failure(let e):
					callback(.Failure(e))
				}

			case .Failure(let e):
				callback(.Failure(e))
			}
		}
	}
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

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
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
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let d = db {
			callback(QBESQLiteData.create(d, tableName: self.tableName ?? "").use({return $0.coalesced}))
		}
		else {
			callback(.Failure(NSLocalizedString("a SQLite database could not be found.", comment: "")))
		}
	}
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.use {(x) -> Data in
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

	override var mutableData: MutableData? {
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
