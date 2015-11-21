import Foundation
import WarpCore

/**
Implementation of the PostgreSQL 'SQL dialect'. Only deviatons from the standard dialect are implemented here. */
private class QBEPostgresDialect: QBEStandardSQLDialect {
	override var identifierQualifier: String { get { return  "\"" } }
	override var identifierQualifierEscape: String { get { return  "\\\"" } }
	
	private override func unaryToSQL(type: QBEFunction, args: [String]) -> String? {
		switch type {
			case .Random:
				return "RANDOM()"
			
			default:
				return super.unaryToSQL(type, args: args)
		}
	}
	
	private override func aggregationToSQL(aggregation: QBEAggregation, alias: String) -> String? {
		// For QBEFunction.Count, we should count numeric values only. In PostgreSQL this can be done using REGEXP
		if aggregation.reduce == QBEFunction.Count {
			if let expressionSQL = expressionToSQL(aggregation.map, alias: alias) {
				return "SUM(CASE WHEN \(expressionSQL) REGEXP '^[[:digit:]]+$') THEN 1 ELSE 0 END)"
			}
			return nil
		}
		
		return super.aggregationToSQL(aggregation, alias: alias)
	}
	
	private override func binaryToSQL(type: QBEBinary, first: String, second: String) -> String? {
		switch type {
			case .MatchesRegex: return "(\(forceStringExpression(second)) ~* \(forceStringExpression(first)))"
			case .MatchesRegexStrict: return "(\(forceStringExpression(second)) ~ \(forceStringExpression(first)))"
			default: return super.binaryToSQL(type, first: first, second: second)
		}
	}
	
	private override func forceStringExpression(expression: String) -> String {
		return "CAST(\(expression) AS VARCHAR)"
	}
	
	private override func forceNumericExpression(expression: String) -> String {
		return "CAST(\(expression) AS DECIMAL)"
	}
}

internal class QBEPostgresResult: SequenceType, GeneratorType {
	typealias Element = QBEFallible<QBETuple>
	typealias Generator = QBEPostgresResult
	
	private let connection: QBEPostgresConnection
	private var result: COpaquePointer
	private let columnNames: [QBEColumn]
	private let columnTypes: [Oid]
	private(set) var finished = false
	private(set) var error: String? = nil
	
	/* The following lists OIDs for PostgreSQL system types. This was generated using the following query on a vanilla
	Postgres installation (much less hassle than using the pg_type.h header...):
	SELECT 'private static let kType' || initcap(typname) || ' : Oid = ' || oid FROM pg_type WHERE typbyval */
	private static let kTypeBool : Oid = 16
	private static let kTypeChar : Oid = 18
	private static let kTypeInt8 : Oid = 20
	private static let kTypeInt2 : Oid = 21
	private static let kTypeInt4 : Oid = 23
	private static let kTypeRegproc : Oid = 24
	private static let kTypeOid : Oid = 26
	private static let kTypeXid : Oid = 28
	private static let kTypeCid : Oid = 29
	private static let kTypeSmgr : Oid = 210
	private static let kTypeFloat4 : Oid = 700
	private static let kTypeFloat8 : Oid = 701
	private static let kTypeAbstime : Oid = 702
	private static let kTypeReltime : Oid = 703
	private static let kTypeMoney : Oid = 790
	private static let kTypeDate : Oid = 1082
	private static let kTypeTime : Oid = 1083
	private static let kTypeTimestamp : Oid = 1114
	private static let kTypeTimestamptz : Oid = 1184
	private static let kTypeRegprocedure : Oid = 2202
	private static let kTypeRegoper : Oid = 2203
	private static let kTypeRegoperator : Oid = 2204
	private static let kTypeRegclass : Oid = 2205
	private static let kTypeRegtype : Oid = 2206
	private static let kTypeRegconfig : Oid = 3734
	private static let kTypeRegdictionary : Oid = 3769
	private static let kTypeAny : Oid = 2276
	private static let kTypeVoid : Oid = 2278
	private static let kTypeTrigger : Oid = 2279
	private static let kTypeEvent_Trigger : Oid = 3838
	private static let kTypeLanguage_Handler : Oid = 2280
	private static let kTypeInternal : Oid = 2281
	private static let kTypeOpaque : Oid = 2282
	private static let kTypeAnyelement : Oid = 2283
	private static let kTypeAnynonarray : Oid = 2776
	private static let kTypeAnyenum : Oid = 3500
	private static let kTypeFdw_Handler : Oid = 3115
	private static let kTypeCardinal_Number : Oid = 11761
	private static let kTypeTime_Stamp : Oid = 11768
	
	static func create(connection: QBEPostgresConnection) -> QBEFallible<QBEPostgresResult> {
		// Get column names from result set
		var resultFallible: QBEFallible<QBEPostgresResult> = .Failure("Unknown error")
		
		dispatch_sync(connection.queue) {
			let result = PQgetResult(connection.connection)

			if result == nil {
				resultFallible = .Failure(connection.lastError)
			}
			else {
				let status = PQresultStatus(result)
				if status.rawValue != PGRES_TUPLES_OK.rawValue && status.rawValue != PGRES_SINGLE_TUPLE.rawValue && status.rawValue != PGRES_COMMAND_OK.rawValue {
					resultFallible = .Failure(connection.lastError)

					// On error, call PQgetresult anyway to ensure that the command has fully finished
					while PQgetResult(connection.connection) != nil {
						QBELog("Extraneous result!")
					}
					return
				}

				if status.rawValue == PGRES_COMMAND_OK.rawValue {
					// This result code indicates our command completed successfully. There is no data, so no need to enumerate columns, etc.
					resultFallible = .Success(QBEPostgresResult(connection: connection, result: result, columnNames: [], columnTypes: []))

					// On PGRES_COMMAND_OK, call PQgetresult anyway to ensure that the command has fully finished
					while PQgetResult(connection.connection) != nil {
						QBELog("Extraneous result!")
					}
					return
				}
				
				var columnNames: [QBEColumn] = []
				var columnTypes: [Oid] = []
				
				let colCount = PQnfields(result)
				for colIndex in 0..<colCount {
					let column = PQfname(result, colIndex)
					if column != nil {
						if let name = NSString(bytes: column, length: Int(strlen(column)), encoding: NSUTF8StringEncoding) {
							columnNames.append(QBEColumn(String(name)))
							let type = PQftype(result, colIndex)
							columnTypes.append(type)
						}
						else {
							resultFallible = .Failure(NSLocalizedString("PostgreSQL returned an invalid column name.", comment: ""))
							return
						}
					}
					else {
						resultFallible = .Failure(NSLocalizedString("PostgreSQL returned an invalid column.", comment: ""))
						return
					}
				}
				
				resultFallible = .Success(QBEPostgresResult(connection: connection, result: result, columnNames: columnNames, columnTypes: columnTypes))
			}
		}
		
		return resultFallible
	}
	
	private init(connection: QBEPostgresConnection, result: COpaquePointer, columnNames: [QBEColumn], columnTypes: [Oid]) {
		self.connection = connection
		self.result = result
		self.columnNames = columnNames
		self.columnTypes = columnTypes
	}
	
	func finish() {
		_finish(false)
	}
	
	private func _finish(warn: Bool) {
		if !self.finished {
			/* A new query cannot be started before all results from the previous one have been fetched, because packets
			will get out of order. */
			var n = 0
			while let r = self.row() {
				if case .Failure(let e) = r {
					#if DEBUG
						if warn {
							QBELog("Unfinished result was destroyed, drained \(n) rows to prevent packet errors, errored \(e). This is a performance issue!")
						}
					#endif
					self.finished = true
					return
				}
				++n
			}
			
			#if DEBUG
				if warn && n > 0 {
					QBELog("Unfinished result was destroyed, drained \(n) rows to prevent packet errors. This is a performance issue!")
				}
			#endif
			self.finished = true
		}
	}
	
	deinit {
		_finish(true)
	}
	
	func generate() -> Generator {
		return self
	}
	
	func next() -> Element? {
		return row()
	}
	
	func row() -> QBEFallible<QBETuple>? {
		var rowData: [QBEValue]? = nil
		
		dispatch_sync(self.connection.queue) {
			if self.result == nil {
				self.result = PQgetResult(self.connection.connection)
			}
			
			// Because we are in single-row mode, each result set should only contain a single tuple.
			if self.result != nil {
				if PQntuples(self.result) == 1 && PQresultStatus(self.result).rawValue == PGRES_SINGLE_TUPLE.rawValue {
					rowData = []
					rowData!.reserveCapacity(self.columnNames.count)
					
					for colIndex in 0..<self.columnNames.count {
						let val = PQgetvalue(self.result, Int32(0), Int32(colIndex))
						if val == nil {
							rowData!.append(QBEValue.InvalidValue)
						}
						else if PQgetisnull(self.result, Int32(0), Int32(colIndex)) == 1 {
							rowData!.append(QBEValue.EmptyValue)
						}
						else {
							if let stringValue = NSString(bytes: val, length: Int(strlen(val)), encoding: NSUTF8StringEncoding) {
								let type = PQftype(self.result, Int32(colIndex))
								if type == QBEPostgresResult.kTypeInt8 || type == QBEPostgresResult.kTypeInt4 || type == QBEPostgresResult.kTypeInt2 {
									rowData!.append(QBEValue.IntValue(stringValue.integerValue))
								}
								else if type == QBEPostgresResult.kTypeFloat4 || type == QBEPostgresResult.kTypeFloat8 {
									rowData!.append(QBEValue.DoubleValue(stringValue.doubleValue))
								}
								else if type == QBEPostgresResult.kTypeBool {
									rowData!.append(QBEValue.BoolValue(stringValue == "t"))
								}
								else {
									rowData!.append(QBEValue.StringValue(stringValue as String))
								}
							}
							else {
								rowData!.append(QBEValue.EmptyValue)
							}
						}
					}
				}
				else {
					self.finished = true
					if PQresultStatus(self.result).rawValue != PGRES_TUPLES_OK.rawValue {
						let status = String(CString: PQresStatus(PQresultStatus(self.result)), encoding: NSUTF8StringEncoding) ?? "(unknown status)"
						let error = String(CString: PQresultErrorMessage(self.result), encoding: NSUTF8StringEncoding) ?? "(unknown error)"
						self.error = error
						QBELog("PostgreSQL no result: \(status) \(error)")
					}
				}
				
				// Free the result
				PQclear(self.result)
				self.result = nil
			}
			else {
				self.finished = true
			}
		}

		if let e = self.error {
			return .Failure(e)
		}
		else if let r = rowData {
			return .Success(r)
		}
		else {
			return nil
		}
	}
}

class QBEPostgresDatabase: QBESQLDatabase {
	private let host: String
	private let port: Int
	private let user: String
	private let password: String
	private let database: String

	let dialect: QBESQLDialect = QBEPostgresDialect()
	var databaseName: String? { return self.database }
	
	init(host: String, port: Int, user: String, password: String, database: String) {
		self.host = host
		self.port = port
		self.user = user
		self.password = password
		self.database = database
	}
	
	func isCompatible(other: QBEPostgresDatabase) -> Bool {
		return self.host == other.host && self.user == other.user && self.password == other.password && self.port == other.port
	}

	func dataForTable(table: String, schema: String?, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		switch QBEPostgresData.create(database: self, tableName: table, schemaName: schema ?? "", locale: nil) {
		case .Success(let d): callback(.Success(d))
		case .Failure(let e): callback(.Failure(e))
		}
	}
	
	func databases(callback: (QBEFallible<[String]>) -> ()) {
		let sql = "SELECT datname FROM pg_catalog.pg_database WHERE NOT datistemplate"
		callback(self.connect().use {
			$0.query(sql).use {(result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .Success(let infoRow) = d {
						if let name = infoRow[0].stringValue {
							dbs.append(name)
						}
					}
				}
				return dbs
			}
		})
	}
	
	func tables(databaseName: String, schemaName: String, callback: (QBEFallible<[String]>) -> ()) {
		let ts = self.dialect.expressionToSQL(QBELiteralExpression(QBEValue(schemaName)), alias: "s", foreignAlias: nil, inputValue: nil)!
		let tc = self.dialect.expressionToSQL(QBELiteralExpression(QBEValue(databaseName)), alias: "s", foreignAlias: nil, inputValue: nil)!

		let sql = "SELECT table_name FROM information_schema.tables t WHERE t.table_schema = \(ts)  AND t.table_catalog = \(tc)"
		callback(self.connect().use {
			$0.query(sql).use { (result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .Success(let infoRow) = d {
						if let tableName = infoRow[0].stringValue {
							dbs.append(tableName)
						}
					}
				}
				return dbs
			}
		})
	}

	/** Fetches the server information string (containing version number and other useful information). This is mostly
	used to check whether a connection can be made. */
	func serverInformation(callback: (QBEFallible<String>) -> ()) {
		switch self.connect() {
		case .Success(let con):
			switch con.query("SELECT version()") {
			case .Success(let result):
				if let rowFallible = result.row() {
					switch rowFallible {
					case .Success(let row):
						if let version = row.first?.stringValue {
							callback(.Success(version))
						}
						else {
							callback(.Failure("No or invalid version string returned"))
						}

					case .Failure(let e):
						callback(.Failure(e))
					}
				}
				else {
					callback(.Failure("No version returned"))
				}

			case .Failure(let e): callback(.Failure(e))
			}

		case .Failure(let e): callback(.Failure(e))
		}
	}

	func schemas(databaseName: String, callback: (QBEFallible<[String]>) -> ()) {
		let cn = self.dialect.expressionToSQL(QBELiteralExpression(QBEValue(databaseName)), alias: "s", foreignAlias: nil, inputValue: nil)!
		let sql = "SELECT s.schema_name FROM information_schema.schemata s WHERE catalog_name=\(cn)"
		callback(self.connect().use {
			$0.query(sql).use { (result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .Success(let infoRow) = d {
						if let schemaName = infoRow[0].stringValue {
							dbs.append(schemaName)
						}
					}
				}
				return dbs
			}
		})
	}

	func connect(callback: (QBEFallible<QBESQLConnection>) -> ()) {
		callback(self.connect().use { return $0 })
	}

	func connect() -> QBEFallible<QBEPostgresConnection> {
		let userEscaped = self.user.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLUserAllowedCharacterSet())!
		let passwordEscaped = self.password.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLPasswordAllowedCharacterSet())!
		let hostEscaped = self.host.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!
		let databaseEscaped = self.database.isEmpty ? "" : ("/"+(self.database.urlEncoded ?? ""))
		let url = "postgres://\(userEscaped):\(passwordEscaped)@\(hostEscaped):\(self.port)\(databaseEscaped)"
		
		let connection = PQconnectdb(url)
		
		switch PQstatus(connection).rawValue {
			case CONNECTION_OK.rawValue:
				return .Success(QBEPostgresConnection(database: self, connection: connection))
			
			case CONNECTION_BAD.rawValue:
				let error = String(CString:  PQerrorMessage(connection), encoding: NSUTF8StringEncoding) ?? "(unknown error)"
				return .Failure(error)
				
			default:
				return .Failure(String(format: NSLocalizedString("Unknown connection status: %d", comment: ""), PQstatus(connection).rawValue))
		}
	}
}

/**
Implements a connection to a PostgreSQL database (corresponding to a MYSQL object in the PostgreSQL library). The connection ensures
that any operations are serialized (for now using a global queue for all PostgreSQL operations). */
internal class QBEPostgresConnection: QBESQLConnection {
	private(set) var database: QBEPostgresDatabase
	private var connection: COpaquePointer
	private(set) weak var result: QBEPostgresResult?
	private let queue : dispatch_queue_t
	
	private init(database: QBEPostgresDatabase, connection: COpaquePointer) {
		self.connection = connection
		self.database = database
		self.queue = dispatch_queue_create("QBEPostgresConnection.Queue", DISPATCH_QUEUE_SERIAL)
		dispatch_set_target_queue(self.queue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
	}
	
	deinit {
		if connection != nil {
			dispatch_sync(queue) {
				PQfinish(self.connection)
			}
		}
	}
	
	func clone() -> QBEFallible<QBEPostgresConnection> {
		return self.database.connect()
	}

	func run(sql: [String], job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		for q in sql {
			let res = self.query(q)
			if case .Failure(let e) = res {
				callback(.Failure(e))
				return
			}
		}

		callback(.Success())
	}

	private func perform(block: () -> (Bool)) -> Bool {
		var success: Bool = false
		dispatch_sync(queue) {
			let result = block()
			if !result {
				let message = String(CString:  PQerrorMessage(self.connection), encoding: NSUTF8StringEncoding) ?? "(unknown)"
				QBELog("PostgreSQL perform error: \(message)")
				success = false
			}
			else {
				success = true
			}
		}
		return success
	}
	
	private var lastError: String { get {
			return String(CString:  PQerrorMessage(self.connection), encoding: NSUTF8StringEncoding) ?? "(unknown)"
	} }
	
	func query(sql: String) -> QBEFallible<QBEPostgresResult> {
		if self.result != nil && !self.result!.finished {
			fatalError("Cannot start a query when the previous result is not finished yet")
		}
		
		#if DEBUG
			QBELog("PostgreSQL Query \(sql)")
		#endif
		
		if self.perform({
			if PQsendQuery(self.connection, sql.cStringUsingEncoding(NSUTF8StringEncoding)!) == 1 {
				PQsetSingleRowMode(self.connection)
				return true
			}
			return false
		}) {
			let result = QBEPostgresResult.create(self)
			switch result {
				case .Success(let r):
					self.result = r
				
				case .Failure(_):
					self.result = nil
			}
			return result
		}
		
		return .Failure(self.lastError)
	}
}

/**
Represents the result of a PostgreSQL query as a QBEData object. */
class QBEPostgresData: QBESQLData {
	private let database: QBEPostgresDatabase
	private let locale: QBELocale?

	static func create(database database: QBEPostgresDatabase, tableName: String, schemaName: String, locale: QBELocale?) -> QBEFallible<QBEPostgresData> {
		let query = "SELECT * FROM \(database.dialect.tableIdentifier(tableName, schema: schemaName, database: database.database)) LIMIT 1"
		return database.connect().use {
			$0.query(query).use {(result) -> QBEPostgresData in
				result.finish() // We're not interested in that one row we just requested, just the column names
				return QBEPostgresData(database: database, schema: schemaName, table: tableName, columns: result.columnNames, locale: locale)
			}
		}
	}
	
	private init(database: QBEPostgresDatabase, fragment: QBESQLFragment, columns: [QBEColumn], locale: QBELocale?) {
		self.database = database
		self.locale = locale
		super.init(fragment: fragment, columns: columns)
	}
	
	private init(database: QBEPostgresDatabase, schema: String, table: String, columns: [QBEColumn], locale: QBELocale?) {
		self.database = database
		self.locale = locale
		super.init(table: table, schema: schema, database: database.database, dialect: database.dialect, columns: columns)
	}
	
	override func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBEPostgresData(database: self.database, fragment: fragment, columns: resultingColumns, locale: locale)
	}
	
	override func stream() -> QBEStream {
		return QBEPostgresStream(data: self)
	}
	
	private func result() -> QBEFallible<QBEPostgresResult> {
		return database.connect().use {
			$0.query(self.sql.sqlSelect(nil).sql)
		}
	}
	
	override func isCompatibleWith(other: QBESQLData) -> Bool {
		if let om = other as? QBEPostgresData {
			if self.database.isCompatible(om.database) {
				return true
			}
		}
		return false
	}
}

/**
QBEPostgresStream provides a stream of records from a PostgreSQL result set. Because SQLite result can only be accessed once
sequentially, cloning of this stream requires re-executing the query. */
private class QBEPostgresResultStream: QBESequenceStream {
	init(result: QBEPostgresResult) {
		super.init(AnySequence<QBEFallible<QBETuple>>(result), columnNames: result.columnNames)
	}
	
	override func clone() -> QBEStream {
		fatalError("QBEPostgresResultStream cannot be cloned, because a result cannot be iterated multiple times. Clone QBEPostgresStream instead")
	}
}

/** Stream that lazily queries and streams results from a PostgreSQL query.
*/
class QBEPostgresStream: QBEStream {
	private var resultStream: QBEStream?
	private let data: QBEPostgresData
	
	init(data: QBEPostgresData) {
		self.data = data
	}
	
	private func stream() -> QBEStream {
		if resultStream == nil {
			switch data.result() {
				case .Success(let rs):
					resultStream = QBEPostgresResultStream(result: rs)
				
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
		return QBEPostgresStream(data: data)
	}
}

class QBEPostgresSourceStep: QBEStep {
	var tableName: String = ""
	var host: String = "localhost"
	var user: String = "postgres"
	var databaseName: String = "postgres"
	var schemaName: String = "public"
	var port: Int = 5432
	let defaultSchemaName = "public"

	var password: QBESecret {
		return QBESecret(serviceType: "postgres", host: host, port: port, account: user, friendlyName: String(format: NSLocalizedString("User %@ at PostgreSQL server %@ (port %d)", comment: ""), user, host, port))
	}
	
	init(host: String, port: Int, user: String, database: String,  schemaName: String, tableName: String) {
		self.host = host
		self.user = user
		self.port = port
		self.databaseName = database
		self.tableName = tableName
		self.schemaName = schemaName
		super.init()
	}

	required init() {
		super.init()
	}

	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? ""
		self.host = (aDecoder.decodeObjectForKey("host") as? String) ?? ""
		self.databaseName = (aDecoder.decodeObjectForKey("database") as? String) ?? ""
		self.user = (aDecoder.decodeObjectForKey("user") as? String) ?? ""
		self.port = Int(aDecoder.decodeIntForKey("port"))
		self.schemaName = aDecoder.decodeStringForKey("schema") ?? ""
		super.init(coder: aDecoder)

		if let pw = (aDecoder.decodeObjectForKey("password") as? String) {
			self.password.stringValue = pw
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(tableName, forKey: "tableName")
		coder.encodeObject(host, forKey: "host")
		coder.encodeObject(user, forKey: "user")
		coder.encodeObject(databaseName, forKey: "database")
		coder.encodeInt(Int32(port ?? 0), forKey: "port")
		coder.encodeString(schemaName ?? "", forKey: "schema")
	}

	override func sentence(locale: QBELocale, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .Neutral, .Read:
			template = "Load table [#] from schema [#] in PostgreSQL database [#]"

		case .Write:
			template = "Write to table [#] in schema [#] in PostgreSQL database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceList(value: self.tableName ?? "", provider: { (callback) -> () in
				if let d = self.database {
					d.tables(self.databaseName ?? "", schemaName: self.schemaName ?? self.defaultSchemaName) { tablesFallible in
						switch tablesFallible {
						case .Success(let tables):
							callback(.Success(tables))

						case .Failure(let e):
							callback(.Failure(e))
						}
					}
				}
				else {
					callback(.Failure(NSLocalizedString("Could not connect to database", comment: "")))
				}
			}, callback: { (newTable) -> () in
				self.tableName = newTable
			}),

			QBESentenceList(value: self.schemaName ?? self.defaultSchemaName, provider: { (callback) -> () in
				if let d = self.database {
					d.schemas(self.databaseName ?? "") { schemaFallible in
						switch schemaFallible {
						case .Success(let dbs):
							callback(.Success(dbs))

						case .Failure(let e):
							callback(.Failure(e))
						}
					}
				}
				else {
					callback(.Failure(NSLocalizedString("Could not connect to database", comment: "")))
				}
			}, callback: { (newSchema) -> () in
					self.schemaName = newSchema
			}),

			QBESentenceList(value: self.databaseName ?? "", provider: { (callback) -> () in
				if let d = self.database {
					d.databases { dbFallible in
						switch dbFallible {
						case .Success(let dbs):
							callback(.Success(dbs))

						case .Failure(let e):
							callback(.Failure(e))
						}
					}
				}
				else {
					callback(.Failure(NSLocalizedString("Could not connect to database", comment: "")))
				}
				}, callback: { (newDatabase) -> () in
					self.databaseName = newDatabase
			})
		)
	}
	
	internal var database: QBEPostgresDatabase? {
		/* For PostgreSQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. This does
		not work from a sandboxed application unless special privileges are obtained. To avoid confusion we rewrite
		localhost here to 127.0.0.1 in order to force access through TCP/IP. */
		let ha = (host == "localhost") ? "127.0.0.1" : host
		return QBEPostgresDatabase(host: ha, port: port, user: user, password: self.password.stringValue ?? "", database: databaseName)
	}

	override var mutableData: QBEMutableData? {
		if let d = self.database where !tableName.isEmpty && !schemaName.isEmpty {
			return QBESQLMutableData(database: d, schemaName: schemaName, tableName: tableName)
		}
		return nil
	}

	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		job.async {
			if let s = self.database where !self.tableName.isEmpty {
				callback(QBEPostgresData.create(database: s, tableName: self.tableName, schemaName: self.schemaName, locale: QBEAppDelegate.sharedInstance.locale).use({return $0.coalesced}))
			}
			else {
				callback(.Failure(NSLocalizedString("No database or table selected", comment: "")))
			}
		}
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}
}