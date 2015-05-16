import Foundation

private class QBEMySQLDialect: QBEStandardSQLDialect {
	override var identifierQualifier: String { get { return  "`" } }
	override var identifierQualifierEscape: String { get { return  "\\`" } }
	
	override func unaryToSQL(type: QBEFunction, args: [String]) -> String? {
		let value = args.implode(", ") ?? ""
		
		if type == QBEFunction.Random {
			return "RAND(\(value))"
		}
		return super.unaryToSQL(type, args: args)
	}
	
	private override func aggregationToSQL(aggregation: QBEAggregation, alias: String) -> String? {
		// For QBEFunction.Count, we should count numeric values only. In MySQL this can be done using REGEXP
		if aggregation.reduce == QBEFunction.Count {
			if let expressionSQL = expressionToSQL(aggregation.map, alias: alias) {
				return "SUM(CASE WHEN \(expressionSQL) REGEXP '^[[:digit:]]+$') THEN 1 ELSE 0 END)"
			}
			return nil
		}
		
		return super.aggregationToSQL(aggregation, alias: alias)
	}
	
	private override func forceStringExpression(expression: String) -> String {
		return "CAST(\(expression) AS BINARY)"
	}
	
	private override func forceNumericExpression(expression: String) -> String {
		return "CAST(\(expression) AS DECIMAL)"
	}
}

internal class QBEMySQLResult: SequenceType, GeneratorType {
	typealias Element = QBETuple
	typealias Generator = QBEMySQLResult
	
	private let connection: QBEMySQLConnection
	private let result: UnsafeMutablePointer<MYSQL_RES>
	private(set) var columnNames: [QBEColumn] = []
	private(set) var columnTypes: [MYSQL_FIELD] = []
	private(set) var finished = false
	
	init?(_ result: UnsafeMutablePointer<MYSQL_RES>, connection: QBEMySQLConnection) {
		self.result = result
		self.connection = connection
		
		// Get column names from result set
		var failed = false
		dispatch_sync(QBEMySQLConnection.sharedQueue) {
			let colCount = mysql_field_count(connection.connection)
			for colIndex in 0..<colCount {
				let column = mysql_fetch_field(self.result)
				if column != nil {
					if let name = NSString(bytes: column.memory.name, length: Int(column.memory.name_length), encoding: NSUTF8StringEncoding) {
						self.columnNames.append(QBEColumn(String(name)))
						self.columnTypes.append(column.memory)
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
		
		let result = self.result
		dispatch_sync(QBEMySQLConnection.sharedQueue) {
			mysql_free_result(result)
			return
		}
	}
	
	func generate() -> Generator {
		return self
	}
	
	func next() -> Element? {
		return row()
	}
	
	func row() -> [QBEValue]? {
		var rowData: [QBEValue]? = nil
		
		dispatch_sync(QBEMySQLConnection.sharedQueue) {
			let row: MYSQL_ROW = mysql_fetch_row(self.result)
			if row != nil {
				rowData = []
				rowData!.reserveCapacity(self.columnNames.count)
				
				for cn in 0..<self.columnNames.count {
					let val = row[cn]
					if val == nil {
						rowData!.append(QBEValue.EmptyValue)
					}
					else {
						// Is this a numeric field?
						let type = self.columnTypes[cn]
						if (Int32(type.flags) & NUM_FLAG) != 0 {
							if type.type.value == MYSQL_TYPE_TINY.value
								|| type.type.value == MYSQL_TYPE_SHORT.value
								|| type.type.value == MYSQL_TYPE_LONG.value
								|| type.type.value == MYSQL_TYPE_INT24.value
								|| type.type.value == MYSQL_TYPE_LONGLONG.value {
									if let str = String(CString: val, encoding: NSUTF8StringEncoding), let nt = str.toInt() {
										rowData!.append(QBEValue.IntValue(nt))
									}
									else {
										rowData!.append(QBEValue.InvalidValue)
									}
									
							}
							else {
								if let str = String(CString: val, encoding: NSUTF8StringEncoding) {
									if let dbl = str.toDouble() {
										rowData!.append(QBEValue.DoubleValue(dbl))
									}
									else {
										rowData!.append(QBEValue.StringValue(str))
									}
								}
								else {
									rowData!.append(QBEValue.InvalidValue)
								}
							}
						}
						else {
							//let value = NSString(bytes: row, length: Int(column.memory.name_length), encoding: NSUTF8StringEncoding);
							if let str = String(CString: val, encoding: NSUTF8StringEncoding) {
								rowData!.append(QBEValue.StringValue(str))
							}
							else {
								rowData!.append(QBEValue.InvalidValue)
							}
						}
					}
				}
			}
			else {
				self.finished = true
			}
		}
		
		return rowData
	}
}

internal class QBEMySQLConnection {
	private var connection: UnsafeMutablePointer<MYSQL>
	private let dialect: QBESQLDialect
	private(set) weak var result: QBEMySQLResult?
	let url: String
	
	class var sharedQueue : dispatch_queue_t {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : dispatch_queue_t? = nil
		}
		dispatch_once(&Static.onceToken) {
			/* Mysql_library_init is what we should call, but as it is #defined to mysql_server_init, Swift doesn't see it. 
			So we just call mysql_server_int. */
			if mysql_server_init(0, nil, nil) == 0 {
				Static.instance = dispatch_queue_create("QBEMySQLConnection.Queue", DISPATCH_QUEUE_SERIAL)
				dispatch_set_target_queue(Static.instance, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
			}
			else {
				QBELog("Error initializing MySQL library")
			}
		}
		return Static.instance!
	}
	
	init?(host: String, port: Int, user: String, password: String, database: String) {
		self.dialect = QBEMySQLDialect()
		self.connection = nil
		self.url = NSURL(scheme: "mysql", host: "\(host):\(port)", path: "/\(user)")!.absoluteString!
		
		self.perform({() -> Int32 in
			self.connection = mysql_init(nil)
			mysql_real_connect(self.connection,
				host.cStringUsingEncoding(NSUTF8StringEncoding)!,
				user.cStringUsingEncoding(NSUTF8StringEncoding)!,
				password.cStringUsingEncoding(NSUTF8StringEncoding)!,
				/*database.cStringUsingEncoding(NSUTF8StringEncoding)!,*/ nil,
				UInt32(port),
				UnsafePointer<Int8>(nil),
				UInt(0)
			)
			return Int32(mysql_errno(self.connection))
		})
		
		if let dbn = database.cStringUsingEncoding(NSUTF8StringEncoding) where !database.isEmpty {
			self.perform({() -> Int32 in
				return mysql_select_db(self.connection, dbn)
			})
		}
	}
	
	deinit {
		if connection != nil {
			dispatch_sync(QBEMySQLConnection.sharedQueue) {
				mysql_close(self.connection)
			}
		}
	}
	
	func databases(callback: ([String]) -> ()) {
		if let r = self.query("SHOW DATABASES") {
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
		if let r = self.query("SHOW TABLES") {
			var dbs: [String] = []
			while let d = r.row() {
				if let name = d[0].stringValue {
					dbs.append(name)
				}
			}
			
			callback(dbs)
		}
	}
	
	private func perform(block: () -> (Int32)) -> Bool {
		var success: Bool = false
		dispatch_sync(QBEMySQLConnection.sharedQueue) {
			let result = block()
			if result != 0 {
				let message = String(CString: mysql_error(self.connection), encoding: NSUTF8StringEncoding)
				QBELog("MySQL perform error: \(message)")
				success = false
			}
			success = true
		}
		return success
	}
	
	func query(sql: String) -> QBEMySQLResult? {
		if self.result != nil && !self.result!.finished {
			fatalError("Cannot start a query when the previous result is not finished yet")
		}
		self.result = nil
		
		#if DEBUG
			QBELog("MySQL Query \(sql)")
		#endif

		if self.perform({return mysql_query(self.connection, sql.cStringUsingEncoding(NSUTF8StringEncoding)!)}) {
			let result = QBEMySQLResult(mysql_use_result(self.connection), connection: self)
			self.result = result
			return result
		}
		return nil
	}
}

func == (lhs: QBEMySQLConnection, rhs: QBEMySQLConnection) -> Bool {
	return lhs.url == rhs.url
}

class QBEMySQLData: QBESQLData {
	private let db: QBEMySQLConnection
	private let locale: QBELocale?
	
	private convenience init(db: QBEMySQLConnection, tableName: String, locale: QBELocale?) {
		let query = "SELECT * FROM \(db.dialect.tableIdentifier(tableName)) LIMIT 1"
		let result = db.query(query)
		result?.finish() // We're not interested in that one row we just requested, just the column names
		
		self.init(db: db, table: tableName, columns: result?.columnNames ?? [], locale: locale)
	}
	
	private init(db: QBEMySQLConnection, fragment: QBESQLFragment, columns: [QBEColumn], locale: QBELocale?) {
		self.db = db
		self.locale = locale
		super.init(fragment: fragment, columns: columns)
	}
	
	private init(db: QBEMySQLConnection, table: String, columns: [QBEColumn], locale: QBELocale?) {
		self.db = db
		self.locale = locale
		super.init(table: table, dialect: db.dialect, columns: columns)
	}
	
	override func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBEMySQLData(db: self.db, fragment: fragment, columns: resultingColumns, locale: locale)
	}
	
	override func stream() -> QBEStream {
		if let result = self.db.query(self.sql.sqlSelect(nil).sql) {
			return QBESequenceStream(SequenceOf<QBETuple>(result), columnNames: result.columnNames)
		}
		return QBEEmptyStream()
	}
	
	override func isCompatibleWith(other: QBESQLData) -> Bool {
		if let om = other as? QBEMySQLData {
			if om.db == self.db {
				return true
			}
		}
		return false
	}
}

class QBEMySQLSourceStep: QBEStep {
	var tableName: String?
	var host: String?
	var user: String?
	var password: String?
	var database: String?
	var port: Int?
	
	init(host: String, port: Int, user: String, password: String, database: String, tableName: String) {
		self.host = host
		self.user = user
		self.password = password
		self.port = port
		self.database = database
		self.tableName = tableName
		super.init(previous: nil)
	}
	
	required init(coder aDecoder: NSCoder) {
		self.tableName = (aDecoder.decodeObjectForKey("tableName") as? String) ?? ""
		self.host = (aDecoder.decodeObjectForKey("host") as? String) ?? ""
		self.database = (aDecoder.decodeObjectForKey("database") as? String) ?? ""
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
		coder.encodeObject(database, forKey: "database")
		coder.encodeInt(Int32(port ?? 0), forKey: "port")
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("MySQL table", comment: "")
		}
		return String(format: NSLocalizedString("Load table %@ from MySQL database", comment: ""), self.tableName ?? "")
	}
	
	internal func db() -> QBEMySQLConnection? {
		if let h = host, p = port, u = user, pw = password, d = database {
			/* For MySQL, the hostname 'localhost' is special and indicates access through a local UNIX socket. This does
			not work from a sandboxed application unless special privileges are obtained. To avoid confusion we rewrite 
			localhost here to 127.0.0.1 in order to force access through TCP/IP. */
			let ha = (h == "localhost") ? "127.0.0.1" : h
			return QBEMySQLConnection(host: ha, port: p, user: u, password: pw, database: d)
		}
		return nil
	}
	
	override func fullData(job: QBEJob?, callback: (QBEData) -> ()) {
		QBEAsyncBackground {
			if let d = self.db() {
				callback(QBECoalescedData(QBEMySQLData(db: d, tableName: self.tableName ?? "", locale: QBEAppDelegate.sharedInstance.locale)))
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