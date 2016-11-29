/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore
import WarpConduit

/** 
Implementation of the MySQL 'SQL dialect'. Only deviatons from the standard dialect are implemented here. */
private final class QBEMySQLDialect: StandardSQLDialect {
	override var identifierQualifier: String { get { return  "`" } }
	override var identifierQualifierEscape: String { get { return  "\\`" } }
	
	override func unaryToSQL(_ type: Function, args: [String]) -> String? {
		let value = args.joined(separator: ", ")
		
		if type == Function.Random {
			return "RAND(\(value))"
		}
		return super.unaryToSQL(type, args: args)
	}
	
	fileprivate override func aggregationToSQL(_ aggregation: Aggregator, alias: String) -> String? {
		// For Function.Count, we should count numeric values only. In MySQL this can be done using REGEXP
		if aggregation.reduce == Function.Count {
			if let expressionSQL = expressionToSQL(aggregation.map, alias: alias) {
				return "SUM(CASE WHEN (\(expressionSQL) REGEXP '^[[:digit:]]+$') THEN 1 ELSE 0 END)"
			}
			return nil
		}
		
		return super.aggregationToSQL(aggregation, alias: alias)
	}
	
	fileprivate override func forceStringExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS BINARY)"
	}
	
	fileprivate override func forceNumericExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS DECIMAL)"
	}
}

internal final class QBEMySQLResult: Sequence, IteratorProtocol {
	typealias Element = Fallible<Tuple>
	typealias Iterator = QBEMySQLResult
	
	private let connection: QBEMySQLConnection
	private let result: UnsafeMutablePointer<MYSQL_RES>
	private(set) var columns: OrderedSet<Column> = []
	private(set) var columnTypes: [MYSQL_FIELD] = []
	private(set) var finished = false
	
	static func create(_ result: UnsafeMutablePointer<MYSQL_RES>, connection: QBEMySQLConnection) -> Fallible<QBEMySQLResult> {
		// Get column names from result set
		var resultSet: Fallible<QBEMySQLResult> = .failure("Unknown error")
		
		QBEMySQLConnection.sharedClient.queue.sync {
			let realResult = QBEMySQLResult(result: result, connection: connection)
			
			let colCount = mysql_field_count(connection.connection)
			for _ in 0..<colCount {
				if let column = mysql_fetch_field(result) {
					if let name = String(bytesNoCopy: column.pointee.name, length: Int(column.pointee.name_length), encoding: String.Encoding.utf8, freeWhenDone: false) {
						realResult.columns.append(Column(String(name)))
						realResult.columnTypes.append(column.pointee)
					}
					else {
						resultSet = .failure(NSLocalizedString("The MySQL data contains an invalid column name.", comment: ""))
						return
					}
				}
				else {
					resultSet = .failure(NSLocalizedString("MySQL returned an invalid column.", comment: ""))
					return
				}
			}
			
			resultSet = .success(realResult)
		}
		
		return resultSet
	}
	
	private init(result: UnsafeMutablePointer<MYSQL_RES>, connection: QBEMySQLConnection) {
		self.result = result
		self.connection = connection
	}
	
	func finish() {
		_finish(false)
	}
	
	private func _finish(_ warn: Bool) {
		if !self.finished {
			/* A new query cannot be started before all results from the previous one have been fetched, because packets
			will get out of order. */
			var n = 0
			while self.row() != nil {
				n += 1
			}
			
			#if DEBUG
				if warn && n > 0 {
					trace("Unfinished result was destroyed, drained \(n) rows to prevent packet errors. This is a performance issue!")
				}
			#endif
			self.finished = true
		}
	}
	
	deinit {
		_finish(true)
		
		let result = self.result
		QBEMySQLConnection.sharedClient.queue.sync {
			mysql_free_result(result)
			return
		}
	}
	
	func makeIterator() -> Iterator {
		return self
	}
	
	func next() -> Element? {
		let r = row()
		return r == nil ? nil : .success(r!)
	}
	
	func row() -> [Value]? {
		var rowDataset: [Value]? = nil
		
		QBEMySQLConnection.sharedClient.queue.sync {
			if let row = mysql_fetch_row(self.result) {
				rowDataset = []
				rowDataset!.reserveCapacity(self.columns.count)
				
				for cn in 0..<self.columns.count {
					let val = row[cn]
					if val == nil {
						rowDataset!.append(Value.empty)
					}
					else {
						// Is this a date field?
						let type = self.columnTypes[cn]
						if type.type.rawValue == MYSQL_TYPE_TIME.rawValue
							|| type.type.rawValue == MYSQL_TYPE_DATE.rawValue
							|| type.type.rawValue == MYSQL_TYPE_DATETIME.rawValue
							|| type.type.rawValue == MYSQL_TYPE_TIMESTAMP.rawValue {
							
							/* Only MySQL TIMESTAMP values are actual dates in UTC. The rest can be anything, in any time
							zone, so we cannot convert these to Value.date. */
							if let ptr = val, let str = String(cString: ptr, encoding: String.Encoding.utf8) {
								if type.type.rawValue == MYSQL_TYPE_TIMESTAMP.rawValue {
									// Datetime string is formatted as YYYY-MM-dd HH:mm:ss and is in UTC
									let dateFormatter = DateFormatter()
									dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
									dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
									if let d = dateFormatter.date(from: str) {
										rowDataset!.append(Value(d))
									}
									else {
										rowDataset!.append(Value.invalid)
									}
								}
								else {
									rowDataset!.append(Value.string(str))
								}
							}
							else {
								rowDataset!.append(Value.invalid)
							}
						}
						else if type.type.rawValue == MYSQL_TYPE_TINY.rawValue
							|| type.type.rawValue == MYSQL_TYPE_SHORT.rawValue
							|| type.type.rawValue == MYSQL_TYPE_LONG.rawValue
							|| type.type.rawValue == MYSQL_TYPE_INT24.rawValue
							|| type.type.rawValue == MYSQL_TYPE_LONGLONG.rawValue {
								if let ptr = val, let str = String(cString: ptr, encoding: String.Encoding.utf8), let nt = Int(str) {
									rowDataset!.append(Value.int(nt))
								}
								else {
									rowDataset!.append(Value.invalid)
								}
								
						}
						else if type.type.rawValue == MYSQL_TYPE_DECIMAL.rawValue
								|| type.type.rawValue == MYSQL_TYPE_NEWDECIMAL.rawValue
								|| type.type.rawValue == MYSQL_TYPE_DOUBLE.rawValue
								|| type.type.rawValue == MYSQL_TYPE_FLOAT.rawValue {
							if let ptr = val, let str = String(cString: ptr, encoding: String.Encoding.utf8) {
								if let dbl = str.toDouble() {
									rowDataset!.append(Value.double(dbl))
								}
								else {
									rowDataset!.append(Value.invalid)
								}
							}
							else {
								rowDataset!.append(Value.invalid)
							}
						}
						else {
							if let ptr = val, let str = String(cString: ptr, encoding: String.Encoding.utf8) {
								rowDataset!.append(Value.string(str))
							}
							else {
								rowDataset!.append(Value.invalid)
							}
						}
					}
				}
			}
			else {
				self.finished = true
			}
		}
		
		return rowDataset
	}
}

class QBEMySQLDatabase: SQLDatabase {
	private let host: String
	private let port: Int
	private let user: String
	private let password: String
	let databaseName: String?
	let dialect: SQLDialect = QBEMySQLDialect()

	/** When database is nil, the current database will be whatever default database MySQL starts with. */
	init(host: String, port: Int, user: String, password: String, database: String? = nil) {
		self.host = host
		self.port = port
		self.user = user
		self.password = password
		self.databaseName = database
	}
	
	func isCompatible(_ other: QBEMySQLDatabase) -> Bool {
		return self.host == other.host && self.user == other.user && self.password == other.password && self.port == other.port
	}

	func connect(_ callback: (Fallible<SQLConnection>) -> ()) {
		callback(self.connect().use { return $0 })
	}
	
	func connect() -> Fallible<QBEMySQLConnection> {
		let connection = QBEMySQLConnection(database: self, connection: mysql_init(nil))
		
		if !connection.perform({ () -> Int32 in
			mysql_real_connect(connection.connection,
				self.host.cString(using: String.Encoding.utf8)!,
				self.user.cString(using: String.Encoding.utf8)!,
				self.password.cString(using: String.Encoding.utf8)!,
				nil,
				UInt32(self.port),
				nil,
				UInt(0)
			)
			return Int32(mysql_errno(connection.connection))
		}) {
			return .failure(connection.lastError)
		}
		
		if let dbn = databaseName, let dbc = dbn.cString(using: String.Encoding.utf8), !dbn.isEmpty {
			if !connection.perform({() -> Int32 in
				return mysql_select_db(connection.connection, dbc)
			}) {
				return .failure(connection.lastError)
			}
		}
		
		/* Use UTF-8 for any textual data that is sent or received in this connection
		(see https://dev.mysql.com/doc/refman/5.0/en/charset-connection.html) */
		connection.query("SET NAMES 'utf8' ").maybe { (res) -> () in
			// We're not using the response from this query
			res?.finish()
		}
		
		// Use UTC for any dates that are sent and received in this connection
		connection.query("SET time_zone = '+00:00' ").maybe { (res) -> () in
			// We're not using the response from this query
			res?.finish()
		}
		return .success(connection)
	}

	func dataForTable(_ table: String, schema: String?, job: Job, callback: (Fallible<Dataset>) -> ()) {
		switch QBEMySQLDataset.create(self, tableName: table) {
		case .success(let md):
			callback(.success(md))
		case .failure(let e):
			callback(.failure(e))
		}
	}
}

private class QBEMySQLClient {
	let queue: DispatchQueue

	init() {
		/* Mysql_library_init is what we should call, but as it is #defined to mysql_server_init, Swift doesn't see it.
		So we just call mysql_server_int. */
		if mysql_server_init(0, nil, nil) == 0 {
			queue = DispatchQueue(label: "QBEMySQLConnection.Queue")
		}
		else {
			fatalError("Error initializing MySQL library")
		}
	}
}

struct QBEMySQLConstraint {
	let name: String

	let database: String
	let table: String
	let column: String

	let referencedDatabase: String
	let referencedTable: String
	let referencedColumn: String
}

/**
Implements a connection to a MySQL database (corresponding to a MYSQL object in the MySQL library). The connection ensures
that any operations are serialized (for now using a global queue for all MySQL operations). */
internal class QBEMySQLConnection: SQLConnection {
	fileprivate static var sharedClient = QBEMySQLClient()
	fileprivate(set) var database: QBEMySQLDatabase
	fileprivate var connection: UnsafeMutablePointer<MYSQL>?
	fileprivate(set) weak var result: QBEMySQLResult?
	
	fileprivate init(database: QBEMySQLDatabase, connection: UnsafeMutablePointer<MYSQL>) {
		self.database = database
		self.connection = connection
	}
	
	deinit {
		if connection != nil {
			QBEMySQLConnection.sharedClient.queue.sync {
				mysql_close(self.connection)
			}
		}
	}

	func run(_ sql: [String], job: Job, callback: (Fallible<Void>) -> ()) {
		for query in sql {
			switch self.query(query) {
			case .success(_):
				break

			case .failure(let e):
				callback(.failure(e))
				return
			}
		}

		callback(.success())
	}

	func clone() -> Fallible<QBEMySQLConnection> {
		return self.database.connect()
	}

	/** Fetches the server information string (containing version number and other useful information). This is mostly
	used to check whether a connection can be made. */
	func serverInformation(_ callback: (Fallible<String>) -> ()) {
		switch self.query("SELECT version()") {
		case .success(let result):
			if let row = result?.row() {
				if let version = row.first?.stringValue {
					callback(.success(version))
				}
				else {
					callback(.failure("No or invalid version string returned"))
				}
			}
			else {
				callback(.failure("No version returned"))
			}

		case .failure(let e): callback(.failure(e))
		}
	}

	func databases(_ callback: (Fallible<[String]>) -> ()) {
		let resultFallible = self.query("SHOW DATABASES")
		switch resultFallible {
			case .success(let result):
				var dbs: [String] = []
				while let d = result?.row() {
					if let name = d[0].stringValue {
						dbs.append(name)
					}
				}
				
				callback(.success(dbs))
			
			case .failure(let error):
				callback(.failure(error))
		}
	}
	
	func tables(_ callback: (Fallible<[String]>) -> ()) {
		let fallibleResult = self.query("SHOW TABLES")
		switch fallibleResult {
			case .success(let result):
				var dbs: [String] = []
				while let d = result?.row() {
					if let name = d[0].stringValue {
						dbs.append(name)
					}
				}
				callback(.success(dbs))
			
			case .failure(let error):
				callback(.failure(error))
		}
	}

	func constraints(fromTable tableName: String, inDatabase databaseName: String, callback: (Fallible<[QBEMySQLConstraint]>) -> ()) {
		let dbn = self.database.dialect.expressionToSQL(Literal(Value(databaseName)), alias: "", foreignAlias: nil, inputValue: nil)!
		let tbn = self.database.dialect.expressionToSQL(Literal(Value(tableName)), alias: "", foreignAlias: nil, inputValue: nil)!

		switch self.query("SELECT constraint_name, table_schema, table_name, column_name, referenced_table_schema, referenced_table_name, referenced_column_name FROM information_schema.key_column_usage WHERE table_schema=\(dbn) AND table_name=\(tbn) AND referenced_column_name IS NOT NULL") {
		case .success(let result):
			var constraints: [QBEMySQLConstraint] = []
			while let d = result?.row() {
				if	let constraintName = d[0].stringValue,
					let tableSchema = d[1].stringValue,
					let tableName = d[2].stringValue,
					let columnName = d[3].stringValue,
					let referencedTableSchema = d[4].stringValue,
					let referencedTableName = d[5].stringValue,
					let referencedColumnName = d[6].stringValue {
					constraints.append(QBEMySQLConstraint(
						name: constraintName,
						database: tableSchema, table: tableName, column: columnName,
						referencedDatabase: referencedTableSchema, referencedTable: referencedTableName, referencedColumn: referencedColumnName
					))
				}
			}
			callback(.success(constraints))

		case .failure(let e):
			callback(.failure(e))
		}
	}
	
	fileprivate func perform(_ block: () -> (Int32)) -> Bool {
		var success: Bool = false
		QBEMySQLConnection.sharedClient.queue.sync {
			let result = block()
			if result != 0 {
				let message = String(cString: mysql_error(self.connection), encoding: String.Encoding.utf8) ?? "(unknown)"
				trace("MySQL perform error: \(message)")
				success = false
			}
			else {
				success = true
			}
		}
		return success
	}
	
	fileprivate var lastError: String {
		return String(cString: mysql_error(self.connection), encoding: String.Encoding.utf8) ?? "(unknown)"
	}

	fileprivate var isError: Bool {
		return mysql_errno(self.connection) != 0
	}

	/** Returns the result as QBEMySQLResult. This is nil for queries that do not return a result (e.g. UPDATE, SET, etc.). */
	func query(_ sql: String) -> Fallible<QBEMySQLResult?> {
		if self.result != nil && !self.result!.finished {
			fatalError("Cannot start a query when the previous result is not finished yet")
		}
		self.result = nil
		
		#if DEBUG
			trace("MySQL Query \(sql)")
		#endif

		if self.perform({return mysql_query(self.connection, sql.cString(using: String.Encoding.utf8)!)}) {
			if let r = mysql_use_result(self.connection) {
				let result = QBEMySQLResult.create(r, connection: self)
				return result.use({self.result = $0; return .success($0)})
			}
			else {
				if self.isError {
					return .failure(self.lastError)
				}
				return .success(nil)
			}
		}
		else {
			return .failure(self.lastError)
		}
	}
}

/** 
Represents the result of a MySQL query as a Dataset object. */
final class QBEMySQLDataset: SQLDataset {
	private let database: QBEMySQLDatabase
	
	static func create(_ database: QBEMySQLDatabase, tableName: String) -> Fallible<QBEMySQLDataset> {
		let query = "SELECT * FROM \(database.dialect.tableIdentifier(tableName, schema: nil, database: database.databaseName)) LIMIT 1"
		
		let fallibleConnection = database.connect()
		switch fallibleConnection {
			case .success(let connection):
				let fallibleResult = connection.query(query)
				
				switch fallibleResult {
					case .success(let result):
						if let result = result {
							result.finish() // We're not interested in that one row we just requested, just the column names
							return .success(QBEMySQLDataset(database: database, table: tableName, columns: result.columns))
						}
						return .failure("no result returned, but also no error")
					
					case .failure(let error):
						return .failure(error)
				}
			
			case .failure(let error):
				return .failure(error)
		}
	}
	
	fileprivate init(database: QBEMySQLDatabase, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.database = database
		super.init(fragment: fragment, columns: columns)
	}
	
	fileprivate init(database: QBEMySQLDatabase, table: String, columns: OrderedSet<Column>) {
		self.database = database
		super.init(table: table, schema: nil, database: database.databaseName!, dialect: database.dialect, columns: columns)
	}
	
	override func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return QBEMySQLDataset(database: self.database, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> WarpCore.Stream {
		return QBEMySQLStream(data: self)
	}
	
	fileprivate func result() -> Fallible<QBEMySQLResult?> {
		return self.database.connect().use { $0.query(self.sql.sqlSelect(nil).sql) }
	}
	
	override func isCompatibleWith(_ other: SQLDataset) -> Bool {
		if let om = other as? QBEMySQLDataset {
			if self.database.isCompatible(om.database) {
				return true
			}
		}
		return false
	}
}

/**
QBEMySQLStream provides a stream of records from a MySQL result set. Because SQLite result can only be accessed once
sequentially, cloning of this stream requires re-executing the query. */
private final class QBEMySQLResultStream: SequenceStream {
	init(result: QBEMySQLResult) {
		super.init(AnySequence<Fallible<Tuple>>(result), columns: result.columns)
	}
	
	override func clone() -> WarpCore.Stream {
		fatalError("QBEMySQLResultStream cannot be cloned, because a result cannot be iterated multiple times. Clone QBEMySQLStream instead")
	}
}

/** 
Stream that lazily queries and streams results from a MySQL query. */
final class QBEMySQLStream: WarpCore.Stream {
	private var resultStream: WarpCore.Stream?
	private let data: QBEMySQLDataset
	private let mutex = Mutex()
	
	init(data: QBEMySQLDataset) {
		self.data = data
	}
	
	private func stream() -> WarpCore.Stream {
		return self.mutex.locked {
			if resultStream == nil {
				switch data.result() {
				case .success(let result):
					if let result = result {
						resultStream = QBEMySQLResultStream(result: result)
					}
					else {
						resultStream = ErrorStream("no result received, but also not an error")
					}

				case .failure(let error):
					resultStream = ErrorStream(error)
				}
			}
			
			return resultStream!
		}
	}
	
	func fetch(_ job: Job, consumer: @escaping Sink) {
		return stream().fetch(job, consumer: consumer)
	}
	
	func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		return stream().columns(job, callback: callback)
	}
	
	func clone() -> WarpCore.Stream {
		return QBEMySQLStream(data: data)
	}
}

class QBEMySQLMutableDataset: SQLMutableDataset {
	override func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		let db = self.database as! QBEMySQLDatabase
		switch db.connect() {
			case .success(let connection):
				let dbn = self.database.dialect.expressionToSQL(Literal(Value(self.database.databaseName ?? "")), alias: "", foreignAlias: nil, inputValue: nil)!
				let tbn = self.database.dialect.expressionToSQL(Literal(Value(self.tableName)), alias: "", foreignAlias: nil, inputValue: nil)!
				switch connection.query("SELECT `COLUMN_NAME` FROM `information_schema`.`COLUMNS` WHERE (`TABLE_SCHEMA` = \(dbn)) AND (`TABLE_NAME` = \(tbn)) AND (`COLUMN_KEY` = 'PRI')") {
				case .success(let result):
					if let result = result {
						var primaryColumns = Set<Column>()
						for row in result {
							switch row {
							case .success(let r):
								if let c = r[0].stringValue {
									primaryColumns.insert(Column(c))
								}
								else {
									return callback(.failure("Invalid column name received"))
								}

							case .failure(let e):
								return callback(.failure(e))
							}
						}

						if primaryColumns.count == 0 {
							// No primary key, find a unique key instead
							switch connection.query("SELECT `COLUMN_NAME`,`INDEX_NAME` FROM `information_schema`.`STATISTICS` WHERE (`TABLE_SCHEMA` = \(dbn)) AND (`TABLE_NAME` = \(tbn)) AND NOT(`NULLABLE`) AND NOT(`NON_UNIQUE`) ORDER BY index_name ASC") {
							case .success(let r):
								var uniqueColumns = Set<Column>()
								var uniqueIndexName: String? = nil

								if let r = r {
									for row in r {
										switch row {
										case .success(let row):
											// Use all columns from the first index we see
											if let indexName = row[1].stringValue {
												if uniqueIndexName == nil {
													uniqueIndexName = indexName
												}
												else if uniqueIndexName! != indexName {
													break
												}
											}

											if let c = row[0].stringValue {
												uniqueColumns.insert(Column(c))
											}
											else {
												return callback(.failure("Invalid column name received"))
											}
										case .failure(let e):
											return callback(.failure(e))
										}
									}
								}

								if uniqueColumns.isEmpty {
									return callback(.failure(NSLocalizedString("This table does not have a primary key, which is required in order to be able to identify individual rows.", comment: "")))
								}
								else {
									return callback(.success(uniqueColumns))
								}

							case .failure(let e):
								return callback(.failure(e))

							}
						}
						else {
							callback(.success(primaryColumns))
						}
					}
					else {
						return callback(.failure("empty result received"))
					}

				case .failure(let e):
					return callback(.failure(e))
			}

			case .failure(let e):
				return callback(.failure(e))
		}
	}
}

class QBEMySQLSourceStep: QBEStep {
	var tableName: String? = nil
	var host: String = "localhost"
	var user: String = "root"
	var databaseName: String? = nil
	var port: Int = 3306

	var password: QBESecret {
		return QBESecret(serviceType: "mysql", host: host, port: port, account: user, friendlyName: String(format: NSLocalizedString("User %@ at MySQL server %@ (port %d)", comment: ""), user, host, port))
	}
	
	init(host: String, port: Int, user: String, database: String?, tableName: String?) {
		self.host = host
		self.user = user
		self.port = port
		self.databaseName = database
		self.tableName = tableName
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

		let host = (aDecoder.decodeObject(forKey: "host") as? String) ?? self.host
		let user = (aDecoder.decodeObject(forKey: "user") as? String) ?? self.user
		let port = Int(aDecoder.decodeInteger(forKey: "port"))

		if let pw = aDecoder.decodeString(forKey:"password") {
			self.password.stringValue = pw
		}

		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? self.tableName
		self.databaseName = (aDecoder.decodeObject(forKey: "database") as? String) ?? self.databaseName
		self.user = user
		self.host = host
		self.port = port
	}

	required init() {
	    super.init()
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(tableName, forKey: "tableName")
		coder.encode(host, forKey: "host")
		coder.encode(user, forKey: "user")
		coder.encode(databaseName, forKey: "database")
		coder.encode(port, forKey: "port")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .neutral, .read: template = "Load table [#] from MySQL database [#]"
		case .write: template = "Write to table [#] in MySQL database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceDynamicOptionsToken(value: self.tableName ?? "", provider: { (callback) -> () in
				let d = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
				switch d.connect() {
				case .success(let con):
					con.tables { tablesFallible in
						switch tablesFallible {
						case .success(let tables):
							callback(.success(tables))

						case .failure(let e):
							callback(.failure(e))
						}
					}

				case .failure(let e):
					callback(.failure(e))
				}
			}, callback: { (newTable) -> () in
					self.tableName = newTable
			}),

			QBESentenceDynamicOptionsToken(value: self.databaseName ?? "", provider: { callback in
				/* Connect without selecting a default database, because the database currently selected may not exists
				(and then we get an error, and can't select another database). */
				let d = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: nil)
				switch d.connect() {
				case .success(let con):
					con.databases { dbFallible in
						switch dbFallible {
							case .success(let dbs):
								callback(.success(dbs))

							case .failure(let e):
								callback(.failure(e))
						}
					}

				case .failure(let e):
					callback(.failure(e))
				}
			}, callback: { (newDatabase) -> () in
				self.databaseName = newDatabase
			})
		)
	}

	internal var hostToConnectTo: String {
		/* For MySQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. This does
		not work from a sandboxed application unless special privileges are obtained. To avoid confusion we rewrite
		localhost here to 127.0.0.1 in order to force access through TCP/IP. */
		return (host == "localhost") ? "127.0.0.1" : host
	}

	override var mutableDataset: MutableDataset? { get {
		if let tn = self.tableName, !tn.isEmpty {
			let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
			return QBEMySQLMutableDataset(database: s, schemaName: nil, tableName: tn)
		}
		return nil
	} }

	var warehouse: Warehouse? {
		let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
		return SQLWarehouse(database: s, schemaName: nil)
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		job.async {
			// First check whether the connection details are right
			let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
			switch  s.connect() {
			case .success(_):
				if let dbn = self.databaseName, !dbn.isEmpty {
					if let tn = self.tableName, !tn.isEmpty {
						let md = QBEMySQLDataset.create(s, tableName: tn)
						callback(md.use { $0.coalesced })
					}
					else {
						callback(.failure(NSLocalizedString("Please select a table.", comment: "")))
					}
				}
				else {
					callback(.failure(NSLocalizedString("Please select a database.", comment: "")))
				}
			case .failure(let e):
				callback(.failure(e))
			}
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		job.async {
			// First check whether the connection details are right
			let s = QBEMySQLDatabase(host: self.hostToConnectTo, port: self.port, user: self.user, password: self.password.stringValue ?? "", database: self.databaseName)
			switch  s.connect() {
			case .success(let con):
				if let dbn = self.databaseName, !dbn.isEmpty, let tn = self.tableName, !tn.isEmpty {
					con.constraints(fromTable: tn, inDatabase: dbn) { result in
						switch result {
						case .success(let constraints):
							let steps = constraints.map { constraint -> QBERelatedStep in
								let sourceStep = QBEMySQLSourceStep(host: self.host, port: self.port, user: self.user, database: constraint.referencedDatabase, tableName: constraint.referencedTable)
								let joinExpression = Comparison(first: Sibling(Column(constraint.column)), second: Foreign(Column(constraint.referencedColumn)), type: .equal)
								return QBERelatedStep.joinable(step: sourceStep, type: .leftJoin, condition: joinExpression)
							}
							return callback(.success(steps))

						case .failure(let e):
							return callback(.failure(e))
						}
					}
				}
				else {
					return callback(.failure("No database or table selected".localized))
				}

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}
