import Foundation

/** The SQL family of classes enables data operations to be pushed down to SQL for efficient execution. In order for
this to work properly and consistently, the calculations need to behave exactly like the (in-memory) reference 
implementations provided by Raster/Stream. There are two problems associated with that:

- The SQL type system is different than the Warp type system. A lot has been done to align the two type systems closely.
  * The Value types map rougly to the basic SQL types VARCHAR/TEXT (StringValue), BOOL or INT (BoolValue), DOUBLE
    (DoubleValue), INT (IntValue).

  * The EmptyValue maps to an empty string in expressions. NULLs received from the database are coalesced to empty 
	strings in expressions, or returned as EmptyValue.

  * InvalidValue always maps to the result of the expression "(1/0)" in SQL.

- Generating SQL statements that work across a large number of different implementations. 

   * Some functions are not supported by a DBMS or have a different name and specification (e.g. GROUP_CONCAT in MySQL
     is roughly similar to String_Agg in Postgres).

   * Functions can behave differently between implementations (e.g. CONCAT can take 2+ values on most DBMS'es, but not on
      Presto, where it can take only two)

   * There may be subtly differences between the handling of types (DBMS'es differ especially on whether they cast values
     'softly' to another type, e.g. when comparing or using for ordering).

   * Corner case behaviour may be different. An example is the usage of "LIMIT 0" to obtain information about the columns
     a query would result in.
   
   In order to overcome the differences between DBMS'es, Warp uses the concept of a "SQL Dialect" which defines the mapping
   from and to SQL for different SQL vendors. The default dialect closely matches SQL/92. For each vendor, a subclass of
   SQLDialect defines exceptions.

- The DBMS may use a different locale than the application. Care is taken not to rely too much on locale-dependent parts.

Even with the measures above in place, there may still be differences between our reference implementation and SQL. */

/** Classes that implement SQLDialect provide SQL generating classes with tools to build SQL queries in a particular
dialect. The standard dialect (implemented in StandardSQLDialect) sticks as closely to the SQL92 standard (to implement
a particular dialect, the standard dialect should be subclassed and should only implement the exceptions). */
public protocol SQLDialect {
	/** The string that starts and ends a string literal. */
	var stringQualifier: String { get }
	
	/** The escape character used inside string literals to escape special characters. Usually '\' */
	var stringEscape: String { get }
	
	/** The string that is used to escape occurrences of the string qualifier in a literal. All occurrences are replaced
	with the escape qualifier before the string is inserted in SQL. */
	var stringQualifierEscape: String { get }
	
	/** The string that is used to start and end identifiers (e.g. table or column names) in SQL. */
	var identifierQualifier: String { get }
	
	/** The string that is used to escape the identifier qualifier in identifiers that contain it. */
	var identifierQualifierEscape: String { get }
	
	/** Returns a column identifier for the given Column. */
	func columnIdentifier(column: Column, table: String?, schema: String?, database: String?) -> String
	
	/** Returns the identifier that represents all columns in the given table (e.g. "table.*" or just "*". */
	func allColumnsIdentifier(table: String?, schema: String?, database: String?) -> String
	
	func tableIdentifier(table: String, schema: String?, database: String?) -> String
	
	/** Transforms the given expression to a SQL string. The inputValue parameter determines the return value of the
	Identity expression. The function may return nil for expressions it cannot successfully transform to SQL. */
	func expressionToSQL(formula: Expression, alias: String, foreignAlias: String?, inputValue: String?) -> String?
	
	func unaryToSQL(type: Function, args: [String]) -> String?
	func binaryToSQL(type: Binary, first: String, second: String) -> String?
	
	/** Transforms the given aggregation to an aggregation description that can be incldued as part of a GROUP BY 
	statement. The function may return nil for aggregations it cannot represent or transform to SQL. */
	func aggregationToSQL(aggregation: Aggregation, alias: String) -> String?
	
	/** Create an expression that forces the specified expression to a numeric type (DOUBLE or INT in SQL). */
	func forceNumericExpression(expression: String) -> String
	
	/** Create an expression that forces the specified expression to a string type (e.g. VARCHAR or TEXT in SQL). */
	func forceStringExpression(expression: String) -> String
	
	/** Returns the SQL name for the indicates join type, or nil if that join type is not supported */
	func joinType(type: JoinType) -> String?

	/** Whether this database supports changing column definitions (or dropping columns) using an ALTER TABLE statement 
	(if false, any changes can only be made by dropping and recreating the table). If false, the database should still
	support ALTER TABLE to add columns. **/
	var supportsChangingColumnDefinitionsWithAlter: Bool { get }
}

/** Represents a particular SQL database. In most cases, this will be a catalog or database on a particular database 
server. Some 'flat' databases do not have the concept of separate databases. In this case, there is one database per
connection/file (e.g. for SQLite). */
public protocol SQLDatabase {
	var dialect: SQLDialect { get }

	/** The name that can be used to refer to this database in SQL queries performed on the connection. */
	var databaseName: String? { get }

	/** Create a connection over which queries can be sent to this database. */
	func connect(callback: (Fallible<SQLConnection>) -> ())

	/** Creates a Data object that can be used to read data from a table in the specified schema (if any) in this
	database. For databases that do not support schemas the schema parameter must be nil. */
	func dataForTable(table: String, schema: String?, job: Job, callback: (Fallible<Data>) -> ())
}

public protocol SQLConnection {
	/** Serially perform the indicate SQL data definition commands in the order specified. The callback is called after 
	the first error is encountered, or when all queries have been executed successfully. Depending on the support of the 
	database, wrapping in a transaction is possible by issuing 'BEGIN'  and 'COMMIT'  commands. Whenever an
	error is encountered, no further query processing should happen. */
	func run(sql: [String], job: Job, callback: (Fallible<Void>) -> ())
}

public class SQLWarehouse: Warehouse {
	public let database: SQLDatabase
	public let schemaName: String?
	public var dialect: SQLDialect { return database.dialect }
	public let hasFixedColumns: Bool = true
	public let hasNamedTables: Bool = true

	public init(database: SQLDatabase, schemaName: String?) {
		self.database = database
		self.schemaName = schemaName
	}

	public func canPerformMutation(mutation: WarehouseMutation) -> Bool {
		switch mutation {
			case .Create(_,_):
				return true
		}
	}

	public func performMutation(mutation: WarehouseMutation, job: Job, callback: (Fallible<MutableData?>) -> ()) {
		if !canPerformMutation(mutation) {
			callback(.Failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		self.database.connect { connectionFallible in
			switch connectionFallible {
			case .Success(let con):
				switch mutation {
				// Create a table to store the given data set
				case .Create(let tableName, let data):
					// Start a transaction
					con.run(["BEGIN"], job: job) { result in
						switch result {
						case .Success(_):
							// Find out the column names of the source data
							data.columnNames(job) { columnsResult in
								switch columnsResult {
								case .Failure(let e): callback(.Failure(e))
								case .Success(let columnNames):
									// Build a 'CREATE TABLE' query and run it
									let fields = columnNames.map {
										return self.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil) + " TEXT NULL DEFAULT NULL"
									}.joinWithSeparator(", ")
									let createQuery = "CREATE TABLE \(self.dialect.tableIdentifier(tableName, schema: self.schemaName, database: self.database.databaseName)) (\(fields))";

									// Create the table
									con.run([createQuery], job: job) { createResult in
										switch createResult {
										case .Failure(let e): callback(.Failure(e))
										case .Success(_):
											// Commit the things we just did
											con.run(["COMMIT"], job: job) { commitResult in
												switch commitResult {
												case .Success:
													// Go and insert the specified data in the table
													let mutableData = SQLMutableData(database: self.database, schemaName: self.schemaName, tableName: tableName)
													let mapping = columnNames.mapDictionary { cn in return (cn, cn) }
													mutableData.performMutation(.Import(data: data, withMapping: mapping), job: job) { insertResult in
														switch insertResult {
														case .Success:
															callback(.Success(mutableData))

														case .Failure(let e): callback(.Failure(e))
														}
													}

												case .Failure(let e): callback(.Failure(e))
												}
											}
										}
									}
								}
							}
						case .Failure(let e): callback(.Failure(e))
						}
					}
				}

			case .Failure(let e):
				callback(.Failure(e))
			}
		}
	}
}

private class SQLInsertPuller: StreamPuller {
	private let columnNames: [Column]
	private var callback: ((Fallible<Void>) -> ())?
	private let fastMapping: [Int?]
	private let insertStatement: String
	private let connection: SQLConnection
	private let database: SQLDatabase

	init(stream: Stream, job: Job, columnNames: [Column], mapping: ColumnMapping, insertStatement: String, connection: SQLConnection, database: SQLDatabase, callback: ((Fallible<Void>) -> ())?) {
		self.callback = callback
		self.columnNames = columnNames
		self.insertStatement = insertStatement
		self.connection = connection
		self.database = database

		self.fastMapping = mapping.keys.map { targetField -> Int? in
			if let sourceFieldName = mapping[targetField] {
				return columnNames.indexOf(sourceFieldName)
			}
			else {
				return nil
			}
		}

		super.init(stream: stream, job: job)
	}

	override func onReceiveRows(rows: [Tuple], callback: (Fallible<Void>) -> ()) {
		self.mutex.locked {
			if !rows.isEmpty {
				let values = rows.map { row in
					let tuple = fastMapping.map { idx -> String in
						if let i = idx {
							return  self.database.dialect.expressionToSQL(Literal(row[i]), alias: "", foreignAlias: nil, inputValue: nil) ?? "NULL"
						}
						else {
							return "NULL"
						}
						}.joinWithSeparator(", ")
					return "(\(tuple))"
					}.joinWithSeparator(", ")

				let sql = "\(insertStatement) \(values)"
				connection.run([sql], job: job) { insertResult in
					switch insertResult {
					case .Failure(let e):
						callback(.Failure(e))

					case .Success(_):
						callback(.Success())
					}
				}
			}
			else {
				callback(.Success())
			}
		}
	}

	override func onDoneReceiving() {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil
			self.job.async {
				cb(.Success())
			}
		}
	}

	override func onError(error: String) {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil

			self.job.async {
				cb(.Failure(error))
			}
		}
	}
}

public class SQLMutableData: MutableData {
	public let database: SQLDatabase
	public let tableName: String
	public let schemaName: String?

	public var warehouse: Warehouse { return SQLWarehouse(database: self.database, schemaName: self.schemaName) }

	public init(database: SQLDatabase, schemaName: String?, tableName: String) {
		self.database = database
		self.tableName = tableName
		self.schemaName = schemaName
	}

	public func identifier(job: Job, callback: (Fallible<Set<Column>?>) -> ()) {
		return callback(.Failure("Not implemented"))
	}

	private var tableIdentifier: String {
		return self.database.dialect.tableIdentifier(self.tableName, schema: self.schemaName, database: self.database.databaseName)
	}

	public func data(job: Job, callback: (Fallible<Data>) -> ()) {
		self.database.dataForTable(tableName, schema: schemaName, job: job, callback: callback)
	}

	private func performInsertByPulling(connection: SQLConnection, data: Data, mapping: ColumnMapping, job: Job, callback: (Fallible<Void>) -> ()) {
		let fields = mapping.keys.map { fn in return self.database.dialect.columnIdentifier(fn, table: nil, schema: nil, database: nil) }.joinWithSeparator(", ")
		let insertStatement = "INSERT INTO \(self.tableIdentifier) (\(fields)) VALUES ";
		print(insertStatement)

		// Fetch rows and insert!
		data.columnNames(job) { columnsFallible in
			switch columnsFallible {
			case .Success(let sourceColumnNames):
				let stream = data.stream()
				let puller = SQLInsertPuller(stream: stream, job: job, columnNames: sourceColumnNames, mapping: mapping, insertStatement: insertStatement, connection: connection, database: self.database, callback: callback)
				puller.start()

			case .Failure(let e):
				callback(.Failure(e))
				return
			}
		}
	}

	private func performInsert(connection: SQLConnection, data: Data, mapping: ColumnMapping, job: Job, callback: (Fallible<Void>) -> ()) {
		if mapping.isEmpty {
			callback(.Failure("Cannot insert zero columns!"))
			return
		}

		// Is the other data set an SQL data set (or an SQL data set shrink-wrapped in CoalescedData)?
		if let otherSQL = (data as? SQLData) ?? ((data as? CoalescedData)?.data as? SQLData) {
			self.data(job) { result in
				switch result {
				case .Success(let myData):
					if let mySQLData  = myData as? SQLData where mySQLData.isCompatibleWith(otherSQL) {
						// Perform INSERT INTO ... SELECT ...
						self.database.connect { result in
							switch result {
							case .Success(let connection):
								let targetColumns = Array(mapping.keys)
								let fields = targetColumns.map { fn in return self.database.dialect.columnIdentifier(fn, table: nil, schema: nil, database: nil) }
								let otherAlias = otherSQL.sql.aliasFor(.Select)

								let selection = targetColumns.map { field in
									return otherSQL.sql.dialect.columnIdentifier(mapping[field]!, table: otherAlias, schema: nil, database: nil)
								}
								let otherSelectSQL = otherSQL.sql.sqlSelect(selection.joinWithSeparator(", "))
								let insertStatement = "INSERT INTO \(self.tableIdentifier) (\(fields.joinWithSeparator(", "))) \(otherSelectSQL.sql)";
								connection.run([insertStatement], job: job, callback: callback)

							case .Failure(let e):
								callback(.Failure(e))
								return
							}
						}
					}
					else {
						self.performInsertByPulling(connection, data: data, mapping: mapping, job: job, callback: callback)
					}

				case .Failure(let e):
					callback(.Failure(e))
					return
				}
			}
		}
		else {
			performInsertByPulling(connection, data: data, mapping: mapping, job: job, callback: callback)
		}
	}

	private func performAlter(connection: SQLConnection, columns desiredColumns: [Column], job: Job, callback: (Fallible<Void>) -> ()) {
		self.data(job) { result in
			switch result {
			case .Success(let data):
				data.columnNames(job) { result in
					switch result {
					case .Success(let existingColumns):
						var changes: [String] = []

						for dropColumn in Set(existingColumns).subtract(desiredColumns) {
							changes.append("DROP COLUMN \(self.database.dialect.columnIdentifier(dropColumn, table: nil, schema: nil, database: nil))")
						}

						/* We should probably ensure that target columns have a storage type that can accomodate our data, 
						but for now we leave the destination columns intact, to prevent unintentional (and unforeseen)
						damage to the destination table. */
						/*for changeColumn in Set(desiredColumns).intersect(existingColumns) {
							let cn = self.database.dialect.columnIdentifier(changeColumn, table: nil, schema: nil, database: nil)
							changes.append("ALTER COLUMN \(cn) \(cn) TEXT NULL DEFAULT NULL")
						}*/

						for addColumn in Set(desiredColumns).subtract(existingColumns) {
							changes.append("ADD COLUMN \(self.database.dialect.columnIdentifier(addColumn, table: nil, schema: nil, database: nil)) TEXT NULL DEFAULT NULL")
						}

						if changes.count > 0 {
							let sql = "ALTER TABLE \(self.tableIdentifier) \(changes.joinWithSeparator(", "))"
							connection.run([sql], job: job, callback: callback)
						}
						else {
							// No change required
							callback(.Success())
						}

					case .Failure(let e): callback(.Failure(e))
					}
				}

			case .Failure(let e): callback(.Failure(e))
			}
		}
	}

	public func performMutation(mutation: DataMutation, job: Job, callback: (Fallible<Void>) -> ()) {
		if !canPerformMutation(mutation) {
			callback(.Failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		job.async {
			self.database.connect({ (connectionFallible) -> () in
				switch connectionFallible {
					case .Success(let con):
						switch mutation {
						case .Drop:
							con.run(["DROP TABLE \(self.tableIdentifier)"], job: job, callback: callback)

						case .Truncate:
							// TODO: MySQL supports TRUNCATE TABLE which supposedly is faster
							con.run(["DELETE FROM \(self.tableIdentifier)"], job: job, callback: callback)

						case .Alter(let columns):
							self.performAlter(con, columns: columns.columnNames, job: job, callback: callback)

						case .Import(data: let data, withMapping: let mapping):
							self.performInsert(con, data: data, mapping: mapping, job: job, callback: callback)

						case .Update(key: _, column: _, old: _, new: _):
							callback(.Failure("Not implemented"))

						case .Edit(_,_,_,_), .Insert(row: _), .Rename(_):
							fatalError("Not supported")
						}

					case .Failure(let e):
						callback(.Failure(e))
				}
			})
		}
	}

	public func canPerformMutation(mutation: DataMutation) -> Bool {
		switch mutation {
		case .Truncate, .Drop, .Import(_, _), .Insert(_):
			return true

		case .Update(_,_,_,_), .Edit(_,_,_,_), .Rename(_):
			return false

		case .Alter(_):
			/* In some cases, an alter results in columns being changes/dropped, which is not supported by some databases
			(SQLite most notably). TODO: check here whether the proposed Alter requires such changes, or implement an 
			alternative for SQLite that uses DROP+CREATE to make the desired changes. */
			return self.database.dialect.supportsChangingColumnDefinitionsWithAlter
		}
	}
}

public class StandardSQLDialect: SQLDialect {
	public var stringQualifier: String { get { return "\'" } }
	public var stringQualifierEscape: String { get { return "\\\'" } }
	public var identifierQualifier: String { get { return "\"" } }
	public var identifierQualifierEscape: String { get { return "\\\"" } }
	public var stringEscape: String { get { return "\\" } }
	public var supportsChangingColumnDefinitionsWithAlter: Bool { return true }

	public init() {
	}

	public func columnIdentifier(column: Column, table: String? = nil, schema: String? = nil, database: String? = nil) -> String {
		if let t = table {
			let ti = tableIdentifier(t, schema: schema, database: database)
			return "\(ti).\(identifierQualifier)\(column.name.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
		}
		else {
			return "\(identifierQualifier)\(column.name.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
		}
	}
	
	public func tableIdentifier(table: String, schema: String?, database: String?) -> String {
		var prefix: String = ""
		if let d = database?.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape) {
			prefix = "\(identifierQualifier)\(d)\(identifierQualifier)."
		}

		if let s = schema?.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape) {
			prefix = prefix + "\(identifierQualifier)\(s)\(identifierQualifier)."
		}

		return "\(prefix)\(identifierQualifier)\(table.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
	}
	
	public func allColumnsIdentifier(table: String?, schema: String? = nil, database: String? = nil) -> String {
		if let t = table {
			return "\(tableIdentifier(t, schema: schema, database: database)).*"
		}
		return "*"
	}
	
	public func joinType(type: JoinType) -> String? {
		switch type {
		case .InnerJoin: return "INNER JOIN"
		case .LeftJoin: return "LEFT JOIN"
		}
	}

	/** Convert the given string to the representation in SQL (this includes string qualifiers and escaping). */
	public func literalString(string: String) -> String {
		let escaped = string
			.stringByReplacingOccurrencesOfString(stringEscape, withString: stringEscape+stringEscape)
			.stringByReplacingOccurrencesOfString(stringQualifier, withString: stringQualifierEscape)
		return "\(stringQualifier)\(escaped)\(stringQualifier)"
	}
	
	public func forceNumericExpression(expression: String) -> String {
		return "CAST(\(expression) AS NUMERIC)"
	}
	
	public func forceStringExpression(expression: String) -> String {
		return "CAST(\(expression) AS TEXT)"
	}
	
	public func expressionToSQL(formula: Expression, alias: String, foreignAlias: String? = nil, inputValue: String? = nil) -> String? {
		if formula.isConstant {
			let result = formula.apply(Row(), foreign: nil, inputValue: nil)
			return valueToSQL(result)
		}
		
		if formula is Literal {
			fatalError("This code is unreachable since literals should always be constant")
		}
		else if formula is Identity {
			return inputValue ?? "???"
		}
		else if let f = formula as? Sibling {
			return columnIdentifier(f.columnName, table: alias)
		}
		else if let f = formula as? Foreign {
			if let fa = foreignAlias {
				return columnIdentifier(f.columnName, table: fa)
			}
			else {
				return nil
			}
		}
		else if let f = formula as? Comparison {
			if let first = expressionToSQL(f.first, alias: alias, foreignAlias: foreignAlias, inputValue: inputValue) {
				if let second = expressionToSQL(f.second, alias: alias, foreignAlias: foreignAlias, inputValue: inputValue) {
					return binaryToSQL(f.type, first: first, second: second)
				}
			}
			return nil
		}
		else if let f = formula as? Call {
			var anyNils = false
			let argValues = f.arguments.map({(e: Expression) -> (String) in
				let r = self.expressionToSQL(e, alias: alias, foreignAlias: foreignAlias, inputValue: inputValue)
				if r == nil {
					anyNils = true
				}
				return r ?? ""
			})
			return anyNils ? nil : unaryToSQL(f.type, args: argValues)
		}

		return nil
	}
	
	public func aggregationToSQL(aggregation: Aggregation, alias: String) -> String? {
		if let expressionSQL = expressionToSQL(aggregation.map, alias: alias, foreignAlias: nil, inputValue: nil) {
			switch aggregation.reduce {
				case .Average: return "AVG(\(expressionSQL))"
				case .CountAll: return "COUNT(*)"
				case .Sum: return "SUM(\(expressionSQL))"
				case .Min: return "MIN(\(expressionSQL))"
				case .Max: return "MAX(\(expressionSQL))"
				case .Concat: return "GROUP_CONCAT(\(expressionSQL),'')"
				
				case .Pack:
					return "GROUP_CONCAT(REPLACE(REPLACE(\(expressionSQL),\(literalString(Pack.Escape)),\(literalString(Pack.EscapeEscape))),\(literalString(Pack.Separator)),\(literalString(Pack.SeparatorEscape))), \(literalString(Pack.Separator)))"
				
				default:
					/* TODO: RandomItem can be implemented using a UDF aggregation function in PostgreSQL. Implementing it in
					SQLite is not easy.. (perhaps Warp can define a UDF from Swift?). */
					return nil
			}
		}
		else {
			return nil
		}
	}

	public func unaryToSQL(type: Function, args: [String]) -> String? {
		let value = args.joinWithSeparator(", ")
		switch type {
			case .Identity: return value
			case .Negate: return "-\(value)"
			case .Uppercase: return "UPPER(\(value))"
			case .Lowercase: return "LOWER(\(value))"
			case .Absolute: return "ABS(\(value))"
			case .Cos: return "COS(\(value))"
			case .Sin: return "SIN(\(value))"
			case .Tan: return "TAN(\(value))"
			case .Cosh: return "COSH(\(value))"
			case .Sinh: return "SINH(\(value))"
			case .Tanh: return "TANH(\(value))"
			case .Acos: return "ACOS(\(value))"
			case .Asin: return "ASIN(\(value))"
			case .Atan: return "ATAN(\(value))"
			case .Sqrt: return "SQRT(\(value))"
			case .Concat: return "CONCAT(\(value))"
			case .If: return "(CASE WHEN \(args[0]) THEN \(args[1]) ELSE \(args[2]) END)"
			case .Left: return "SUBSTR(\(args[0]), 1, \(args[1]))"
			case .Right: return "RIGHT(\(args[0]), LENGTH(\(args[0]))-\(args[1]))"
			case .Mid: return "SUBSTR(\(args[0]), \(args[1]), \(args[2]))"
			case .Length: return "LEN(\(args[0]))"
			case .Trim: return "TRIM(\(args[0]))"
			case .Not: return "NOT(\(value))"
			case .Substitute: return "REPLACE(\(args[0]), \(args[1]), \(args[2]))"
			case .Xor: return "((\(args[0])<>\(args[1])) AND (\(args[0]) OR \(args[1])))"
			case .Coalesce: return "COALESCE(\(value))"
			case .IfError: return "IFNULL(\(args[0]), \(args[1]))" // In SQLite, the result of (1/0) equals NULL
			case .Sum: return args.joinWithSeparator(" + ")
			case .Average: return "(" + (args.joinWithSeparator(" + ")) + ")/\(args.count)"
			case .Min: return "MIN(\(value))" // Should be LEAST in SQL Server
			case .Max: return "MAX(\(value))" // Might be GREATEST in SQL Server
			
			case .And:
				if args.count > 0 {
					let ands = args.joinWithSeparator(" AND ")
					return "(\(ands))"
				}
				return "(1=0)"
			
			case .Or:
				if args.count > 0 {
					let ors = args.joinWithSeparator(" OR ")
					return "(\(ors))"
				}
				return "(1=1)"
			
			case .RandomBetween:
				/* FIXME check this! Using RANDOM() with modulus introduces a bias, but because we're using ABS, the bias
				should be cancelled out. See http://stackoverflow.com/questions/8304204/generating-only-positive-random-numbers-in-sqlite */
				let rf = self.unaryToSQL(Function.Random, args: []) ?? "RANDOM()"
				return "(\(args[0]) + ABS(\(rf) % (\(args[1])-\(args[0]))))"
			
			case .Random:
				/* FIXME: According to the SQLite documentation, RANDOM() generates a number between -9223372036854775808 
				and +9223372036854775807. This should work to generate a random double between 0 and 1 (although there is 
				a slight bias introduced because the lower bound is one lower than the upper bound). */
				return "ABS(RANDOM() / 9223372036854775807.0)"
			
			/* FIXME: this is random once (before query execution), in the raster implementation it is random for each
			row. Something like INDEX(RANDOM(), arg0, arg1, ...) might work (or even using CASE WHEN). */
			case .RandomItem: return (args.count > 0) ? args[Int.random(0..<args.count)] : "NULL"
			case .Log:
				// LOG() can either receive two parameters (number, log base) or one (just number, log base is 10).
				if args.count == 2 {
					return "(LOG(\(args[0])) / LOG(\(args[1])))"
				}
				else {
					return "(LOG(\(args[0])) / LOG(10))"
				}
			case .Ln:
				return "(LOG(\(args[0])) / LOG(\(exp(1.0))))"
			
			case .Exp:
				return "EXP(\(args[0]))"
			
			case .Round:
				if args.count == 1 {
					return "ROUND(\(args[0]), 0)"
				}
				else {
					return "ROUND(\(args[0]), \(args[1]))"
				}
			
			case .Sign:
				return "(CASE WHEN \(args[0])=0 THEN 0 WHEN \(args[0])>0 THEN 1 ELSE -1 END)"
			
			
			/* FIXME: These could simply call Function.Count.apply() if the parameters are constant, but then we need
			the original Expression arguments. */
			case .Count: return nil
			case .CountAll: return nil
			case .Pack: return nil
			
			// FIXME: should be implemented as CASE WHEN i=1 THEN a WHEN i=2 THEN b ... END
			case .Choose: return nil
			case .RegexSubstitute: return nil
			case .NormalInverse: return nil
			case .Split: return nil
			case .Nth: return nil
			case .Items: return nil
			case .Levenshtein: return nil
			case .URLEncode: return nil
			case .Capitalize: return nil
			
			// TODO: date function can probably be implemented in SQL
			case .Now: return nil
			case .ToUTCISO8601: return nil
			case .FromUnixTime: return nil
			case .ToUnixTime: return nil
			case .ToLocalISO8601: return nil
			case .FromISO8601: return nil
			case .FromExcelDate: return nil
			case .ToExcelDate: return nil
			case .UTCDay: return nil
			case .UTCHour: return nil
			case .UTCMinute: return nil
			case .UTCSecond: return nil
			case .UTCYear: return nil
			case .UTCMonth: return nil
			case .UTCDate: return nil
			case .Duration: return nil
			case .After: return nil
			/* TODO: Some databases probaby support date parsing and formatting with non-Unicode format strings; 
			implement that by translating the format strings */
			case .ToUnicodeDateString: return nil
			case .FromUnicodeDateString: return nil
			
			case .RandomString: return nil
			
			case .Floor: return "FLOOR(\(args[0]))"
			case .Ceiling: return "CEIL(\(args[0]))"
			
			case .In:
				// Not all databases might support IN with arbitrary values. If so, generate OR(a=x; a=y; ..)
				let first = args[0]
				var conditions: [String] = []
				for item in 1..<args.count {
					let otherItem = args[item]
					conditions.append(otherItem)
				}
				return "(\(first) IN (" + conditions.joinWithSeparator(", ") + "))"
			
			case .NotIn:
				// Not all databases might support NOT IN with arbitrary values. If so, generate AND(a<>x; a<>y; ..)
				let first = args[0]
				var conditions: [String] = []
				for item in 1..<args.count {
					let otherItem = args[item]
					conditions.append(otherItem)
				}
				return "(\(first) NOT IN (" + conditions.joinWithSeparator(", ") + "))"
			
			case .Power:
				return "POW(\(args[0]), \(args[1]))"
		}
	}
	
	internal func valueToSQL(value: Value) -> String {
		switch value {
			case .StringValue(let s):
				return literalString(s)
				
			case .DoubleValue(let d):
				if d.isNormal {
					return "\(d)"
				}
				else {
					return "(1.0/0.0)"
				}

			case .IntValue(let i):
				return "\(i)"
			
			case .DateValue(let d):
				return "\(d)"
			
			case .BoolValue(let b):
				return b ? "(1=1)" : "(1=0)"
				
			case .InvalidValue:
				return "(1/0)"
				
			case .EmptyValue:
				return "''"
		}
	}
	
	public func binaryToSQL(type: Binary, first: String, second: String) -> String? {
		switch type {
			case .Addition:		return "(\(second)+\(first))"
			case .Subtraction:	return "(\(second)-\(first))"
			case .Multiplication: return "(\(second)*\(first))"
			case .Division:		return "(\(second)/\(first))"
			case .Modulus:		return "MOD(\(second), \(first))"
			case .Concatenation: return "CONCAT(\(second),\(first))"
			case .Power:		return "POW(\(second), \(first))"
			case .Greater:		return "(\(second)>\(first))"
			case .Lesser:		return "(\(second)<\(first))"
			case .GreaterEqual:	return "(\(second)>=\(first))"
			case .LesserEqual:	return "(\(second)<=\(first))"
			case .Equal:		return "(\(second)=\(first))"
			case .NotEqual:		return "(\(second)<>\(first))"
			
			/* Most SQL database support the "a LIKE '%b%'" syntax for finding items where column a contains the string b
			(case-insensitive), so that's what we use for ContainsString and ContainsStringStrict. Because Presto doesn't
			support CONCAT with multiple parameters, we use two. */
			case .ContainsString: return "(LOWER(\(second)) LIKE CONCAT('%', CONCAT(LOWER(\(first)),'%')))"
			case .ContainsStringStrict: return "(\(second) LIKE CONCAT('%',CONCAT(\(first),'%')))"
			case .MatchesRegex: return "(\(second) REGEXP \(first))"
			case .MatchesRegexStrict: return "(\(second) REGEXP BINARY \(first))"
		}
	}
}

/** Logical fragments in an SQL statement, in order of logical execution. */
public enum SQLFragmentType {
	case From
	case Join
	case Where
	case Group
	case Having
	case Order
	case Limit
	case Select
	case Union
	
	var precedingType: SQLFragmentType? {
		switch self {
		case .From: return nil
		case .Join: return .From
		case .Where: return .Join
		case .Group: return .Where
		case .Having: return .Group
		case .Order: return .Having
		case .Limit: return .Order
		case .Select: return .Limit
		case .Union: return .Select
		}
	}
}

/** SQLFragment is used to generate SQL queries in an efficient manner, by taking the logical execution order of an SQL
statement into account. Fragments can be added to an existing fragment by calling one of the sql* functions. If the 
fragment logically followed the existing one (e.g. a LIMIT after a WHERE), it will be added to the fragment. If however
the added fragment does *not* logically follow the existing fragment (e.g. a WHERE after a LIMIT), the existing fragment
is made to be a subquery of a new query in which the added fragment is put. 

Why go through all this trouble? Some RDBMS'es execute subqueries naively, leading to very large temporary tables. By 
combining as much limiting factors in a subquery as possible, the size of intermediate results can be decreased, resulting
in higher performance. Another issue is that indexes can often not be used to accelerate lookups on derived tables. By
combining operations in a single query, they stay 'closer' to the original table, and the chance we can use an available
index is higher.

Note that SQLFragment is not concerned with filling in the actual fragments - that is the job of SQLData. */
public class SQLFragment {
	public let type: SQLFragmentType
	public let sql: String
	public let dialect: SQLDialect
	public let alias: String
	
	public init(type: SQLFragmentType, sql: String, dialect: SQLDialect, alias: String) {
		self.type = type
		self.sql = sql
		self.dialect = dialect
		self.alias = alias
	}
	
	public convenience init(table: String, schema: String?, database: String?, dialect: SQLDialect) {
		self.init(type: .From, sql: "FROM \(dialect.tableIdentifier(table,  schema: schema, database: database))", dialect: dialect, alias: table)
	}
	
	public convenience init(query: String, dialect: SQLDialect) {
		let alias = "T\(abs(query.hash))"
		
		// TODO: can use WITH..AS syntax here for DBMS'es that work better with that
		self.init(type: .From, sql: "FROM (\(query)) AS \(dialect.tableIdentifier(alias, schema: nil, database: nil))", dialect: dialect, alias: alias)
	}
	
	/** 
	Returns the table alias to be used in the next call that adds a part; for example:
	  
	let fragment = SQLFragment(table: "test", dialect: ...)
	let newFragment = fragment.sqlOrder(dialect.columnIdentifier("col", table: fragment.aliasFor(.Order)) + " ASC")
	*/
	func aliasFor(part: SQLFragmentType) -> String {
		return advance(part, part: "X").alias
	}
	
	// State transitions
	public func sqlWhere(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Where, part: part)
	}
	
	public func sqlJoin(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Join, part: part)
	}
	
	public func sqlGroup(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Group, part: part)
	}
	
	public func sqlHaving(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Having, part: part)
	}
	
	public func sqlOrder(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Order, part: part)
	}
	
	public func sqlLimit(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Limit, part: part)
	}
	
	public func sqlSelect(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Select, part: part)
	}
	
	public func sqlUnion(part: String?) -> SQLFragment {
		return advance(SQLFragmentType.Union, part: part)
	}
	
	/** Add a WHERE or HAVING clause with the given SQL for the condition part, depending on the state the query is 
	currently in. This can be used to add another filter to the query without creating a new subquery layer, only for
	conditions for which WHERE and HAVING have the same effect. */
	public func sqlWhereOrHaving(part: String?) -> SQLFragment {
		if self.type == .Group || self.type == .Where {
			return sqlHaving(part)
		}
		return sqlWhere(part)
	}
	
	var asSubquery: SQLFragment { get {
		return SQLFragment(query: self.sqlSelect(nil).sql, dialect: dialect)
	} }
	
	private func advance(toType: SQLFragmentType, part: String?) -> SQLFragment {
		// From which state can one go to the to-state?
		let precedingType = toType.precedingType
		let source: SQLFragment
		
		if self.type == toType && part == nil {
			// We are in the right place
			return self
		}
		
		if self.type == precedingType {
			// We are in the right state :-)
			source = self
		}
		else if precedingType == nil {
			// We are at the beginning, need to subquery
			source = self.asSubquery
		}
		else {
			// We need to skip some states to get in the right one
			source = advance(precedingType!, part: nil)
		}
		
		let fullPart: String
		if let p = part {
			switch toType {
				case .Group:
					fullPart = "\(source.sql) GROUP BY \(p)"
				
				case .Where:
					fullPart = "\(source.sql) WHERE \(p)"
				
				case .Join:
					fullPart = "\(source.sql) \(p)"
				
				case .Having:
					fullPart = "\(source.sql) HAVING \(p)"
				
				case .Order:
					fullPart = "\(source.sql) ORDER BY \(p)"
				
				case .Limit:
					fullPart = "\(source.sql) LIMIT \(p)"
				
				case .Select:
					fullPart = "SELECT \(p) \(source.sql)"
				
				case .Union:
					fullPart = "(\(source.sql)) UNION (\(p))";
				
				case .From:
					fatalError("Cannot advance to FROM with a part")
			}
		}
		else {
			switch toType {
				case .Select:
					fullPart = "SELECT * \(source.sql)"
				
				default:
					fullPart = source.sql
			}
		}
		
		return SQLFragment(type: toType, sql: fullPart, dialect: source.dialect, alias: source.alias)
	}
}

/** SQLData implements a general SQL-based data source. It maintains a single SQL statement that (when executed) 
should return the data represented by this data set. This class needs to be subclassed to be able to actually fetch the
data (a subclass implements the raster function to return the fetched data, preferably the stream function to return a
stream of results, and the apply function, to make sure any operations on the data set return a data set of the same
subclassed type). See QBESQLite for an implementation example. */
public class SQLData: NSObject, Data {
    public let sql: SQLFragment
	public let columns: [Column]
	
	public init(fragment: SQLFragment, columns: [Column]) {
		self.columns = columns
		self.sql = fragment
	}
	
	public init(sql: String, dialect: SQLDialect, columns: [Column]) {
		self.sql = SQLFragment(query: sql, dialect: dialect)
		self.columns = columns
    }
	
	public init(table: String, schema: String?, database: String, dialect: SQLDialect, columns: [Column]) {
		self.sql = SQLFragment(table: table, schema: schema, database: database, dialect: dialect)
		self.columns = columns
	}
	
	private func fallback() -> Data {
		return StreamData(source: self.stream())
	}
	
	public func columnNames(job: Job, callback: (Fallible<[Column]>) -> ()) {
		callback(.Success(columns))
	}
	
	public func raster(job: Job, callback: (Fallible<Raster>) -> ()) {
		job.async {
			StreamData(source: self.stream()).raster(job, callback: once(callback))
		}
	}
	
	/** Transposition is difficult in SQL, and therefore left to RasterData. */
   public  func transpose() -> Data {
		return fallback().transpose()
    }
	
	public func pivot(horizontal: [Column], vertical: [Column], values: [Column]) -> Data {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}
	
	public func flatten(valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) -> Data {
		return fallback().flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to)
	}
	
	public func union(data: Data) -> Data {
		if let rightSQL = data as? SQLData where isCompatibleWith(rightSQL) {
			// Find out what columns we will end up with
			var cols = self.columns
			for rightColumn in rightSQL.columns {
				if !cols.contains(rightColumn) {
					cols.append(rightColumn)
				}
			}
			
			return apply(self.sql.sqlUnion(rightSQL.sql.sqlSelect(nil).sql), resultingColumns: cols)
		}
		else {
			return fallback().union(data)
		}
	}
	
	public func join(join: Join) -> Data {
		if let sqlJoinType = sql.dialect.joinType(join.type) {
			switch join.type {
			case .LeftJoin, .InnerJoin:
				// We need to 'unpack' coalesced data to get to the actual data
				var rightData = join.foreignData
				while rightData is ProxyData || rightData is CoalescedData {
					if let rd = rightData as? CoalescedData {
						rightData = rd.data
					}
					else if let rd = rightData as? ProxyData {
						rightData = rd.data
					}
				}
				
				// Check if the other data set is a compatible SQL data set
				if let rightSQL = rightData as? SQLData where isCompatibleWith(rightSQL) {
					// Get SQL from right dataset
					let rightQuery = rightSQL.sql.sqlSelect(nil).sql
					let leftAlias = self.sql.aliasFor(.Join)
					let rightAlias = "F\(abs(rightQuery.hash))"
					
					// Which columns?
					let leftColumns = self.columns
					let rightColumns = rightSQL.columns.filter({!leftColumns.contains($0)})
					if rightColumns.count > 0 {
						let rightSelects = rightColumns.map({return self.sql.dialect.columnIdentifier($0, table: rightAlias, schema: nil, database: nil) + " AS " + self.sql.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil)}).joinWithSeparator(", ")
						let selects = "\(sql.dialect.allColumnsIdentifier(leftAlias, schema: nil, database: nil)), \(rightSelects)"
						
						// Generate a join expression
						if let es = sql.dialect.expressionToSQL(join.expression, alias: leftAlias, foreignAlias: rightAlias, inputValue: nil) {
							return apply(self.sql
								.sqlJoin("\(sqlJoinType) (\(rightQuery)) AS \(sql.dialect.tableIdentifier(rightAlias, schema: nil, database: nil)) ON \(es)")
								.sqlSelect(selects), resultingColumns: leftColumns + rightColumns)
						}
					}
					return self
				}
				return fallback().join(join)
			}
		}
		else {
			// The join type is not supported in this database
			return fallback().join(join)
		}
	}
	
	/** Determines whether another SQLData set is 'compatible' with this one. Compatible means that the two data sets 
	are actually in the same database, so that a join (or other merging operation) is possible between these datasets. By
	default, we assume data sets are never compatible. */
	public func isCompatibleWith(other: SQLData) -> Bool {
		return false
	}
	
	public func calculate(calculations: Dictionary<Column, Expression>) -> Data {
		var values: [String] = []
		var newColumns = columns
		
		let sourceSQL = sql.asSubquery
		let sourceAlias = sourceSQL.alias
		
		// Re-calculate existing columns first
		for targetColumn in columns {
			if calculations[targetColumn] != nil {
				let expression = calculations[targetColumn]!.prepare()
				if let expressionString = sql.dialect.expressionToSQL(expression, alias: sourceAlias, foreignAlias: nil, inputValue: sql.dialect.columnIdentifier(targetColumn, table: sourceAlias, schema: nil, database: nil)) {
					values.append("\(expressionString) AS \(sql.dialect.columnIdentifier(targetColumn, table: nil, schema: nil, database: nil))")
				}
				else {
					return fallback().calculate(calculations)
				}
			}
			else {
				values.append("\(sql.dialect.columnIdentifier(targetColumn, table: sourceAlias, schema: nil, database: nil)) AS \(sql.dialect.columnIdentifier(targetColumn, table: nil, schema: nil, database: nil))")
			}
		}
		
		// New columns are added at the end
		for (targetColumn, expression) in calculations {
			if !columns.contains(targetColumn) {
				if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), alias: sourceAlias, foreignAlias: nil, inputValue: sql.dialect.columnIdentifier(targetColumn, table: sourceAlias, schema: nil, database: nil)) {
					values.append("\(expressionString) AS \(sql.dialect.columnIdentifier(targetColumn, table: nil, schema: nil, database: nil))")
				}
				else {
					return fallback().calculate(calculations)
				}
				newColumns.append(targetColumn)
			}
		}
		
		let valueString = values.joinWithSeparator(", ")
		return apply(sourceSQL.sqlSelect(valueString), resultingColumns: newColumns)
    }
	
	public func sort(by: [Order]) -> Data {
		var error = false
		
		let sqlOrders = by.map({(order) -> (String) in
			if let expression = order.expression, let esql = self.sql.dialect.expressionToSQL(expression, alias: self.sql.aliasFor(.Order), foreignAlias: nil,inputValue: nil) {
				let castedSQL: String
				if order.numeric {
					castedSQL = self.sql.dialect.forceNumericExpression(esql)
				}
				else {
					castedSQL = self.sql.dialect.forceStringExpression(esql)
				}
				return castedSQL + " " + (order.ascending ? "ASC" : "DESC")
			}
			else {
				error = true
				return ""
			}
		})
		
		// If one of the sorting expressions can't be represented in SQL, use the fall-back
		// TODO: for ORDER BY a, b, c still perform ORDER BY b, c if a cannot be represented in sQL
		if error {
			return fallback().sort(by)
		}
		
		let orderClause = sqlOrders.joinWithSeparator(", ")
		return apply(sql.sqlOrder(orderClause), resultingColumns: columns)
	}
	
	public func distinct() -> Data {
		return apply(self.sql.sqlSelect("DISTINCT *"), resultingColumns: columns)
	}
    
    public func limit(numberOfRows: Int) -> Data {
		return apply(self.sql.sqlLimit("\(numberOfRows)"), resultingColumns: columns)
    }
	
	public func offset(numberOfRows: Int) -> Data {
		// FIXME: T-SQL uses "SELECT TOP x" syntax
		// FIXME: the LIMIT -1 is probably only necessary for SQLite
		return apply(sql.sqlLimit("-1 OFFSET \(numberOfRows)"), resultingColumns: columns)
	}
	
	public func filter(condition: Expression) -> Data {
		let optimizedCondition = condition.prepare()
		if optimizedCondition.isConstant {
			let constantValue = optimizedCondition.apply(Row(), foreign: nil, inputValue: nil)
			if constantValue == Value(false) {
				// Never return any rows
				return RasterData(data: [], columnNames: self.columns)
			}
			else if constantValue == Value(true) {
				// Return all rows always
				return self
			}
		}

		if let expressionString = sql.dialect.expressionToSQL(condition.prepare(), alias: sql.aliasFor(.Where), foreignAlias: nil,inputValue: nil) {
			return apply(sql.sqlWhereOrHaving(expressionString), resultingColumns: columns)
		}
		else {
			return fallback().filter(condition)
		}
	}
	
	public func random(numberOfRows: Int) -> Data {
		let randomFunction = sql.dialect.unaryToSQL(Function.Random, args: []) ?? "RANDOM()"
		return apply(sql.sqlOrder(randomFunction).sqlLimit("\(numberOfRows)"), resultingColumns: columns)
	}
	
	public func unique(expression: Expression, job: Job, callback: (Fallible<Set<Value>>) -> ()) {
		if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), alias: sql.aliasFor(.Select), foreignAlias: nil, inputValue: nil) {
			let data = apply(self.sql.sqlSelect("DISTINCT \(expressionString) AS _value"), resultingColumns: ["_value"])
			
			data.raster(job) { (raster) -> () in
				callback(raster.use { r in
					return Set<Value>(r.raster.map({$0[0]}))
				})
			}
		}
		else {
			return fallback().unique(expression, job: job, callback: once(callback))
		}
	}
	
	public func selectColumns(columns: [Column]) -> Data {
		let colNames = columns.map { self.sql.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil) }.joinWithSeparator(", ")
		return apply(self.sql.sqlSelect(colNames), resultingColumns: columns)
	}
	
	public func aggregate(groups: [Column : Expression], values: [Column : Aggregation]) -> Data {
		if groups.isEmpty && values.isEmpty {
			return StreamData(source: EmptyStream())
		}

		var groupBy: [String] = []
		var select: [String] = []
		var resultingColumns: [Column] = []
		
		let alias = groups.count > 0 ? sql.aliasFor(.Group) : sql.aliasFor(.Select)
		for (column, expression) in groups {
			if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), alias: alias, foreignAlias: nil, inputValue: nil) {
				select.append("\(expressionString) AS \(sql.dialect.columnIdentifier(column, table: nil, schema: nil, database: nil))")
				groupBy.append("\(expressionString)")
				resultingColumns.append(column)
			}
			else {
				return fallback().aggregate(groups, values: values)
			}
		}
		
		for (column, aggregation) in values {
			if let aggregationSQL = sql.dialect.aggregationToSQL(aggregation, alias: alias) {
				select.append("\(aggregationSQL) AS \(sql.dialect.columnIdentifier(column, table: nil, schema: nil, database: nil))")
				resultingColumns.append(column)
			}
			else {
				// Fall back to default implementation for unsupported aggregation functions
				return fallback().aggregate(groups, values: values)
			}
		}
		
		let selectString = select.joinWithSeparator(", ")
		if groupBy.count>0 {
			let groupString = groupBy.joinWithSeparator(", ")
			return apply(sql.sqlGroup(groupString).sqlSelect(selectString), resultingColumns: resultingColumns)
		}
		else {
			// No columns to group by, total aggregates it is
			return apply(sql.sqlSelect(selectString), resultingColumns: resultingColumns)
		}
	}
	
	public func apply(fragment: SQLFragment, resultingColumns: [Column]) -> Data {
		return SQLData(fragment: fragment, columns: columns)
	}
	
	public func stream() -> Stream {
		fatalError("Stream() must be implemented by subclass of SQLData")
	}
}