/* Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
import Foundation
import WarpCore

public class SQLiteResult {
	let resultSet: OpaquePointer
	let db: SQLiteConnection

	public static func create(_ sql: String, db: SQLiteConnection) -> Fallible<SQLiteResult> {
		assert(sql.lengthOfBytes(using: String.Encoding.utf8) < 1000000, "SQL statement for SQLite too long!")
		var resultSet: OpaquePointer? = nil
		trace("SQL \(sql)")
		let dbPointer = db.db!
		let result = db.perform({ () -> Int32 in
			return sqlite3_prepare_v2(dbPointer, sql, -1, &resultSet, nil)
		})

		if case .failure(let m) = result {
			return .failure(m)
		}
		else {
			return .success(SQLiteResult(resultSet: resultSet!, db: db))
		}
	}

	init(resultSet: OpaquePointer, db: SQLiteConnection) {
		self.resultSet = resultSet
		self.db = db
	}

	deinit {
		_ = db.perform { () -> Int32 in
			return sqlite3_finalize(self.resultSet)
		}
	}

	/** Run is used to execute statements that do not return data (e.g. UPDATE, INSERT, DELETE, etc.). It can optionally
	be fed with parameters which will be bound before query execution. */
	public func run(_ parameters: [Value]? = nil) -> Fallible<Void> {
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

	public var columnCount: Int {
		return self.db.mutex.locked {
			return Int(sqlite3_column_count(self.resultSet))
		}
	}

	public var columns: OrderedSet<Column> {
		return self.db.mutex.locked {
			let count = sqlite3_column_count(self.resultSet)
			return OrderedSet((0..<count).map({
				Column(String(cString: sqlite3_column_name(self.resultSet, $0)))
			}))
		}
	}

	func sequence() -> AnySequence<Fallible<Tuple>> {
		return AnySequence<Fallible<Tuple>>(SQLiteResultSequence(result: self))
	}
}

private class SQLiteResultSequence: Sequence {
	let result: SQLiteResult
	typealias Iterator = SQLiteResultGenerator

	init(result: SQLiteResult) {
		self.result = result
	}

	func makeIterator() -> Iterator {
		return SQLiteResultGenerator(self.result)
	}
}

private class SQLiteResultGenerator: IteratorProtocol {
	typealias Element = Fallible<Tuple>
	let result: SQLiteResult
	var lastStatus: Int32 = SQLITE_OK

	init(_ result: SQLiteResult) {
		self.result = result
	}

	func next() -> Element? {
		if lastStatus == SQLITE_DONE {
			return nil
		}

		var item: Element? = nil

		if case .failure(let m) = self.result.db.perform({ () -> Int32 in
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
					if let ptr = sqlite3_column_text(self.result.resultSet, Int32(idx)) {
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

public  struct SQLiteForeignKey {
	public let table: String
	public let column: String
	public let referencedTable: String
	public let referencedColumn: String
}

open class SQLiteConnection: NSObject, SQLConnection {
	fileprivate static let sqliteUDFFunctionName = "WARP_FUNCTION"
	fileprivate static let sqliteUDFBinaryName = "WARP_BINARY"

	public private(set) var url: String?
	public let db: OpaquePointer?
	public let dialect: SQLDialect = SQLiteDialect()

	private static let sharedMutex = Mutex()
	private let ownMutex = Mutex()

	public init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		let url = URL(fileURLWithPath: path, isDirectory: false)
		self.url = url.absoluteString

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
		SQLiteConnection.sqliteUDFFunctionName.withCString { udfName in
			SQLiteConnection.sqliteUDFBinaryName.withCString { udfBinaryName in
				SQLiteCreateFunction(self.db, udfName, -1, true, SQLiteConnection.sqliteUDFFunction)
				SQLiteCreateFunction(self.db, udfBinaryName, 3, true, SQLiteConnection.sqliteUDFBinary)
			}
		}
	}

	deinit {
		_ = perform {
			sqlite3_close(self.db)
		}
	}

	fileprivate var mutex: Mutex { get {
		switch sqlite3_threadsafe() {
		case 0:
			/* SQLite was compiled without any form of thread-safety, so all requests to it need to go through the
			shared SQLite queue */
			return SQLiteConnection.sharedMutex

		default:
			/* SQLite is (at least) thread safe (i.e. a single connection may be used by a single thread; concurrently
			other threads may use different connections). */
			return ownMutex
		}
		} }


	fileprivate var lastError: String {
		return String(cString: sqlite3_errmsg(self.db))
	}

	fileprivate func perform(_ op: () -> Int32) -> Fallible<Void> {
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
				let ptr = sqlite3_value_text(value)
				if ptr != nil {
					return Value.string(String(cString: ptr!))
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

	public func query(_ sql: String) -> Fallible<SQLiteResult> {
		return SQLiteResult.create(sql, db: self)
	}

	public func run(_ sql: [String], job: Job, callback: (Fallible<Void>) -> ()) {
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

	public var tableNames: Fallible<[String]> {
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
	}

	public func foreignKeys(forTable table: String, job: Job, callback: (Fallible<[SQLiteForeignKey]>) -> ()) {
		let tableName = self.dialect.expressionToSQL(Literal(Value(table)), alias: "", foreignAlias: nil, inputValue: nil)!
		switch query("PRAGMA foreign_key_list(\(tableName))") {
		case .success(let names):
			let constraints = names.sequence().flatMap { row -> SQLiteForeignKey? in
				switch row {
				case .success(let info):
					return SQLiteForeignKey(
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

private func ==(lhs: SQLiteConnection, rhs: SQLiteConnection) -> Bool {
	return lhs.db == rhs.db || (lhs.url == rhs.url && lhs.url != nil && rhs.url != nil)
}

private class SQLiteDialect: StandardSQLDialect {
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
		case .containsString: result = "INSTR(LOWER(\(second)), LOWER(\(first)))>0"
		case .containsStringStrict: result = "INSTR(\(second), \(first))>0"
		case .matchesRegex: result = nil // Force usage of UDF here, SQLite does not implement (a REGEXP p)
		case .matchesRegexStrict: result = nil
		case .concatenation: result = "(\(second) || \(first))"

		default:
			result = super.binaryToSQL(type, first: first, second: second)
		}

		/* If a binary expression cannot be represented in 'normal' SQL, we can always use the special UDF function to
		call into the native implementation */
		if result == nil {
			return "\(SQLiteConnection.sqliteUDFBinaryName)('\(type.rawValue)',\(second), \(first))"
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
		return "\(SQLiteConnection.sqliteUDFFunctionName)('\(type.rawValue)',\(value))"
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

public class SQLiteDataset: SQLDataset {
	private let db: SQLiteConnection

	static public func create(_ db: SQLiteConnection, tableName: String) -> Fallible<SQLiteDataset> {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: nil, database: nil))"
		switch db.query(query) {
		case .success(let result):
			return .success(SQLiteDataset(db: db, fragment: SQLFragment(table: tableName, schema: nil, database: nil, dialect: db.dialect), columns: result.columns))

		case .failure(let error):
			return .failure(error)
		}
	}

	public init(db: SQLiteConnection, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}

	override public func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return SQLiteDataset(db: self.db, fragment: fragment, columns: resultingColumns)
	}

	override public func stream() -> WarpCore.Stream {
		return SQLiteStream(data: self)
	}

	fileprivate func result() -> Fallible<SQLiteResult> {
		return self.db.query(self.sql.sqlSelect(nil).sql)
	}

	override public func isCompatibleWith(_ other: SQLDataset) -> Bool {
		if let os = other as? SQLiteDataset {
			return os.db == self.db
		}
		return false
	}

	/** SQLite does not support "OFFSET" without a LIMIT clause. It does support "LIMIT -1 OFFSET x". */
	override public func offset(_ numberOfRows: Int) -> Dataset {
		return self.apply(sql.sqlLimit("-1").sqlOffset("\(numberOfRows)"), resultingColumns: columns)
	}
}

/**
Stream that lazily queries and streams results from an SQLite query. */
public class SQLiteStream: WarpCore.Stream {
	private var resultStream: WarpCore.Stream?
	private let data: SQLiteDataset
	private let mutex = Mutex()

	fileprivate init(data: SQLiteDataset) {
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

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		return stream().fetch(job, consumer: consumer)
	}

	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		return stream().columns(job, callback: callback)
	}

	public func clone() -> WarpCore.Stream {
		return SQLiteStream(data: data)
	}
}

public class SQLiteDatabase: SQLDatabase {
	public let url: URL
	public let readOnly: Bool
	public let dialect: SQLDialect = SQLiteDialect()
	public let databaseName: String? = nil

	public init(url: URL, readOnly: Bool) {
		self.url = url
		self.readOnly = readOnly
	}

	public func connect(_ callback: (Fallible<SQLConnection>) -> ()) {
		if let c = SQLiteConnection(path: self.url.path, readOnly: self.readOnly) {
			callback(.success(c))
		}
		else {
			callback(.failure("Could not connect to SQLite database"))
		}
	}

	public func dataForTable(_ table: String, schema: String?, job: Job, callback: (Fallible<Dataset>) -> ()) {
		if schema != nil {
			callback(.failure("SQLite does not support schemas"))
			return
		}

		if let con = SQLiteConnection(path: self.url.path, readOnly: self.readOnly) {
			switch SQLiteDataset.create(con, tableName: table) {
			case .success(let d): callback(.success(d))
			case .failure(let e): callback(.failure(e))
			}
		}
		else {
			callback(.failure("Could not connect to SQLite database"))
		}
	}
}

public class SQLiteDatasetWarehouse: SQLWarehouse {
	override public init(database: SQLDatabase, schemaName: String?) {
		super.init(database: database, schemaName: schemaName)
	}

	override public func canPerformMutation(_ mutation: WarehouseMutation) -> Bool {
		switch mutation {
		case .create(_, _):
			// A read-only database cannot be mutated
			let db = self.database as! SQLiteDatabase
			return !db.readOnly
		}
	}
}

public class SQLiteMutableDataset: SQLMutableDataset {
	override public var warehouse: Warehouse { return SQLiteDatasetWarehouse(database: self.database, schemaName: self.schemaName) }

	override public func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		let s = self.database as! SQLiteDatabase
		s.connect { result in
			switch result {
			case .success(let con):
				let c = con as! SQLiteConnection
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
