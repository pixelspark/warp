import Foundation

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
	
	private override func forceStringExpression(expression: String) -> String {
		return "CAST(\(expression) AS VARCHAR)"
	}
	
	private override func forceNumericExpression(expression: String) -> String {
		return "CAST(\(expression) AS DECIMAL)"
	}
}

internal class QBEPostgresResult: SequenceType, GeneratorType {
	typealias Element = QBETuple
	typealias Generator = QBEPostgresResult
	
	private let connection: QBEPostgresConnection
	private var result: COpaquePointer = nil
	private(set) var columnNames: [QBEColumn] = []
	private(set) var columnTypes: [Oid] = []
	private(set) var finished = false
	
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
	
	init?(connection: QBEPostgresConnection) {
		self.connection = connection
		
		// Get column names from result set
		var failed = false
		dispatch_sync(connection.queue) {
			self.result = PQgetResult(self.connection.connection)
			if self.result == nil {
				QBELog("PostgreSQL no result: \(PQerrorMessage(self.connection.connection))")
				self.finished = true
			}
			else {
				let colCount = PQnfields(self.result)
				for colIndex in 0..<colCount {
					let column = PQfname(self.result, colIndex)
					if column != nil {
						if let name = NSString(bytes: column, length: Int(strlen(column)), encoding: NSUTF8StringEncoding) {
							self.columnNames.append(QBEColumn(String(name)))
							let type = PQftype(self.result, colIndex)
							self.columnTypes.append(type)
						}
						else {
							failed = true
							return
						}
					}
					else {
						failed = true
						return
					}
				}
			}
		}
		
		if failed {
			return nil
		}
	}
	
	func finish() {
		_finish(false)
	}
	
	private func _finish(warn: Bool) {
		if !self.finished {
			/* A new query cannot be started before all results from the previous one have been fetched, because packets
			will get out of order. */
			var n = 0
			while let x = self.row() {
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
	
	func row() -> [QBEValue]? {
		var rowData: [QBEValue]? = nil
		
		dispatch_sync(self.connection.queue) {
			if self.result == nil {
				self.result = PQgetResult(self.connection.connection)
			}
			
			// Because we are in single-row mode, each result set should only contain a single tuple.
			if self.result != nil {
				if PQntuples(self.result) == 1 && PQresultStatus(self.result).value == PGRES_SINGLE_TUPLE.value {
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
					if PQresultStatus(self.result).value != PGRES_TUPLES_OK.value {
						let status = String(CString: PQresStatus(PQresultStatus(self.result)), encoding: NSUTF8StringEncoding) ?? "(unknown status)"
						let error = String(CString: PQresultErrorMessage(self.result), encoding: NSUTF8StringEncoding) ?? "(unknown error)"
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
		return rowData
	}
}

class QBEPostgresDatabase {
	private let host: String
	private let port: Int
	private let user: String
	private let password: String
	private let database: String
	private let dialect: QBESQLDialect = QBEPostgresDialect()
	
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
	
	func databases(callback: ([String]) -> ()) {
		if let r = QBEPostgresConnection(database: self).query("SELECT datname FROM pg_catalog.pg_database WHERE NOT datistemplate") {
			var dbs: [String] = []
			while let d = r.row() {
				if let name = d[0].stringValue {
					dbs.append(name)
				}
			}
			
			callback(dbs)
		}
	}
	
	func tables(callback: ([String]) -> ()) {
		if let r = QBEPostgresConnection(database: self).query("SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname != 'pg_catalog'  AND schemaname != 'information_schema'") {
			var dbs: [String] = []
			while let d = r.row() {
				if let name = d[0].stringValue {
					dbs.append(name)
				}
			}
			
			callback(dbs)
		}
	}
}

/**
Implements a connection to a PostgreSQL database (corresponding to a MYSQL object in the PostgreSQL library). The connection ensures
that any operations are serialized (for now using a global queue for all PostgreSQL operations). */
internal class QBEPostgresConnection {
	private(set) var database: QBEPostgresDatabase
	private var connection: COpaquePointer
	private(set) weak var result: QBEPostgresResult?
	private let queue : dispatch_queue_t
	
	init(database: QBEPostgresDatabase) {
		self.database = database
		self.connection = nil
		self.queue = dispatch_queue_create("QBEPostgresConnection.Queue", DISPATCH_QUEUE_SERIAL)
		dispatch_set_target_queue(self.queue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
		
		self.perform({() -> Bool in
			let userEscaped = database.user.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLUserAllowedCharacterSet())!
			let passwordEscaped = database.password.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLPasswordAllowedCharacterSet())!
			let hostEscaped = database.host.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!
			
			let url = "postgres://\(userEscaped):\(passwordEscaped)@\(hostEscaped):\(database.port)/\(database.database.urlEncoded)"
			
			self.connection = PQconnectdb(url)
			
			switch PQstatus(self.connection).value {
				case CONNECTION_BAD.value:
					return false
				
				case CONNECTION_OK.value:
					return true
				
				default:
					QBELog("Unknown connection status: \(PQstatus(self.connection))")
					return false
			}
		})
	}
	
	deinit {
		if connection != nil {
			dispatch_sync(queue) {
				PQfinish(self.connection)
			}
		}
	}
	
	func clone() -> QBEPostgresConnection? {
		return QBEPostgresConnection(database: self.database)
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
			success = true
		}
		return success
	}
	
	func query(sql: String) -> QBEPostgresResult? {
		if self.result != nil && !self.result!.finished {
			fatalError("Cannot start a query when the previous result is not finished yet")
		}
		
		#if DEBUG
			QBELog("PostgreSQL Query \(sql)")
		#endif
		
		var result: QBEPostgresResult? = nil
		if self.perform({
			if PQsendQuery(self.connection, sql.cStringUsingEncoding(NSUTF8StringEncoding)!) == 1 {
				PQsetSingleRowMode(self.connection)
				return true
			}
			return false
		}) {
			result = QBEPostgresResult(connection: self)
			self.result = result
			return result
		}
		
		return nil
	}
}

/**
Represents the result of a PostgreSQL query as a QBEData object. */
class QBEPostgresData: QBESQLData {
	private let database: QBEPostgresDatabase
	private let locale: QBELocale?
	
	private convenience init(database: QBEPostgresDatabase, tableName: String, locale: QBELocale?) {
		let query = "SELECT * FROM \(database.dialect.tableIdentifier(tableName)) LIMIT 1"
		let result = QBEPostgresConnection(database: database).query(query)
		result?.finish() // We're not interested in that one row we just requested, just the column names
		
		self.init(database: database, table: tableName, columns: result?.columnNames ?? [], locale: locale)
	}
	
	private init(database: QBEPostgresDatabase, fragment: QBESQLFragment, columns: [QBEColumn], locale: QBELocale?) {
		self.database = database
		self.locale = locale
		super.init(fragment: fragment, columns: columns)
	}
	
	private init(database: QBEPostgresDatabase, table: String, columns: [QBEColumn], locale: QBELocale?) {
		self.database = database
		self.locale = locale
		super.init(table: table, dialect: database.dialect, columns: columns)
	}
	
	override func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBEPostgresData(database: self.database, fragment: fragment, columns: resultingColumns, locale: locale)
	}
	
	override func stream() -> QBEStream {
		return QBEPostgresStream(data: self) ?? QBEEmptyStream()
	}
	
	private func result() -> QBEPostgresResult? {
		let res = QBEPostgresConnection(database: self.database).query(self.sql.sqlSelect(nil).sql)
		return res
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
		super.init(SequenceOf<QBETuple>(result), columnNames: result.columnNames)
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
			if let rs = data.result() {
				resultStream = QBEPostgresResultStream(result: rs)
			}
			else {
				resultStream = QBEEmptyStream()
			}
		}
		return resultStream!
	}
	
	func fetch(consumer: QBESink, job: QBEJob?) {
		return stream().fetch(consumer, job: job)
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		return stream().columnNames(callback)
	}
	
	func clone() -> QBEStream {
		return QBEPostgresStream(data: data)
	}
}

class QBEPostgresSourceStep: QBEStep {
	var tableName: String?
	var host: String?
	var user: String?
	var password: String?
	var databaseName: String?
	var port: Int?
	
	init(host: String, port: Int, user: String, password: String, database: String, tableName: String) {
		self.host = host
		self.user = user
		self.password = password
		self.port = port
		self.databaseName = database
		self.tableName = tableName
		super.init(previous: nil)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? ""
		self.host = (aDecoder.decodeObjectForKey("host") as? String) ?? ""
		self.databaseName = (aDecoder.decodeObjectForKey("database") as? String) ?? ""
		self.user = (aDecoder.decodeObjectForKey("user") as? String) ?? ""
		self.password = (aDecoder.decodeObjectForKey("password") as? String) ?? ""
		self.port = Int(aDecoder.decodeIntForKey("port"))
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(tableName, forKey: "tableName")
		coder.encodeObject(host, forKey: "host")
		coder.encodeObject(user, forKey: "user")
		coder.encodeObject(password, forKey: "password")
		coder.encodeObject(databaseName, forKey: "database")
		coder.encodeInt(Int32(port ?? 0), forKey: "port")
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("PostgreSQL table", comment: "")
		}
		return String(format: NSLocalizedString("Load table %@ from PostgreSQL database", comment: ""), self.tableName ?? "")
	}
	
	internal var database: QBEPostgresDatabase? { get {
		if let h = host, p = port, u = user, pw = password, d = databaseName {
			/* For PostgreSQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. This does
			not work from a sandboxed application unless special privileges are obtained. To avoid confusion we rewrite
			localhost here to 127.0.0.1 in order to force access through TCP/IP. */
			let ha = (h == "localhost") ? "127.0.0.1" : h
			return QBEPostgresDatabase(host: ha, port: p, user: u, password: pw, database: d)
		}
		return nil
		} }
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		QBEAsyncBackground {
			if let s = self.database {
				callback(QBECoalescedData(QBEPostgresData(database: s, tableName: self.tableName ?? "", locale: QBEAppDelegate.sharedInstance.locale)))
			}
			else {
				callback(QBERasterData())
			}
		}
	}
	
	override func exampleData(job: QBEJob?, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		self.fullData(job, callback: { (fd) -> () in
			callback(fd.random(maxInputRows))
		})
	}
}