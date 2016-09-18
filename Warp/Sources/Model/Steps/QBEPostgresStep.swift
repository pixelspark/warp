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
Implementation of the PostgreSQL 'SQL dialect'. Only deviatons from the standard dialect are implemented here. */
private class QBEPostgresDialect: StandardSQLDialect {
	override var identifierQualifier: String { get { return  "\"" } }
	override var identifierQualifierEscape: String { get { return  "\\\"" } }

	override func literalString(_ string: String) -> String {
		/* PostgreSQL needs its string literals prefixed with 'E' to make C-style backslash escapes work.
		    See http://www.postgresql.org/docs/9.2/static/sql-syntax-lexical.html */
		return "E\(super.literalString(string))"
	}
	
	private override func unaryToSQL(_ type: Function, args: [String]) -> String? {
		switch type {
			case .Random: return "RANDOM()"
			case .Left: return "SUBSTR(\(args[0]), 1, (\(args[1]))::integer)"
			case .Right: return "RIGHT(\(args[0]), LENGTH(\(args[0]))-(\(args[1]))::integer)"
			case .Mid: return "SUBSTR(\(args[0]), (\(args[1]))::integer, (\(args[2]))::integer)"

			default:
				return super.unaryToSQL(type, args: args)
		}
	}
	
	private override func aggregationToSQL(_ aggregation: Aggregator, alias: String) -> String? {
		// For Function.Count, we should count numeric values only. In PostgreSQL this can be done using REGEXP
		if let expressionSQL = expressionToSQL(aggregation.map, alias: alias) {
			switch aggregation.reduce {
			case .Count: return "SUM(CASE WHEN \(expressionSQL) ~* '^[[:digit:]]+$' THEN 1 ELSE 0 END)"
			case .Sum: return "SUM((\(expressionSQL))::float)"
				
			case .Average: return "AVG((\(expressionSQL))::float)"
			case .StandardDeviationPopulation: return "STDDEV_POP((\(expressionSQL))::float)"
			case .StandardDeviationSample: return "STDDEV_SAMP((\(expressionSQL))::float)"
			case .VariancePopulation: return "VAR_POP((\(expressionSQL))::float)"
			case .VarianceSample: return "VAR_SAMP((\(expressionSQL))::float)"
			case .Concat: return "STRING_AGG(\(expressionSQL),'')"
			case .Pack:
				return "STRING_AGG(REPLACE(REPLACE(\(expressionSQL),\(literalString(Pack.escape)),\(literalString(Pack.escapeEscape))),\(literalString(Pack.separator)),\(literalString(Pack.separatorEscape))), \(literalString(Pack.separator)))"

			default:
				break
			}
		}
		
		return super.aggregationToSQL(aggregation, alias: alias)
	}
	
	private override func binaryToSQL(_ type: Binary, first: String, second: String) -> String? {
		switch type {
			case .matchesRegex: return "(\(forceStringExpression(second)) ~* \(forceStringExpression(first)))"
			case .matchesRegexStrict: return "(\(forceStringExpression(second)) ~ \(forceStringExpression(first)))"
			default: return super.binaryToSQL(type, first: first, second: second)
		}
	}
	
	private override func forceStringExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS VARCHAR)"
	}
	
	private override func forceNumericExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS DECIMAL)"
	}
}

internal enum QBEPostgresType: Oid {
	case bool = 16
	case bytea = 17
	case char = 18
	case name = 19
	case int8 = 20
	case int2 = 21
	case int2vector = 22
	case int4 = 23
	case regproc = 24
	case text = 25
	case oid = 26
	case tid = 27
	case xid = 28
	case cid = 29
	case oidvector = 30
	case pg_type = 71
	case pg_attribute = 75
	case pg_proc = 81
	case pg_class = 83
	case json = 114
	case xml = 142
	case _xml = 143
	case _json = 199
	case pg_node_tree = 194
	case smgr = 210
	case point = 600
	case lseg = 601
	case path = 602
	case box = 603
	case polygon = 604
	case line = 628
	case _line = 629
	case float4 = 700
	case float8 = 701
	case abstime = 702
	case reltime = 703
	case tinterval = 704
	case unknown = 705
	case circle = 718
	case _circle = 719
	case money = 790
	case _money = 791
	case macaddr = 829
	case inet = 869
	case cidr = 650
	case _bool = 1000
	case _bytea = 1001
	case _char = 1002
	case _name = 1003
	case _int2 = 1005
	case _int2vector = 1006
	case _int4 = 1007
	case _regproc = 1008
	case _text = 1009
	case _oid = 1028
	case _tid = 1010
	case _xid = 1011
	case _cid = 1012
	case _oidvector = 1013
	case _bpchar = 1014
	case _varchar = 1015
	case _int8 = 1016
	case _point = 1017
	case _lseg = 1018
	case _path = 1019
	case _box = 1020
	case _float4 = 1021
	case _float8 = 1022
	case _abstime = 1023
	case _reltime = 1024
	case _tinterval = 1025
	case _polygon = 1027
	case aclitem = 1033
	case _aclitem = 1034
	case _macaddr = 1040
	case _inet = 1041
	case _cidr = 651
	case _cstring = 1263
	case bpchar = 1042
	case varchar = 1043
	case date = 1082
	case time = 1083
	case timestamp = 1114
	case _timestamp = 1115
	case _date = 1182
	case _time = 1183
	case timestamptz = 1184
	case _timestamptz = 1185
	case interval = 1186
	case _interval = 1187
	case _numeric = 1231
	case timetz = 1266
	case _timetz = 1270
	case bit = 1560
	case _bit = 1561
	case varbit = 1562
	case _varbit = 1563
	case numeric = 1700
	case refcursor = 1790
	case _refcursor = 2201
	case regprocedure = 2202
	case regoper = 2203
	case regoperator = 2204
	case regclass = 2205
	case regtype = 2206
	case _regprocedure = 2207
	case _regoper = 2208
	case _regoperator = 2209
	case _regclass = 2210
	case _regtype = 2211
	case uuid = 2950
	case _uuid = 2951
	case pg_lsn = 3220
	case _pg_lsn = 3221
	case tsvector = 3614
	case gtsvector = 3642
	case tsquery = 3615
	case regconfig = 3734
	case regdictionary = 3769
	case _tsvector = 3643
	case _gtsvector = 3644
	case _tsquery = 3645
	case _regconfig = 3735
	case _regdictionary = 3770
	case jsonb = 3802
	case _jsonb = 3807
	case txid_snapshot = 2970
	case _txid_snapshot = 2949
	case int4range = 3904
	case _int4range = 3905
	case numrange = 3906
	case _numrange = 3907
	case tsrange = 3908
	case _tsrange = 3909
	case tstzrange = 3910
	case _tstzrange = 3911
	case daterange = 3912
	case _daterange = 3913
	case int8range = 3926
	case _int8range = 3927
	case record = 2249
	case _record = 2287
	case cstring = 2275
	case any = 2276
	case anyarray = 2277
	case void = 2278
	case trigger = 2279
	case event_trigger = 3838
	case language_handler = 2280
	case `internal` = 2281
	case opaque = 2282
	case anyelement = 2283
	case anynonarray = 2776
	case anyenum = 3500
	case fdw_handler = 3115
}

internal class QBEPostgresResult: Sequence, IteratorProtocol {
	typealias Element = Fallible<Tuple>
	typealias Iterator = QBEPostgresResult

	fileprivate let connection: QBEPostgresConnection
	fileprivate var result: OpaquePointer?
	fileprivate let columns: OrderedSet<Column>
	fileprivate let columnTypes: [Oid]
	fileprivate(set) var finished = false
	fileprivate(set) var error: String? = nil
	
	/* The following lists OIDs for PostgreSQL system types. This was generated using the following query on a vanilla
	Postgres installation (much less hassle than using the pg_type.h header...):
	SELECT 'private static let kType' || initcap(typname) || ' : Oid = ' || oid FROM pg_type WHERE typbyval */
	
	static func create(_ connection: QBEPostgresConnection) -> Fallible<QBEPostgresResult> {
		// Get column names from result set
		var resultFallible: Fallible<QBEPostgresResult> = .failure("Unknown error")
		
		(connection.queue).sync {
			if let result = PQgetResult(connection.connection) {
				let status = PQresultStatus(result)
				if status.rawValue != PGRES_TUPLES_OK.rawValue && status.rawValue != PGRES_SINGLE_TUPLE.rawValue && status.rawValue != PGRES_COMMAND_OK.rawValue {
					resultFallible = .failure(connection.lastError)

					// On error, call PQgetresult anyway to ensure that the command has fully finished
					while PQgetResult(connection.connection) != nil {
						trace("Extraneous result!")
					}
					return
				}

				if status.rawValue == PGRES_COMMAND_OK.rawValue {
					// This result code indicates our command completed successfully. There is no data, so no need to enumerate columns, etc.
					resultFallible = .success(QBEPostgresResult(connection: connection, result: result, columns: [], columnTypes: []))

					// On PGRES_COMMAND_OK, call PQgetresult anyway to ensure that the command has fully finished
					while PQgetResult(connection.connection) != nil {
						trace("Extraneous result!")
					}
					return
				}
				
				var columns: OrderedSet<Column> = []
				var columnTypes: [Oid] = []
				
				let colCount = PQnfields(result)
				for colIndex in 0..<colCount {
					if let column = PQfname(result, colIndex) {
						if let name = String(cString: column, encoding: String.Encoding.utf8) {
							columns.append(Column(String(name)))
							let type = PQftype(result, colIndex)
							columnTypes.append(type)
						}
						else {
							resultFallible = .failure(NSLocalizedString("PostgreSQL returned an invalid column name.", comment: ""))
							return
						}
					}
					else {
						resultFallible = .failure(NSLocalizedString("PostgreSQL returned an invalid column.", comment: ""))
						return
					}
				}
				
				resultFallible = .success(QBEPostgresResult(connection: connection, result: result, columns: columns, columnTypes: columnTypes))
			}
			else {
				resultFallible = .failure(connection.lastError)
			}
		}
		
		return resultFallible
	}
	
	private init(connection: QBEPostgresConnection, result: OpaquePointer, columns: OrderedSet<Column>, columnTypes: [Oid]) {
		self.connection = connection
		self.result = result
		self.columns = columns
		self.columnTypes = columnTypes
	}
	
	func finish() {
		_finish(false)
	}
	
	private func _finish(_ warn: Bool) {
		if !self.finished {
			/* A new query cannot be started before all results from the previous one have been fetched, because packets
			will get out of order. */
			var n = 0
			while let r = self.row() {
				if case .failure(let e) = r {
					#if DEBUG
						if warn {
							trace("Unfinished result was destroyed, drained \(n) rows to prevent packet errors, errored \(e). This is a performance issue!")
						}
					#endif
					self.finished = true
					return
				}
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
	}
	
	func makeIterator() -> Iterator {
		return self
	}
	
	func next() -> Element? {
		return row()
	}
	
	func row() -> Fallible<Tuple>? {
		var rowDataset: [Value]? = nil
		
		self.connection.queue.sync {
			if self.result == nil {
				self.result = PQgetResult(self.connection.connection)
			}
			
			// Because we are in single-row mode, each result set should only contain a single tuple.
			if self.result != nil {
				if PQntuples(self.result) == 1 && PQresultStatus(self.result).rawValue == PGRES_SINGLE_TUPLE.rawValue {
					rowDataset = []
					rowDataset!.reserveCapacity(self.columns.count)
					
					for colIndex in 0..<self.columns.count {
						if let val = PQgetvalue(self.result, Int32(0), Int32(colIndex)) {
							if PQgetisnull(self.result, Int32(0), Int32(colIndex)) == 1 {
								rowDataset!.append(Value.empty)
							}
							else {
								if let stringValue = String(cString: val, encoding: String.Encoding.utf8) {
									if let type = QBEPostgresType(rawValue: PQftype(self.result, Int32(colIndex))) {
										switch type {
										case .int8, .int4, .int2:
											if let iv = stringValue.toInt() {
												rowDataset!.append(Value.int(iv))
											}
											else {
												rowDataset!.append(Value.invalid)
											}

										case .float4, .float8:
											if let dv = stringValue.toDouble() {
												rowDataset!.append(Value.double(dv))
											}
											else {
												rowDataset!.append(Value.invalid)
											}

										case .json, .jsonb:
											if let data = stringValue.data(using: .utf8) {
												do {
													let obj = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
													rowDataset!.append(Value(jsonObject: obj))
												}
												catch(_) {
													rowDataset!.append(.invalid)
												}
											}
											else {
												rowDataset!.append(.invalid)
											}

										case .bool:
											rowDataset!.append(Value.bool(stringValue == "t"))

										default:
											rowDataset!.append(Value.string(stringValue as String))
										}
									}
									else {
										rowDataset!.append(Value.string(stringValue as String))
									}
								}
								else {
									rowDataset!.append(Value.empty)
								}
							}
						}
						else {
							rowDataset!.append(Value.invalid)
						}
					}
				}
				else {
					self.finished = true
					if PQresultStatus(self.result).rawValue != PGRES_TUPLES_OK.rawValue && PQresultStatus(self.result).rawValue != PGRES_COMMAND_OK.rawValue {
						let status = String(cString: PQresStatus(PQresultStatus(self.result)), encoding: String.Encoding.utf8) ?? "(unknown status)"
						let error = String(cString: PQresultErrorMessage(self.result), encoding: String.Encoding.utf8) ?? "(unknown error)"
						self.error = error
						trace("PostgreSQL no result: \(status) \(error)")
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
			return .failure(e)
		}
		else if let r = rowDataset {
			return .success(r)
		}
		else {
			return nil
		}
	}
}

class QBEPostgresMutableDataset: SQLMutableDataset {
	override func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		let s = self.database as! QBEPostgresDatabase
		let tableIdentifier = s.dialect.tableIdentifier(self.tableName, schema: self.schemaName, database: nil)
		let query = "SELECT a.attname AS attname, format_type(a.atttypid, a.atttypmod) AS data_type FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) WHERE  i.indrelid = '\(tableIdentifier)'::regclass AND i.indisprimary"
		switch s.connect() {
		case .success(let connection):
			switch connection.query(query)  {
			case .success(let result):
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
					return callback(.failure(NSLocalizedString("This table does not have a primary key, which is required in order to be able to identify individual rows.", comment: "")))
				}

				callback(.success(primaryColumns))

			case .failure(let e):
				return callback(.failure(e))
			}

		case .failure(let e):
			return callback(.failure(e))
		}
	}
}

class QBEPostgresDatabase: SQLDatabase {
	fileprivate let host: String
	fileprivate let port: Int
	fileprivate let user: String
	fileprivate let password: String
	fileprivate let database: String

	let dialect: SQLDialect = QBEPostgresDialect()
	var databaseName: String? { return self.database }
	
	init(host: String, port: Int, user: String, password: String, database: String) {
		self.host = host
		self.port = port
		self.user = user
		self.password = password
		self.database = database
	}
	
	func isCompatible(_ other: QBEPostgresDatabase) -> Bool {
		return self.host == other.host && self.user == other.user && self.password == other.password && self.port == other.port
	}

	func dataForTable(_ table: String, schema: String?, job: Job, callback: (Fallible<Dataset>) -> ()) {
		switch QBEPostgresDataset.create(database: self, tableName: table, schemaName: schema ?? "") {
		case .success(let d): callback(.success(d))
		case .failure(let e): callback(.failure(e))
		}
	}
	
	func databases(_ callback: (Fallible<[String]>) -> ()) {
		let sql = "SELECT datname FROM pg_catalog.pg_database WHERE NOT datistemplate"
		callback(self.connect().use {
			$0.query(sql).use {(result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .success(let infoRow) = d {
						if let name = infoRow[0].stringValue {
							dbs.append(name)
						}
					}
				}
				return dbs
			}
		})
	}
	
	func tables(_ databaseName: String, schemaName: String, callback: (Fallible<[String]>) -> ()) {
		let ts = self.dialect.expressionToSQL(Literal(Value(schemaName)), alias: "s", foreignAlias: nil, inputValue: nil)!
		let tc = self.dialect.expressionToSQL(Literal(Value(databaseName)), alias: "s", foreignAlias: nil, inputValue: nil)!

		let sql = "SELECT table_name FROM information_schema.tables t WHERE t.table_schema = \(ts)  AND t.table_catalog = \(tc)"
		callback(self.connect().use {
			$0.query(sql).use { (result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .success(let infoRow) = d {
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
	func serverInformation(_ callback: (Fallible<String>) -> ()) {
		switch self.connect() {
		case .success(let con):
			switch con.query("SELECT version()") {
			case .success(let result):
				if let rowFallible = result.row() {
					switch rowFallible {
					case .success(let row):
						if let version = row.first?.stringValue {
							callback(.success(version))
						}
						else {
							callback(.failure("No or invalid version string returned"))
						}

					case .failure(let e):
						callback(.failure(e))
					}
				}
				else {
					callback(.failure("No version returned"))
				}

			case .failure(let e): callback(.failure(e))
			}

		case .failure(let e): callback(.failure(e))
		}
	}

	func schemas(_ databaseName: String, callback: (Fallible<[String]>) -> ()) {
		let cn = self.dialect.expressionToSQL(Literal(Value(databaseName)), alias: "s", foreignAlias: nil, inputValue: nil)!
		let sql = "SELECT s.schema_name FROM information_schema.schemata s WHERE catalog_name=\(cn)"
		callback(self.connect().use {
			$0.query(sql).use { (result) -> [String] in
				var dbs: [String] = []
				while let d = result.row() {
					if case .success(let infoRow) = d {
						if let schemaName = infoRow[0].stringValue {
							dbs.append(schemaName)
						}
					}
				}
				return dbs
			}
		})
	}

	func connect(_ callback: (Fallible<SQLConnection>) -> ()) {
		callback(self.connect().use { return $0 })
	}

	func connect() -> Fallible<QBEPostgresConnection> {
		let userEscaped = self.user.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlUserAllowed)!
		let passwordEscaped = self.password.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPasswordAllowed)!
		let hostEscaped = self.host.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!
		let databaseEscaped = self.database.isEmpty ? "" : ("/"+(self.database.urlEncoded ?? ""))
		let url = "postgres://\(userEscaped):\(passwordEscaped)@\(hostEscaped):\(self.port)\(databaseEscaped)"
		
		if let connection = PQconnectdb(url) {
			switch PQstatus(connection).rawValue {
				case CONNECTION_OK.rawValue:
					return .success(QBEPostgresConnection(database: self, connection: connection))
				
				case CONNECTION_BAD.rawValue:
					let error = String(cString:  PQerrorMessage(connection), encoding: String.Encoding.utf8) ?? "(unknown error)"
					return .failure(error)
					
				default:
					return .failure(String(format: NSLocalizedString("Unknown connection status: %d", comment: ""), PQstatus(connection).rawValue))
			}
		}
		else {
			return .failure("(uknown error)")
		}
	}
}

/**
Implements a connection to a PostgreSQL database (corresponding to a MYSQL object in the PostgreSQL library). The connection ensures
that any operations are serialized (for now using a global queue for all PostgreSQL operations). */
internal class QBEPostgresConnection: SQLConnection {
	fileprivate(set) var database: QBEPostgresDatabase
	fileprivate var connection: OpaquePointer?
	fileprivate(set) weak var result: QBEPostgresResult?
	fileprivate let queue : DispatchQueue
	
	fileprivate init(database: QBEPostgresDatabase, connection: OpaquePointer) {
		self.connection = connection
		self.database = database
		self.queue = DispatchQueue(label: "QBEPostgresConnection.Queue")
	}
	
	deinit {
		if connection != nil {
			queue.sync {
				PQfinish(self.connection)
			}
		}
	}
	
	func clone() -> Fallible<QBEPostgresConnection> {
		return self.database.connect()
	}

	func run(_ sql: [String], job: Job, callback: (Fallible<Void>) -> ()) {
		for q in sql {
			let res = self.query(q)
			if case .failure(let e) = res {
				callback(.failure(e))
				return
			}
		}

		callback(.success())
	}

	/** Fetches the server version number. This number can be used to enable/disable certain features by version. */
	func serverVersion(_ callback: (Fallible<String>) -> ()) {
		switch self.query("SHOW server_version") {
		case .success(let result):
			if let rowFallible = result.row() {
				result.finish()

				switch rowFallible {
				case .success(let row):
					if let version = row.first?.stringValue {
						return callback(.success(version))
					}
					else {
						return callback(.failure("No or invalid version string returned"))
					}

				case .failure(let e):
					return callback(.failure(e))
				}
			}
			else {
				result.finish()
				return callback(.failure("No version returned"))
			}

		case .failure(let e): callback(.failure(e))
		}
	}

	fileprivate func perform(_ block: () -> (Bool)) -> Bool {
		var success: Bool = false
		queue.sync {
			let result = block()
			if !result {
				let message = String(cString:  PQerrorMessage(self.connection), encoding: String.Encoding.utf8) ?? "(unknown)"
				trace("PostgreSQL perform error: \(message)")
				success = false
			}
			else {
				success = true
			}
		}
		return success
	}
	
	fileprivate var lastError: String { get {
			return String(cString:  PQerrorMessage(self.connection), encoding: String.Encoding.utf8) ?? "(unknown)"
	} }
	
	func query(_ sql: String) -> Fallible<QBEPostgresResult> {
		if self.result != nil && !self.result!.finished {
			fatalError("Cannot start a query when the previous result is not finished yet")
		}
		
		#if DEBUG
			trace("PostgreSQL Query \(sql)")
		#endif
		
		if self.perform({
			if PQsendQuery(self.connection, sql.cString(using: String.Encoding.utf8)!) == 1 {
				PQsetSingleRowMode(self.connection)
				return true
			}
			return false
		}) {
			let result = QBEPostgresResult.create(self)
			switch result {
				case .success(let r):
					self.result = r
				
				case .failure(_):
					self.result = nil
			}
			return result
		}
		
		return .failure(self.lastError)
	}
}

/**
Represents the result of a PostgreSQL query as a Dataset object. */
class QBEPostgresDataset: SQLDataset {
	private let database: QBEPostgresDatabase

	static func create(database: QBEPostgresDatabase, tableName: String, schemaName: String) -> Fallible<QBEPostgresDataset> {
		let query = "SELECT * FROM \(database.dialect.tableIdentifier(tableName, schema: schemaName, database: database.database)) LIMIT 1"
		return database.connect().use {
			$0.query(query).use {(result) -> QBEPostgresDataset in
				result.finish() // We're not interested in that one row we just requested, just the column names
				return QBEPostgresDataset(database: database, schema: schemaName, table: tableName, columns: result.columns)
			}
		}
	}
	
	private init(database: QBEPostgresDatabase, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.database = database
		super.init(fragment: fragment, columns: columns)
	}
	
	private init(database: QBEPostgresDatabase, schema: String, table: String, columns: OrderedSet<Column>) {
		self.database = database
		super.init(table: table, schema: schema, database: database.database, dialect: database.dialect, columns: columns)
	}
	
	override func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return QBEPostgresDataset(database: self.database, fragment: fragment, columns: resultingColumns)
	}
	
	override func stream() -> WarpCore.Stream {
		return QBEPostgresStream(data: self)
	}
	
	fileprivate func result() -> Fallible<QBEPostgresResult> {
		return database.connect().use {
			$0.query(self.sql.sqlSelect(nil).sql)
		}
	}
	
	override func isCompatibleWith(_ other: SQLDataset) -> Bool {
		if let om = other as? QBEPostgresDataset {
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
private class QBEPostgresResultStream: SequenceStream {
	init(result: QBEPostgresResult) {
		super.init(AnySequence<Fallible<Tuple>>(result), columns: result.columns)
	}
	
	override func clone() -> WarpCore.Stream {
		fatalError("QBEPostgresResultStream cannot be cloned, because a result cannot be iterated multiple times. Clone QBEPostgresStream instead")
	}
}

/** Stream that lazily queries and streams results from a PostgreSQL query.
*/
class QBEPostgresStream: WarpCore.Stream {
	private var resultStream: WarpCore.Stream?
	private let data: QBEPostgresDataset
	private let mutex = Mutex()
	
	init(data: QBEPostgresDataset) {
		self.data = data
	}
	
	private func stream() -> WarpCore.Stream {
		return mutex.locked {
			if resultStream == nil {
				switch data.result() {
					case .success(let rs):
						resultStream = QBEPostgresResultStream(result: rs)
					
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
		self.tableName = (aDecoder.decodeObject(forKey: "tableName") as? String) ?? ""
		self.host = (aDecoder.decodeObject(forKey: "host") as? String) ?? ""
		self.databaseName = (aDecoder.decodeObject(forKey: "database") as? String) ?? ""
		self.user = (aDecoder.decodeObject(forKey: "user") as? String) ?? ""
		self.port = Int(aDecoder.decodeInteger(forKey: "port"))
		self.schemaName = aDecoder.decodeString(forKey:"schema") ?? ""
		super.init(coder: aDecoder)

		if let pw = (aDecoder.decodeObject(forKey: "password") as? String) {
			self.password.stringValue = pw
		}
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(tableName, forKey: "tableName")
		coder.encode(host, forKey: "host")
		coder.encode(user, forKey: "user")
		coder.encode(databaseName, forKey: "database")
		coder.encode(port , forKey: "port")
		coder.encodeString(schemaName , forKey: "schema")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .neutral, .read:
			template = "Load table [#] from schema [#] in PostgreSQL database [#]"

		case .write:
			template = "Write to table [#] in schema [#] in PostgreSQL database [#]"
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceDynamicOptionsToken(value: self.tableName , provider: { (callback) -> () in
				if let d = self.database {
					d.tables(self.databaseName , schemaName: self.schemaName ) { tablesFallible in
						switch tablesFallible {
						case .success(let tables):
							callback(.success(tables))

						case .failure(let e):
							callback(.failure(e))
						}
					}
				}
				else {
					callback(.failure(NSLocalizedString("Could not connect to database", comment: "")))
				}
			}, callback: { (newTable) -> () in
				self.tableName = newTable
			}),

			QBESentenceDynamicOptionsToken(value: self.schemaName, provider: { (callback) -> () in
				if let d = self.database {
					d.schemas(self.databaseName ) { schemaFallible in
						switch schemaFallible {
						case .success(let dbs):
							callback(.success(dbs))

						case .failure(let e):
							callback(.failure(e))
						}
					}
				}
				else {
					callback(.failure(NSLocalizedString("Could not connect to database", comment: "")))
				}
			}, callback: { (newSchema) -> () in
					self.schemaName = newSchema
			}),

			QBESentenceDynamicOptionsToken(value: self.databaseName , provider: { (callback) -> () in
				if let d = self.database {
					d.databases { dbFallible in
						switch dbFallible {
						case .success(let dbs):
							callback(.success(dbs))

						case .failure(let e):
							callback(.failure(e))
						}
					}
				}
				else {
					callback(.failure(NSLocalizedString("Could not connect to database", comment: "")))
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

	override var mutableDataset: MutableDataset? {
		if let d = self.database, !tableName.isEmpty && !schemaName.isEmpty {
			return QBEPostgresMutableDataset(database: d, schemaName: schemaName, tableName: tableName)
		}
		return nil
	}

	var warehouse: Warehouse? {
		if let d = self.database, !schemaName.isEmpty {
			return SQLWarehouse(database: d, schemaName: schemaName)
		}
		return nil
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		job.async {
			if let s = self.database {
				// Check whether the connection details are right
				switch s.connect() {
				case .success(_):
					if !self.tableName.isEmpty {
						callback(QBEPostgresDataset.create(database: s, tableName: self.tableName, schemaName: self.schemaName).use({ return $0.coalesced }))
					}
					else {
						callback(.failure(NSLocalizedString("No database or table selected", comment: "")))
					}

				case .failure(let e):
					callback(.failure(e))
				}
			}
			else {
				callback(.failure(NSLocalizedString("No database or table selected", comment: "")))
			}
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job, callback: { (fd) -> () in
			callback(fd.use({$0.random(maxInputRows)}))
		})
	}
}
