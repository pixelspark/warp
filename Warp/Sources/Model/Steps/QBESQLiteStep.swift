import Foundation
import WarpCore

private class QBESQLiteResult {
	let resultSet: OpaquePointer
	let db: QBESQLiteConnection
	
	static func create(_ sql: String, db: QBESQLiteConnection) -> Fallible<QBESQLiteResult> {
		assert(sql.lengthOfBytes(using: String.Encoding.utf8) < 1000000, "SQL statement for SQLite too long!")
		var resultSet: OpaquePointer? = nil
		trace("SQL \(sql)")
		if case .failure(let m) = db.perform({sqlite3_prepare_v2(db.db, sql, -1, &resultSet, nil)}) {
			return .failure(m)
		}
		else {
			return .success(QBESQLiteResult(resultSet: resultSet!, db: db))
		}
	}
	
	init(resultSet: OpaquePointer, db: QBESQLiteConnection) {
		self.resultSet = resultSet
		self.db = db
	}
	
	deinit {
		_ = db.perform { sqlite3_finalize(self.resultSet) }
	}
	
	/** Run is used to execute statements that do not return data (e.g. UPDATE, INSERT, DELETE, etc.). It can optionally
	be fed with parameters which will be bound before query execution. */
	func run(_ parameters: [Value]? = nil) -> Fallible<Void> {
		// If there are parameters, bind them
		return self.db.mutex.locked {
			if let p = parameters {
				var i = 0
				for value in p {
					var result = SQLITE_OK
					switch value {
						case .string(let s):
							// This, apparently, is super-slow, because Swift needs to convert its string to UTF-8.
							result = sqlite3_bind_text(self.resultSet, CInt(i+1), s, -1, sqlite3_transient_destructor)
						
						case .int(let x):
							result = sqlite3_bind_int64(self.resultSet, CInt(i+1), sqlite3_int64(x))
						
						case .double(let d):
							result = sqlite3_bind_double(self.resultSet, CInt(i+1), d)
						
						case .date(let d):
							result = sqlite3_bind_double(self.resultSet, CInt(i+1), d)
						
						case .bool(let b):
							result = sqlite3_bind_int(self.resultSet, CInt(i+1), b ? 1 : 0)
						
						case .invalid:
							result = sqlite3_bind_null(self.resultSet, CInt(i+1))
						
						case .empty:
							result = sqlite3_bind_null(self.resultSet, CInt(i+1))
					}
					
					if result != SQLITE_OK {
						return .failure("SQLite error on parameter bind: \(self.db.lastError)")
					}
					
					i += 1
				}
			}
		
			let result = sqlite3_step(self.resultSet)
			if result != SQLITE_ROW && result != SQLITE_DONE {
				return .failure("SQLite error running statement: \(self.db.lastError)")
			}
			
			if sqlite3_clear_bindings(self.resultSet) != SQLITE_OK {
				return .failure("SQLite: failed to clear parameter bindings: \(self.db.lastError)")
			}
			
			if sqlite3_reset(self.resultSet) != SQLITE_OK {
				return .failure("SQLite: could not reset statement: \(self.db.lastError)")
			}

			return .success()
		}
	}
	
	var columnCount: Int { get {
		return self.db.mutex.locked {
			return Int(sqlite3_column_count(self.resultSet))
		}
	} }
	
	 var columns: OrderedSet<Column> { get {
		return self.db.mutex.locked {
			let count = sqlite3_column_count(self.resultSet)
			return OrderedSet((0..<count).map({
				Column(String(cString: sqlite3_column_name(self.resultSet, $0)))
			}))
		}
	} }

	func sequence() -> AnySequence<Fallible<Tuple>> {
		return AnySequence<Fallible<Tuple>>(QBESQLiteResultSequence(result: self))
	}
}

private class QBESQLiteResultSequence: Sequence {
	let result: QBESQLiteResult
	typealias Iterator = QBESQLiteResultGenerator
	
	init(result: QBESQLiteResult) {
		self.result = result
	}
	
	func makeIterator() -> Iterator {
		return QBESQLiteResultGenerator(self.result)
	}
}

private class QBESQLiteResultGenerator: IteratorProtocol {
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
		
		if case .failure(let m) = self.result.db.perform({
			self.lastStatus = sqlite3_step(self.result.resultSet)
			if self.lastStatus == SQLITE_ROW {
				item = .success(self.row)
				return SQLITE_OK
			}
			else if self.lastStatus == SQLITE_DONE {
				return SQLITE_OK
			}
			else {
				item = .failure(self.result.db.lastError)
				return self.lastStatus
			}
		}) {
			return .failure(m)
		}
		
		return item
	}

	var row: Tuple {
		return self.result.db.mutex.locked {
			return (0..<result.columns.count).map { idx in
				switch sqlite3_column_type(self.result.resultSet, Int32(idx)) {
				case SQLITE_FLOAT:
					return Value(sqlite3_column_double(self.result.resultSet, Int32(idx)))
					
				case SQLITE_NULL:
					return Value.empty
					
				case SQLITE_INTEGER:
					// Booleans are represented as integers, but boolean columns are declared as BOOL columns
					let intValue = Int(sqlite3_column_int64(self.result.resultSet, Int32(idx)))

					if let ptr = sqlite3_column_decltype(self.result.resultSet, Int32(idx)) {
						let type = String(cString: ptr)
						if type.hasPrefix("BOOL") {
							return Value(intValue != 0)
						}
						return Value(intValue)
					}
					return Value.invalid
					
				case SQLITE_TEXT:
					if let ptr = UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx))) {
						let string = String(cString: ptr)
						return Value(string)
					}
					return Value.invalid
					
				default:
					return Value.invalid
				}
			}
		}
	}
}

private struct QBESQLiteForeignKey {
	let table: String
	let column: String
	let referencedTable: String
	let referencedColumn: String
}

private class QBESQLiteConnection: NSObject, SQLConnection {
	var url: String?
	let db: OpaquePointer?
	let dialect: SQLDialect = QBESQLiteDialect()
	let presenters: [QBEFilePresenter]

	init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		let url = URL(fileURLWithPath: path, isDirectory: false)
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

		if case .failure(_) = perform({sqlite3_open_v2(path, &self.db, flags, nil) }) {
			return nil
		}

		/* By default, SQLite does not implement various mathematical SQL functions such as SIN, COS, TAN, as well as
		certain aggregates such as STDEV. RegisterExtensionFunctions plugs these into the database. */
		RegisterExtensionFunctions(self.db)

		/* Create the 'WARP_*' user-defined functions in SQLite. When called, it looks up the native implementation of a
		Function/Binary whose raw value name is equal to the first parameter. It applies the function to the other parameters
		and returns the result to SQLite. */
		QBESQLiteConnection.sqliteUDFFunctionName.withCString { udfName in
			QBESQLiteConnection.sqliteUDFBinaryName.withCString { udfBinaryName in
				SQLiteCreateFunction(self.db, udfName, -1, true, QBESQLiteConnection.sqliteUDFFunction)
				SQLiteCreateFunction(self.db, udfBinaryName, 3, true, QBESQLiteConnection.sqliteUDFBinary)
			}
		}
	}

	deinit {
		_ = perform {
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
		 return String(cString: sqlite3_errmsg(self.db)) ?? ""
	}
	
	private func perform(_ op: () -> Int32) -> Fallible<Void> {
		return mutex.locked {
			let code = op()
			if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW {
				return .failure("SQLite error \(code): \(self.lastError)")
			}
			return .success()
		}
	}
	
	private static func sqliteValueToValue(_ value: OpaquePointer) -> Value {
		return self.sharedMutex.locked {
			switch sqlite3_value_type(value) {
				case SQLITE_NULL:
					return Value.empty
				
				case SQLITE_FLOAT:
					return Value.double(sqlite3_value_double(value))
				
				case SQLITE_TEXT:
					if let ptr = UnsafePointer<CChar>(sqlite3_value_text(value)) {
						return Value.string(String(cString: ptr))
					}
					return Value.invalid

				
				case SQLITE_INTEGER:
					return Value.int(Int(sqlite3_value_int64(value)))
				
				default:
					return Value.invalid
			}
		}
	}
	
	private static func sqliteResult(_ context: OpaquePointer, result: Value) {
		return self.sharedMutex.locked {
			switch result {
				case .invalid:
					sqlite3_result_null(context)
					
				case .empty:
					sqlite3_result_null(context)
					
				case .string(let s):
					sqlite3_result_text(context, s, -1, sqlite3_transient_destructor)
					
				case .int(let s):
					sqlite3_result_int64(context, Int64(s))
					
				case .double(let d):
					sqlite3_result_double(context, d)
				
				case .date(let d):
					sqlite3_result_double(context, d)
				
				case .bool(let b):
					sqlite3_result_int64(context, b ? 1 : 0)
			}
		}
	}
	
	private static let sqliteUDFFunctionName = "WARP_FUNCTION"
	private static let sqliteUDFBinaryName = "WARP_BINARY"
	
	/* This function implements the 'WARP_FUNCTION' user-defined function in SQLite. When called, it looks up the native
	implementation of a Function whose raw value name is equal to the first parameter. It applies the function to the
	other parameters and returns the result to SQLite. */
	private static func sqliteUDFFunction(_ context: OpaquePointer?, argc: Int32,  values: UnsafeMutablePointer<OpaquePointer?>?) {
		assert(argc>0, "The Warp UDF should always be called with at least one parameter")
		let functionName = sqliteValueToValue(values![0]!).stringValue!
		let type = Function(rawValue: functionName)!
		assert(type.isDeterministic, "Calling non-deterministic function through SQLite Warp UDF is not allowed")
		
		var args: [Value] = []
		for i in 1..<argc {
			let sqliteValue = values![Int(i)]!
			args.append(sqliteValueToValue(sqliteValue))
		}
		
		let result = type.apply(args)
		sqliteResult(context!, result: result)
	}
	
	/* This function implements the 'WARP_BINARY' user-defined function in SQLite. When called, it looks up the native
	implementation of a Binary whose raw value name is equal to the first parameter. It applies the function to the
	other parameters and returns the result to SQLite. */
	private static func sqliteUDFBinary(_ context: OpaquePointer?, argc: Int32,  values: UnsafeMutablePointer<OpaquePointer?>?) {
		assert(argc==3, "The Warp_binary UDF should always be called with three parameters")
		let functionName = sqliteValueToValue(values![0]!).stringValue!
		let type = Binary(rawValue: functionName)!
		let first = sqliteValueToValue(values![1]!)
		let second = sqliteValueToValue(values![2]!)
		
		let result = type.apply(first, second)
		sqliteResult(context!, result: result)
	}
	
	func query(_ sql: String) -> Fallible<QBESQLiteResult> {
		return QBESQLiteResult.create(sql, db: self)
	}

	func run(_ sql: [String], job: Job, callback: (Fallible<Void>) -> ()) {
		for q in sql {
			switch query(q) {
				case .success(let c):
					if case .failure(let m) = c.run() {
						return callback(.failure(m))
					}

				case .failure(let e):
					return callback(.failure(e))
			}
		}
		return callback(.success())
	}
	
	var tableNames: Fallible<[String]> { get {
		let names = query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC")
		
		return names.use({(ns) -> [String] in
			var nameStrings: [String] = []
			for name in ns.sequence() {
				switch name {
				case .success(let n):
					nameStrings.append(n[0].stringValue!)

				case .failure(_):
					// Ignore
					break
				}

			}
			return nameStrings
		})
	} }

	func foreignKeys(forTable table: String, job: Job, callback: (Fallible<[QBESQLiteForeignKey]>) -> ()) {
		let tableName = self.dialect.expressionToSQL(Literal(Value(table)), alias: "", foreignAlias: nil, inputValue: nil)!
		switch query("PRAGMA foreign_key_list(\(tableName))") {
		case .success(let names):
			let constraints = names.sequence().flatMap { row -> QBESQLiteForeignKey? in
				switch row {
				case .success(let info):
					return QBESQLiteForeignKey(
						table: table,
						column: info[names.columns.index(of: Column("from"))!].stringValue!,
						referencedTable: info[names.columns.index(of: Column("table"))!].stringValue!,
						referencedColumn: info[names.columns.index(of: Column("to"))!].stringValue!
					)

				case .failure(_):
					return nil
				}
			}
			callback(.success(constraints))

		case .failure(let e):
			return callback(.failure(e))
		}
	}
}

private func ==(lhs: QBESQLiteConnection, rhs: QBESQLiteConnection) -> Bool {
	return lhs.db == rhs.db || (lhs.url == rhs.url && lhs.url != nil && rhs.url != nil)
}

private class QBESQLiteDialect: StandardSQLDialect {
	// SQLite does not support changing column definitions using an ALTER statement
	override var supportsChangingColumnDefinitionsWithAlter: Bool { return false }

	// SQLite does not support column names with '"' in them.
	override func columnIdentifier(_ column: Column, table: String?, schema: String?, database: String?) -> String {
		return super.columnIdentifier(Column(column.name.replacingOccurrences(of: "\"", with: "", options: [], range: nil)), table: table, schema: schema, database: database)
	}
	
	override func binaryToSQL(_ type: Binary, first: String, second: String) -> String? {
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
	
	override func unaryToSQL(_ type: Function, args: [String]) -> String? {
		let result: String?
		switch type {
			case .Concat:
				result = args.joined(separator: " || ")
			
			default:
				result = super.unaryToSQL(type, args: args)
		}
		
		if result != nil {
			return result
		}
		
		/* If a function cannot be implemented in SQL, we should fall back to our special UDF function to call into the 
		native implementation */
		let value = args.joined(separator: ", ")
		return "\(QBESQLiteConnection.sqliteUDFFunctionName)('\(type.rawValue)',\(value))"
	}
	
	override func aggregationToSQL(_ aggregation: Aggregator, alias: String) -> String? {
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

class QBESQLiteDataset: SQLDataset {
	private let db: QBESQLiteConnection
	
	static private func create(_ db: QBESQLiteConnection, tableName: String) -> Fallible<QBESQLiteDataset> {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		switch db.query(query) {
			case .success(let result):
				return .success(QBESQLiteDataset(db: db, fragment: SQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: result.columns))
				
			case .failure(let error):
				return .failure(error)
		}
	}
	
	private init(db: QBESQLiteConnection, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}
	
	override func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return QBESQLiteDataset(db: self.db, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> WarpCore.Stream {
		return QBESQLiteStream(data: self) ?? EmptyStream()
	}
	
	private func result() -> Fallible<QBESQLiteResult> {
		return self.db.query(self.sql.sqlSelect(nil).sql)
	}

	override func isCompatibleWith(_ other: SQLDataset) -> Bool {
		if let os = other as? QBESQLiteDataset {
			return os.db == self.db
		}
		return false
	}

	/** SQLite does not support "OFFSET" without a LIMIT clause. It does support "LIMIT -1 OFFSET x". */
	override func offset(_ numberOfRows: Int) -> Dataset {
		return self.apply(sql.sqlLimit("-1").sqlOffset("\(numberOfRows)"), resultingColumns: columns)
	}
}

/**
Stream that lazily queries and streams results from an SQLite query. */
class QBESQLiteStream: WarpCore.Stream {
	private var resultStream: WarpCore.Stream?
	private let data: QBESQLiteDataset
	private let mutex = Mutex()
	
	init(data: QBESQLiteDataset) {
		self.data = data
	}
	
	private func stream() -> WarpCore.Stream {
		return self.mutex.locked {
			if resultStream == nil {
				switch data.result() {
					case .success(let result):
						resultStream = SequenceStream(AnySequence<Fallible<Tuple>>(result.sequence()), columns: result.columns)
						
					case .failure(let error):
						resultStream = ErrorStream(error)
				}
			}
			
			return resultStream!
		}
	}
	
	func fetch(_ job: Job, consumer: Sink) {
		return stream().fetch(job, consumer: consumer)
	}
	
	func columns(_ job: Job, callback: (Fallible<OrderedSet<Column>>) -> ()) {
		return stream().columns(job, callback: callback)
	}
	
	func clone() -> WarpCore.Stream {
		return QBESQLiteStream(data: data)
	}
}

private class QBESQLiteWriterSession {
	private let database: QBESQLiteConnection
	private let tableName: String
	private let source: Dataset

	private var job: Job? = nil
	private var stream: WarpCore.Stream?
	private var insertStatement: QBESQLiteResult?
	private var completion: ((Fallible<Void>) -> ())?

	init(data source: Dataset, toDatabase database: QBESQLiteConnection, tableName: String) {
		self.database = database
		self.tableName = tableName
		self.source = source
	}

	deinit {
		if let j = self.job {
			if j.isCancelled {
				j.log("SQLite ingest job was cancelled, rolling back transaction")
				self.database.query("ROLLBACK").require { c in
					if case .failure(let m) = c.run() {
						j.log("ROLLBACK of SQLite data failed \(m)! not swapping")
					}
				}
			}
		}
	}

	func start(_ job: Job, callback: (Fallible<Void>) -> ()) {
		let dialect = database.dialect
		self.completion = callback
		self.job = job

		job.async {
			self.source.columns(job) { (columns) -> () in
				switch columns {
				case .success(let cns):
					if cns.isEmpty {
						return callback(.failure("Cannot cache data: data set does not contain columns".localized))
					}

					// Create SQL field specifications for the columns
					let columnSpec = cns.map({ (column) -> String in
						let colString = dialect.columnIdentifier(column, table: nil, schema: nil, database: nil)
						return "\(colString) VARCHAR"
					}).joined(separator: ", ")

					// Create destination table
					let sql = "CREATE TABLE \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) (\(columnSpec))"
					switch self.database.query(sql) {
					case .success(let createQuery):
						if case .failure(let m) = createQuery.run() {
							return callback(.failure(m))
						}
						self.stream = self.source.stream()

						// Prepare the insert-statement
						let values = cns.map({(m) -> String in return "?"}).joined(separator: ",")
						switch self.database.query("INSERT INTO \(dialect.tableIdentifier(self.tableName, schema: nil, database: nil)) VALUES (\(values))") {
						case .success(let insertStatement):
							self.insertStatement = insertStatement
							/** SQLite inserts are fastest when they are grouped in a transaction (see docs).
							A transaction is started here and is ended in self.ingest. */
							self.database.query("BEGIN").require { r in
								if case .failure(let m) = r.run() {
									return callback(.failure(m))
								}
								// TODO: use StreamPuller to do this with more threads simultaneously
								self.stream?.fetch(job, consumer: self.ingest)
							}

						case .failure(let error):
							callback(.failure(error))
						}

					case .failure(let error):
						callback(.failure(error))
					}

				case .failure(let error):
					callback(.failure(error))
				}
			}
		}
	}

	private func ingest(_ rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) {
		switch rows {
		case .success(let r):
			if streamStatus == .hasMore && !self.job!.isCancelled {
				self.stream?.fetch(self.job!, consumer: self.ingest)
			}

			job!.time("SQLite insert", items: r.count, itemType: "rows") {
				if let statement = self.insertStatement {
					for row in r {
						if case .failure(let m) = statement.run(row) {
							self.completion!(.failure(m))
							self.completion = nil
							return
						}
					}
				}
			}

			if streamStatus == .finished {
				// First end the transaction started in init
				self.database.query("COMMIT").require { c in
					if case .failure(let m) = c.run() {
						self.job!.log("COMMIT of SQLite data failed \(m)! not swapping")
						self.completion!(.failure(m))
						self.completion = nil
						return
					}
					else {
						self.completion!(.success())
						self.completion = nil
					}
				}
			}

		case .failure(let errMessage):
			// Roll back the transaction that was started in init.
			self.database.query("ROLLBACK").require { c in
				if case .failure(let m) = c.run() {
					self.completion!(.failure("\(errMessage), followed by rollback failure: \(m)"))
				}
				else {
					self.completion!(.failure(errMessage))
				}
				self.completion = nil
			}
		}
	}
}

class QBESQLiteWriter: NSObject, QBEFileWriter, NSCoding {
	var tableName: String

	static func explain(_ fileExtension: String, locale: Language) -> String {
		return NSLocalizedString("SQLite database", comment: "")
	}

	static var fileTypes: Set<String> { get { return Set(["sqlite"]) } }

	required init(locale: Language, title: String?) {
		tableName = "data"
	}

	required init?(coder aDecoder: NSCoder) {
		tableName = aDecoder.decodeString(forKey:"tableName") ?? "data"
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encodeString(tableName, forKey: "tableName")
	}

	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: (Fallible<Void>) -> ()) {
		if let database = QBESQLiteConnection(path: file.path) {
			// We must disable the WAL because the sandbox doesn't allow us to write to the WAL file (created separately)
			database.query("PRAGMA journal_mode = MEMORY").require { s in
				if case .failure(let m) = s.run() {
					return callback(.failure(m))
				}

				database.query("DROP TABLE IF EXISTS \(database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))").require { s in
					if case .failure(let m) = s.run() {
						return callback(.failure(m))
					}
					QBESQLiteWriterSession(data: data, toDatabase: database, tableName: self.tableName).start(job, callback: callback)
				}
			}
		}
		else {
			callback(.failure(NSLocalizedString("Could not write to SQLite database file", comment: "")));
		}
	}

	func sentence(_ locale: Language) -> QBESentence? {
		return QBESentence(format: NSLocalizedString("(Over)write data to table [#]", comment: ""),
			QBESentenceTextInput(value: self.tableName, callback: { [weak self] (newTableName) -> (Bool) in
				self?.tableName = newTableName
				return true
			})
		)
	}
}

private class QBESQLiteSharedCacheDatabase {
	let connection: QBESQLiteConnection

	init() {
		connection = QBESQLiteConnection(path: "", readOnly: false)!
		/** Because this database is created anew, we can set its encoding. As the code reading strings from SQLite
		uses UTF-8, set the database's encoding to UTF-8 so that no unnecessary conversions have to take place. */

		connection.query("PRAGMA encoding = \"UTF-8\"").require { e in
			e.run().require {
				connection.query("PRAGMA synchronous = OFF").require { r in
					r.run().require {
						connection.query("PRAGMA journal_mode = MEMORY").require { s in
							s.run().require {
							}
						}
					}
				}
			}
		}
	}
}

/**
Cache a given Dataset data set in a SQLite table. Loading the data set into SQLite is performed asynchronously in the
background, and the SQLite-cached data set is swapped with the original one at completion transparently. The cache is
placed in a shared, temporary 'cache' database (sharedCacheDatabase) so that cached tables can efficiently be joined by
SQLite. Users of this class can set a completion callback if they want to wait until caching has finished. */
class QBESQLiteCachedDataset: ProxyDataset {
	private static var sharedCacheDatabase = QBESQLiteSharedCacheDatabase()

	private let database: QBESQLiteConnection
	private let tableName: String
	private(set) var isCached: Bool = false
	private let mutex = Mutex()
	private let cacheJob: Job
	
	init(source: Dataset, job: Job? = nil, completion: ((Fallible<QBESQLiteCachedDataset>) -> ())? = nil) {
		database = QBESQLiteCachedDataset.sharedCacheDatabase.connection
		tableName = "cache_\(String.randomStringWithLength(32))"
		self.cacheJob = job ?? Job(.background)
		super.init(data: source)
		
		QBESQLiteWriterSession(data: source, toDatabase: database, tableName: tableName).start(cacheJob) { (result) -> () in
			switch result {
			case .success:
				// Swap out the original source with our new cached source
				self.cacheJob.log("Done caching, swapping out")
				self.data.columns(self.cacheJob) { [unowned self] (columns) -> () in
					switch columns {
					case .success(let cns):
						self.mutex.locked {
							self.data = QBESQLiteDataset(db: self.database, fragment: SQLFragment(table: self.tableName, schema: nil, database: nil, dialect: self.database.dialect), columns: cns)
							self.isCached = true
						}
						completion?(.success(self))

					case .failure(let error):
						completion?(.failure(error))
					}
				}
			case .failure(let e):
				completion?(.failure(e))
			}
		}
	}

	deinit {
		self.mutex.locked {
			if !self.isCached {
				cacheJob.cancel()
			}
			else {
				if case .failure(let m) = self.database.query("DROP TABLE \(self.database.dialect.tableIdentifier(self.tableName, schema: nil, database: nil))") {
					trace("failure dropping table in deinitializer: \(m)")
				}
			}
		}
	}
}

class QBESQLiteDatabase: SQLDatabase {
	let url: URL
	let readOnly: Bool
	let dialect: SQLDialect = QBESQLiteDialect()
	let databaseName: String? = nil

	init(url: URL, readOnly: Bool) {
		self.url = url
		self.readOnly = readOnly
	}

	func connect(_ callback: (Fallible<SQLConnection>) -> ()) {
		if let c = QBESQLiteConnection(path: self.url.path, readOnly: self.readOnly) {
			callback(.success(c))
		}
		else {
			callback(.failure("Could not connect to SQLite database"))
		}
	}

	func dataForTable(_ table: String, schema: String?, job: Job, callback: (Fallible<Dataset>) -> ()) {
		if schema != nil {
			callback(.failure("SQLite does not support schemas"))
			return
		}

		if let con = QBESQLiteConnection(path: self.url.path, readOnly: self.readOnly) {
			switch QBESQLiteDataset.create(con, tableName: table) {
			case .success(let d): callback(.success(d))
			case .failure(let e): callback(.failure(e))
			}
		}
		else {
			callback(.failure("Could not connect to SQLite database"))
		}
	}
}

class QBESQLiteDatasetWarehouse: SQLWarehouse {
	override init(database: SQLDatabase, schemaName: String?) {
		super.init(database: database, schemaName: schemaName)
	}

	override func canPerformMutation(_ mutation: WarehouseMutation) -> Bool {
		switch mutation {
		case .create(_, _):
			// A read-only database cannot be mutated
			let db = self.database as! QBESQLiteDatabase
			return !db.readOnly
		}
	}
}

class QBESQLiteMutableDataset: SQLMutableDataset {
	override var warehouse: Warehouse { return QBESQLiteDatasetWarehouse(database: self.database, schemaName: self.schemaName) }

	override func identifier(_ job: Job, callback: (Fallible<Set<Column>?>) -> ()) {
		let s = self.database as! QBESQLiteDatabase
		s.connect { result in
			switch result {
			case .success(let con):
				let c = con as! QBESQLiteConnection
				switch c.query("PRAGMA table_info(\(s.dialect.tableIdentifier(self.tableName, schema: self.schemaName, database: nil)))") {
				case .success(let result):
					guard let nameIndex = result.columns.index(of: Column("name")) else { callback(.failure("No name column")); return }
					guard let pkIndex = result.columns.index(of: Column("pk")) else { callback(.failure("No pk column")); return }

					var identifiers = Set<Column>()
					for row in result.sequence() {
						switch row {
						case .success(let r):
							if r[pkIndex] == Value(1) {
								// This column is part of the primary key
								if let name = r[nameIndex].stringValue {
									identifiers.insert(Column(name))
								}
								else {
									callback(.failure("Invalid column name"))
									return
								}
							}

						case .failure(let e):
							callback(.failure(e))
							return
						}
					}

					callback(.success(identifiers))

				case .failure(let e):
					callback(.failure(e))
				}

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}
}

/** Usually, an example data set provides a random sample of a source data set. For SQL data sets, this means that we
select randomly rows from the table. This however implies a full table scan. This class wraps around a full SQL data set
to provide an example data set where certain operations are applied to the original rather than the samples data set,
for efficiency. */
class QBESQLiteExampleDataset: ProxyDataset {
	let maxInputRows: Int
	let maxOutputRows: Int
	let fullData: Dataset

	init(data: Dataset, maxInputRows: Int, maxOutputRows: Int) {
		self.maxInputRows = maxInputRows
		self.maxOutputRows = maxOutputRows
		self.fullData = data
		super.init(data: data.random(maxInputRows))
	}

	override func unique(_ expression: Expression, job: Job, callback: (Fallible<Set<Value>>) -> ()) {
		return fullData.unique(expression, job: job, callback: callback)
	}

	override func filter(_ condition: Expression) -> Dataset {
		return fullData.filter(condition).random(max(maxInputRows, maxOutputRows))
	}
}

class QBESQLiteSourceStep: QBEStep {
	var file: QBEFileReference? = nil { didSet {
		oldValue?.url?.stopAccessingSecurityScopedResource()
		if let b = file?.url?.startAccessingSecurityScopedResource(), !b {
			trace("startAccessingSecurityScopedResource failed for \(file!.url!)")
		}
		switchDatabase()
	} }
	
	var tableName: String? = nil
	private var db: QBESQLiteConnection? = nil

	required init() {
		super.init()
	}
	
	init?(url: URL) {
		self.file = QBEFileReference.absolute(url)
		super.init()
		switchDatabase()
	}

	init(file: QBEFileReference) {
		self.file = file
		super.init()
		switchDatabase()
	}

	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	private func switchDatabase() {
		self.db = nil
		
		if let url = file?.url {
			self.db = QBESQLiteConnection(path: url.path, readOnly: true)
			
			if self.tableName == nil {
				self.db?.tableNames.maybe {(tns) in
					self.tableName = tns.first
				}
			}
		}
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let fileSentenceItem = QBESentenceFile(file: self.file, allowedFileTypes: ["org.sqlite.v3"], canCreate: true, callback: { [weak self] (newFile) -> () in
			// If a file was selected that does not exist yet, create a new database
			var error: NSError? = nil
			if let url = newFile.url, !(url as NSURL).checkResourceIsReachableAndReturnError(&error) {
				let db = QBESQLiteDatabase(url: url as URL, readOnly: false)
				db.connect { result in
					switch result {
					case .success(_): break
					case .failure(let e):
						Swift.print("Failed to create SQLite database at \(url): \(e)")
					}
				}
			}

			self?.file = newFile
		})

		if self.file == nil {
			let template: String
			switch variant {
			case .read, .neutral: template = "Load data from SQLite database [#]"
			case .write: template = "Write to SQLite database [#]"
			}
			return QBESentence(format: NSLocalizedString(template, comment: ""), fileSentenceItem)
		}
		else {
			let template: String
			switch variant {
			case .read, .neutral: template = "Load table [#] from SQLite database [#]"
			case .write: template = "Write to table [#] in SQLite database [#]"
			}

			return QBESentence(format: NSLocalizedString(template, comment: ""),
				QBESentenceList(value: self.tableName ?? "", provider: { [weak self] (cb) -> () in
					if let d = self?.db {
						cb(d.tableNames)
					}
				}, callback: { [weak self] (newTable) -> () in
					self?.tableName = newTable
				}),
				fileSentenceItem
			)
		}
	}
	
	override func fullDataset(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		if let d = db {
			callback(QBESQLiteDataset.create(d, tableName: self.tableName ?? "").use({return $0.coalesced}))
		}
		else {
			callback(.failure("The SQLite database could not be opened.".localized))
		}
	}

	override func related(job: Job, callback: (Fallible<[QBERelatedStep]>) -> ()) {
		if let d = db, let file = self.file, let tn = self.tableName, !tn.isEmpty {
			d.foreignKeys(forTable: tn, job: job) { result in
				switch result {
				case .success(let fkeys):
					let steps = fkeys.map { fkey -> QBERelatedStep in
						let s = QBESQLiteSourceStep(file: file)
						s.tableName = fkey.referencedTable
						return QBERelatedStep.joinable(step: s, type: .LeftJoin, condition: Comparison(first: Sibling(Column(fkey.column)), second: Foreign(Column(fkey.referencedColumn)), type: .Equal))
					}
					return callback(.success(steps))

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			callback(fd.use {(x) -> Dataset in
				return QBESQLiteExampleDataset(data: x, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows)
			})
		})
	}
	
	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? ""
		
		let u = aDecoder.decodeObject(forKey: "fileURL") as? URL
		let b = aDecoder.decodeObject(forKey: "fileBookmark") as? Data
		self.file = QBEFileReference.create(u, b)
		super.init(coder: aDecoder)
		
		if let url = u {
			if !url.startAccessingSecurityScopedResource() {
				trace("startAccessingSecurityScopedResource failed for \(url)")
			}
			self.db = QBESQLiteConnection(path: url.path, readOnly: true)
		}
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(file?.url, forKey: "fileURL")
		coder.encode(file?.bookmark, forKey: "fileBookmark")
		coder.encode(tableName, forKey: "tableName")
	}
	
	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}

	var warehouse: Warehouse? {
		if let u = self.file?.url {
			return QBESQLiteDatasetWarehouse(database: QBESQLiteDatabase(url: u, readOnly: false), schemaName: nil)
		}
		return nil
	}

	override var mutableDataset: MutableDataset? {
		if let u = self.file?.url, let tn = tableName {
			return QBESQLiteMutableDataset(database: QBESQLiteDatabase(url: u, readOnly: false), schemaName: nil, tableName: tn)
		}
		return nil
	}
	
	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
		if let url = self.file?.url {
			if !url.startAccessingSecurityScopedResource() {
				trace("startAccessingSecurityScopedResource failed for \(url)")
			}
			self.db = QBESQLiteConnection(path: url.path, readOnly: true)
		}
	}
}
