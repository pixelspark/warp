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
	func columnIdentifier(_ column: Column, table: String?, schema: String?, database: String?) -> String
	
	/** Returns the identifier that represents all columns in the given table (e.g. "table.*" or just "*". */
	func allColumnsIdentifier(_ table: String?, schema: String?, database: String?) -> String
	
	func tableIdentifier(_ table: String, schema: String?, database: String?) -> String
	
	/** Transforms the given expression to a SQL string. The inputValue parameter determines the return value of the
	Identity expression. The function may return nil for expressions it cannot successfully transform to SQL. */
	func expressionToSQL(_ formula: Expression, alias: String, foreignAlias: String?, inputValue: String?) -> String?
	
	func unaryToSQL(_ type: Function, args: [String]) -> String?
	func binaryToSQL(_ type: Binary, first: String, second: String) -> String?
	
	/** Transforms the given aggregation to an aggregation description that can be incldued as part of a GROUP BY 
	statement. The function may return nil for aggregations it cannot represent or transform to SQL. */
	func aggregationToSQL(_ aggregation: Aggregator, alias: String) -> String?
	
	/** Create an expression that forces the specified expression to a numeric type (DOUBLE or INT in SQL). */
	func forceNumericExpression(_ expression: String) -> String
	
	/** Create an expression that forces the specified expression to a string type (e.g. VARCHAR or TEXT in SQL). */
	func forceStringExpression(_ expression: String) -> String
	
	/** Returns the SQL name for the indicates join type, or nil if that join type is not supported */
	func joinType(_ type: JoinType) -> String?

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
	func connect(_ callback: (Fallible<SQLConnection>) -> ())

	/** Creates a Dataset object that can be used to read data from a table in the specified schema (if any) in this
	database. For databases that do not support schemas the schema parameter must be nil. */
	func dataForTable(_ table: String, schema: String?, job: Job, callback: (Fallible<Dataset>) -> ())
}

public protocol SQLConnection {
	/** Serially perform the indicate SQL data definition commands in the order specified. The callback is called after 
	the first error is encountered, or when all queries have been executed successfully. Depending on the support of the 
	database, wrapping in a transaction is possible by issuing 'BEGIN'  and 'COMMIT'  commands. Whenever an
	error is encountered, no further query processing should happen. */
	func run(_ sql: [String], job: Job, callback: (Fallible<Void>) -> ())
}

open class SQLWarehouse: Warehouse {
	public let database: SQLDatabase
	public let schemaName: String?
	public var dialect: SQLDialect { return database.dialect }
	open let hasFixedColumns: Bool = true
	public let hasNamedTables: Bool = true

	public init(database: SQLDatabase, schemaName: String?) {
		self.database = database
		self.schemaName = schemaName
	}

	open func canPerformMutation(_ mutation: WarehouseMutationKind) -> Bool {
		switch mutation {
		case .create:
			return true
		}
	}

	open func performMutation(_ mutation: WarehouseMutation, job: Job, callback: @escaping (Fallible<MutableDataset?>) -> ()) {
		if !canPerformMutation(mutation.kind) {
			callback(.failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		self.database.connect { connectionFallible in
			switch connectionFallible {
			case .success(let con):
				switch mutation {
				// Create a table to store the given data set
				case .create(let tableName, let data):
					// Start a transaction
					con.run(["BEGIN"], job: job) { result in
						switch result {
						case .success(_):
							// Find out the column names of the source data
							data.columns(job) { columnsResult in
								switch columnsResult {
								case .failure(let e): callback(.failure(e))
								case .success(let columns):
									// Build a 'CREATE TABLE' query and run it
									let fields = columns.map {
										return self.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil) + " TEXT NULL DEFAULT NULL"
									}.joined(separator: ", ")
									let createQuery = "CREATE TABLE \(self.dialect.tableIdentifier(tableName, schema: self.schemaName, database: self.database.databaseName)) (\(fields))";

									// Create the table
									con.run([createQuery], job: job) { createResult in
										switch createResult {
										case .failure(let e): callback(.failure(e))
										case .success(_):
											// Commit the things we just did
											con.run(["COMMIT"], job: job) { commitResult in
												switch commitResult {
												case .success:
													// Go and insert the specified data in the table
													let mutableDataset = SQLMutableDataset(database: self.database, schemaName: self.schemaName, tableName: tableName)
													let mapping = columns.mapDictionary { cn in return (cn, cn) }
													mutableDataset.performMutation(.import(data: data, withMapping: mapping), job: job) { insertResult in
														switch insertResult {
														case .success:
															callback(.success(mutableDataset))

														case .failure(let e): callback(.failure(e))
														}
													}

												case .failure(let e): callback(.failure(e))
												}
											}
										}
									}
								}
							}
						case .failure(let e): callback(.failure(e))
						}
					}
				}

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}
}

private class SQLInsertPuller: StreamPuller {
	private let columns: OrderedSet<Column>
	private var callback: ((Fallible<Void>) -> ())?
	private let fastMapping: [Int?]
	private let insertStatement: String
	private let connection: SQLConnection
	private let database: SQLDatabase

	init(stream: Stream, job: Job, columns: OrderedSet<Column>, mapping: ColumnMapping, insertStatement: String, connection: SQLConnection, database: SQLDatabase, callback: ((Fallible<Void>) -> ())?) {
		self.callback = callback
		self.columns = columns
		self.insertStatement = insertStatement
		self.connection = connection
		self.database = database

		self.fastMapping = mapping.keys.map { targetField -> Int? in
			if let sourceFieldName = mapping[targetField] {
				return columns.index(of: sourceFieldName)
			}
			else {
				return nil
			}
		}

		super.init(stream: stream, job: job)
	}

	override func onReceiveRows(_ rows: [Tuple], callback: @escaping (Fallible<Void>) -> ()) {
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
						}.joined(separator: ", ")
					return "(\(tuple))"
					}.joined(separator: ", ")

				let sql = "\(insertStatement) \(values)"
				connection.run([sql], job: job) { insertResult in
					switch insertResult {
					case .failure(let e):
						callback(.failure(e))

					case .success(_):
						callback(.success())
					}
				}
			}
			else {
				callback(.success())
			}
		}
	}

	override func onDoneReceiving() {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil
			self.job.async {
				cb(.success())
			}
		}
	}

	override func onError(_ error: String) {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil

			self.job.async {
				cb(.failure(error))
			}
		}
	}
}

open class SQLMutableDataset: MutableDataset {
	public let database: SQLDatabase
	public let tableName: String
	public let schemaName: String?

	open var warehouse: Warehouse { return SQLWarehouse(database: self.database, schemaName: self.schemaName) }

	public init(database: SQLDatabase, schemaName: String?, tableName: String) {
		self.database = database
		self.tableName = tableName
		self.schemaName = schemaName
	}

	/** Subclasses must implement this function to fetch the table's row identifier (primary key). See Schema.identifier
	for what is expected. */
	open func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		return callback(.failure("Not implemented"))
	}

	private var tableIdentifier: String {
		return self.database.dialect.tableIdentifier(self.tableName, schema: self.schemaName, database: self.database.databaseName)
	}

	public func data(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.database.dataForTable(tableName, schema: schemaName, job: job, callback: callback)
	}

	public func schema(_ job: Job, callback: @escaping (Fallible<Schema>) -> ()) {
		// TODO: query information_schema here
		self.data(job) { result in
			switch result {
			case .success(let data):
				data.columns(job) { result in
					switch result {
					case .success(let cols):
						self.identifier(job) { result in
							switch result {
							case .success(let identifier):
								let schema = Schema(columns: cols, identifier: identifier)
								return callback(.success(schema))

							case .failure(let e):
								return callback(.failure(e))
							}
						}

					case .failure(let e):
						return callback(.failure(e))
					}
				}

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}

	private func performInsertByPulling(_ connection: SQLConnection, data: Dataset, mapping: ColumnMapping, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		let fields = mapping.keys.map { fn in return self.database.dialect.columnIdentifier(fn, table: nil, schema: nil, database: nil) }.joined(separator: ", ")
		let insertStatement = "INSERT INTO \(self.tableIdentifier) (\(fields)) VALUES ";
		job.log(insertStatement)

		// Fetch rows and insert!
		data.columns(job) { columnsFallible in
			switch columnsFallible {
			case .success(let sourceColumnNames):
				let stream = data.stream()
				let puller = SQLInsertPuller(stream: stream, job: job, columns: sourceColumnNames, mapping: mapping, insertStatement: insertStatement, connection: connection, database: self.database, callback: callback)
				puller.start()

			case .failure(let e):
				callback(.failure(e))
				return
			}
		}
	}

	private func performInsert(_ connection: SQLConnection, data: Dataset, mapping: ColumnMapping, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		if mapping.isEmpty {
			callback(.failure("Cannot insert zero columns!"))
			return
		}

		// Is the other data set an SQL data set (or an SQL data set shrink-wrapped in CoalescedDataset)?
		if let otherSQL = (data as? SQLDataset) ?? ((data as? CoalescedDataset)?.data as? SQLDataset) {
			self.data(job) { result in
				switch result {
				case .success(let myDataset):
					if let mySQLDataset  = myDataset as? SQLDataset, mySQLDataset.isCompatibleWith(otherSQL) {
						// Perform INSERT INTO ... SELECT ...
						self.database.connect { result in
							switch result {
							case .success(let connection):
								let targetColumns = Array(mapping.keys)
								let fields = targetColumns.map { fn in return self.database.dialect.columnIdentifier(fn, table: nil, schema: nil, database: nil) }
								let otherAlias = otherSQL.sql.aliasFor(.select)

								let selection = targetColumns.map { field in
									return otherSQL.sql.dialect.columnIdentifier(mapping[field]!, table: otherAlias, schema: nil, database: nil)
								}
								let otherSelectSQL = otherSQL.sql.sqlSelect(selection.joined(separator: ", "))
								let insertStatement = "INSERT INTO \(self.tableIdentifier) (\(fields.joined(separator: ", "))) \(otherSelectSQL.sql)";
								connection.run([insertStatement], job: job, callback: callback)

							case .failure(let e):
								callback(.failure(e))
								return
							}
						}
					}
					else {
						self.performInsertByPulling(connection, data: data, mapping: mapping, job: job, callback: callback)
					}

				case .failure(let e):
					callback(.failure(e))
					return
				}
			}
		}
		else {
			performInsertByPulling(connection, data: data, mapping: mapping, job: job, callback: callback)
		}
	}

	private func performAlter(_ connection: SQLConnection, desiredSchema: Schema, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		self.schema(job) { result in
			switch result {
			case .success(let existingSchema):
				var changes: [String] = []

				for dropColumn in Set(existingSchema.columns).subtracting(desiredSchema.columns) {
					changes.append("DROP COLUMN \(self.database.dialect.columnIdentifier(dropColumn, table: nil, schema: nil, database: nil))")
				}

				/* We should probably ensure that target columns have a storage type that can accomodate our data, 
				but for now we leave the destination columns intact, to prevent unintentional (and unforeseen)
				damage to the destination table. */
				/*for changeColumn in Set(desiredColumns).intersect(existingColumns) {
					let cn = self.database.dialect.columnIdentifier(changeColumn, table: nil, schema: nil, database: nil)
					changes.append("ALTER COLUMN \(cn) \(cn) TEXT NULL DEFAULT NULL")
				}*/

				for addColumn in Set(desiredSchema.columns).subtracting(existingSchema.columns) {
					changes.append("ADD COLUMN \(self.database.dialect.columnIdentifier(addColumn, table: nil, schema: nil, database: nil)) TEXT NULL DEFAULT NULL")
				}

				if changes.count > 0 {
					let sql = "ALTER TABLE \(self.tableIdentifier) \(changes.joined(separator: ", "))"
					connection.run([sql], job: job) { result in
						switch result {
						case .success():
							// Do we also need to change primary keys?
							if existingSchema.identifier != desiredSchema.identifier {
								// FIXME implement changing the primary key (if data set supports it).
								// If desiredSchema.identifier == nil, drop the primary key altogether
								return callback(.failure("Changing the primary key of this table is not supported, because it is not yet implemented."))
							}
							else {
								return callback(.success())
							}

						case .failure(let e):
							return callback(.failure(e))
						}
					}
				}
				else {
					// No change required
					callback(.success())
				}

			case .failure(let e): callback(.failure(e))
			}
		}
	}

	private func performDelete(_ connection: SQLConnection, keys: [[Column: Value]], job: Job, callback: (Fallible<Void>) -> ()) {
		var allWheres: [Expression] = []

		for key in keys {
			var wheres: [Expression] = []
			for (column, value) in key {
				wheres.append(Comparison(first: Sibling(column), second: Literal(value), type: .equal))
			}
			allWheres.append(Call(arguments: wheres, type: .And))
		}

		let whereExpression = Call(arguments: allWheres, type: .Or)

		guard let whereSQL = self.database.dialect.expressionToSQL(whereExpression, alias: self.tableName, foreignAlias: nil, inputValue: nil) else {
			return callback(.failure("Selection cannot be written in SQL"))
		}

		let query = "DELETE FROM \(self.tableIdentifier) WHERE \(whereSQL)"
		connection.run([query], job: job, callback: callback)
	}

	private func performUpdate(_ connection: SQLConnection, key: [Column: Value], column: Column, old: Value, new:Value, job: Job, callback: (Fallible<Void>) -> ()) {
		var wheres: [Expression] = []
		for (column, value) in key {
			wheres.append(Comparison(first: Sibling(column), second: Literal(value), type: .equal))
		}

		// Only update if the old value matches what we last saw
		wheres.append(Comparison(first: Sibling(column), second: Literal(old), type: .equal))

		let whereExpression = Call(arguments: wheres, type: .And)
		guard let whereSQL = self.database.dialect.expressionToSQL(whereExpression, alias: self.tableName, foreignAlias: nil, inputValue: nil) else { return callback(.failure("Selection cannot be written in SQL")) }

		// Write assignment
		let targetIdentifier = self.database.dialect.columnIdentifier(column, table: nil, schema: nil, database: nil)
		guard let valueSQL = self.database.dialect.expressionToSQL(Literal(new), alias: self.tableName, foreignAlias: nil, inputValue: nil) else {
			return callback(.failure("Assignment cannot be written as SQL"))
		}
		let assignSQL = "\(targetIdentifier) = \(valueSQL)"

		let query = "UPDATE \(self.tableIdentifier) SET \(assignSQL) WHERE \(whereSQL)"
		connection.run([query], job: job, callback: callback)
	}

	private func performInsert(_ connection: SQLConnection, row: Row, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		self.schema(job) { result in
			switch result {
			case .success(let schema):
				let insertingColumns = Array(Set(row.columns).intersection(Set(schema.columns)))
				let insertingColumnsSQL = insertingColumns
					.map { return self.database.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil) }
					.joined(separator: ", ")

				var valuesSQL: [String] = []
				for column in insertingColumns {
					if let s = self.database.dialect.expressionToSQL(Literal(row[column]), alias: self.tableName, foreignAlias: nil, inputValue: nil) {
						valuesSQL.append(s)
					}
					else {
						// Value can't be written in this SQL dialect, bail out
						return callback(.failure("value type not supported: '\(row[column])'"))
					}
				}

				let valuesSQLString = valuesSQL.joined(separator: ", ")
				let query = "INSERT INTO \(self.tableIdentifier) (\(insertingColumnsSQL)) VALUES (\(valuesSQLString))"
				connection.run([query], job: job, callback: callback)

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}

	public func performMutation(_ mutation: DatasetMutation, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		if !canPerformMutation(mutation.kind) {
			callback(.failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		job.async {
			self.database.connect({ (connectionFallible) -> () in
				switch connectionFallible {
					case .success(let con):
						switch mutation {
						case .drop:
							con.run(["DROP TABLE \(self.tableIdentifier)"], job: job, callback: callback)

						case .truncate:
							// TODO: MySQL supports TRUNCATE TABLE which supposedly is faster
							con.run(["DELETE FROM \(self.tableIdentifier)"], job: job, callback: callback)

						case .alter(let schema):
							self.performAlter(con, desiredSchema: schema, job: job, callback: callback)

						case .import(data: let data, withMapping: let mapping):
							self.performInsert(con, data: data, mapping: mapping, job: job, callback: callback)

						case .update(key: let k, column: let c, old: let o, new: let n):
							self.performUpdate(con, key:k, column: c, old: o, new: n, job: job, callback: callback)

						case .delete(keys: let k):
							self.performDelete(con, keys:k, job: job, callback: callback)

						case .insert(row: let row):
							self.performInsert(con, row: row, job: job, callback: callback)

						case .rename(_):
							fatalError("Not supported")
						}

					case .failure(let e):
						callback(.failure(e))
				}
			})
		}
	}

	open func canPerformMutation(_ mutation: DatasetMutationKind) -> Bool {
		switch mutation {
		case .truncate, .drop, .`import`, .insert, .update, .delete:
			return true

		case .rename:
			return false

		case .alter:
			/* In some cases, an alter results in columns being changes/dropped, which is not supported by some databases
			(SQLite most notably). TODO: check here whether the proposed Alter requires such changes, or implement an 
			alternative for SQLite that uses DROP+CREATE to make the desired changes. */
			return self.database.dialect.supportsChangingColumnDefinitionsWithAlter
		}
	}
}

open class StandardSQLDialect: SQLDialect {
	open var stringQualifier: String { return "\'" }
	open var stringQualifierEscape: String { return "\'\'" }
	open var identifierQualifier: String { return "\"" }
	open var identifierQualifierEscape: String { return "\\\"" }
	open var stringEscape: String { return "\\" }
	open var supportsChangingColumnDefinitionsWithAlter: Bool { return true }

	public init() {
	}

	open func columnIdentifier(_ column: Column, table: String? = nil, schema: String? = nil, database: String? = nil) -> String {
		if let t = table {
			let ti = tableIdentifier(t, schema: schema, database: database)
			return "\(ti).\(identifierQualifier)\(column.name.replacingOccurrences(of: identifierQualifier, with: identifierQualifierEscape))\(identifierQualifier)"
		}
		else {
			return "\(identifierQualifier)\(column.name.replacingOccurrences(of: identifierQualifier, with: identifierQualifierEscape))\(identifierQualifier)"
		}
	}
	
	open func tableIdentifier(_ table: String, schema: String?, database: String?) -> String {
		var prefix: String = ""
		if let d = database?.replacingOccurrences(of: identifierQualifier, with: identifierQualifierEscape) {
			prefix = "\(identifierQualifier)\(d)\(identifierQualifier)."
		}

		if let s = schema?.replacingOccurrences(of: identifierQualifier, with: identifierQualifierEscape) {
			prefix = prefix + "\(identifierQualifier)\(s)\(identifierQualifier)."
		}

		return "\(prefix)\(identifierQualifier)\(table.replacingOccurrences(of: identifierQualifier, with: identifierQualifierEscape))\(identifierQualifier)"
	}
	
	open func allColumnsIdentifier(_ table: String?, schema: String? = nil, database: String? = nil) -> String {
		if let t = table {
			return "\(tableIdentifier(t, schema: schema, database: database)).*"
		}
		return "*"
	}
	
	open func joinType(_ type: JoinType) -> String? {
		switch type {
		case .innerJoin: return "INNER JOIN"
		case .leftJoin: return "LEFT JOIN"
		}
	}

	/** Convert the given string to the representation in SQL (this includes string qualifiers and escaping). */
	open func literalString(_ string: String) -> String {
		let escaped = string
			.replacingOccurrences(of: stringEscape, with: stringEscape+stringEscape)
			.replacingOccurrences(of: stringQualifier, with: stringQualifierEscape)
		return "\(stringQualifier)\(escaped)\(stringQualifier)"
	}
	
	open func forceNumericExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS NUMERIC)"
	}
	
	open func forceStringExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS TEXT)"
	}
	
	open func expressionToSQL(_ formula: Expression, alias: String, foreignAlias: String? = nil, inputValue: String? = nil) -> String? {
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
			return columnIdentifier(f.column, table: alias)
		}
		else if let f = formula as? Foreign {
			if let fa = foreignAlias {
				return columnIdentifier(f.column, table: fa)
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
			// Do we have the required arguments?
			if !f.type.arity.valid(f.arguments.count) {
				return nil
			}

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
	
	open func aggregationToSQL(_ aggregation: Aggregator, alias: String) -> String? {
		if let expressionSQL = expressionToSQL(aggregation.map, alias: alias, foreignAlias: nil, inputValue: nil) {
			switch aggregation.reduce {
				case .Average: return "AVG(\(expressionSQL))"
				case .CountAll: return "COUNT(*)"
				case .CountDistinct: return "COUNT(DISTINCT \(expressionSQL))"
				case .Sum: return "SUM(\(expressionSQL))"
				case .Min: return "MIN(\(expressionSQL))"
				case .Max: return "MAX(\(expressionSQL))"
				case .StandardDeviationPopulation: return "STDDEV_POP(\(expressionSQL))"
				case .StandardDeviationSample: return "STDDEV_SAMP(\(expressionSQL))"
				case .VariancePopulation: return "VAR_POP(\(expressionSQL))"
				case .VarianceSample: return "VAR_SAMP(\(expressionSQL))"
				case .Concat: return "GROUP_CONCAT(\(expressionSQL),'')"
				
				case .Pack:
					return "GROUP_CONCAT(REPLACE(REPLACE(\(expressionSQL),\(literalString(Pack.escape)),\(literalString(Pack.escapeEscape))),\(literalString(Pack.separator)),\(literalString(Pack.separatorEscape))), \(literalString(Pack.separator)))"
				
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

	open func unaryToSQL(_ type: Function, args: [String]) -> String? {
		let value = args.joined(separator: ", ")
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
		case .Sum: return args.joined(separator: " + ")
		case .Average: return "(" + (args.joined(separator: " + ")) + ")/\(args.count)"
		case .Min: return "MIN(\(value))" // Should be LEAST in SQL Server
		case .Max: return "MAX(\(value))" // Might be GREATEST in SQL Server

		case .And:
			if args.count > 0 {
				let ands = args.joined(separator: " AND ")
				return "(\(ands))"
			}
			return "(1=0)"

		case .Or:
			if args.count > 0 {
				let ors = args.joined(separator: " OR ")
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
		case .CountDistinct: return nil
		case .CountAll: return nil
		case .Pack: return nil
		case .Median: return nil
		case .MedianLow: return nil
		case .MedianHigh: return nil
		case .MedianPack: return nil
		case .StandardDeviationSample: return nil
		case .StandardDeviationPopulation: return nil
		case .VarianceSample: return nil
		case .VariancePopulation: return nil

		// FIXME: should be implemented as CASE WHEN i=1 THEN a WHEN i=2 THEN b ... END
		case .Choose: return nil
		case .RegexSubstitute: return nil
		case .NormalInverse: return nil
		case .Split: return nil
		case .Nth: return nil
		case .ValueForKey: return nil
		case .Items: return nil
		case .Levenshtein: return nil
		case .URLEncode: return nil
		case .Capitalize: return nil
		case .UUID: return nil

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
			return "(\(first) IN (" + conditions.joined(separator: ", ") + "))"

		case .NotIn:
			// Not all databases might support NOT IN with arbitrary values. If so, generate AND(a<>x; a<>y; ..)
			let first = args[0]
			var conditions: [String] = []
			for item in 1..<args.count {
				let otherItem = args[item]
				conditions.append(otherItem)
			}
			return "(\(first) NOT IN (" + conditions.joined(separator: ", ") + "))"

		case .Power:
			return "POW(\(args[0]), \(args[1]))"

		case .IsEmpty:
			return "(\(args[0]) IS NULL)"

		case .IsInvalid:
			return nil

		case .JSONDecode:
			return nil

		case .HilbertXYToD, .HilbertDToX, .HilbertDToY:
			return nil

		case .PowerUp, .PowerDown:
			return nil

		case .ParseNumber:
			var value = args[0]

			// Replace thousands separator
			if args.count >= 2 {
				value = "REPLACE(\(value), \(args[2]), '')"
			}

			// Put in the right decimal separator
			if args.count >= 1 {
				value = "REPLACE(\(value), \(args[1]), '.')"
			}

			return self.forceNumericExpression(value)
		}
	}

	open func valueToSQL(_ value: Value) -> String {
		switch value {
			case .string(let s):
				return literalString(s)

			case .double(let d):
				if d.isNormal || d.isZero {
					return "\(d)"
				}
				else {
					return "(1.0/0.0)"
				}

			case .int(let i):
				return "\(i)"
			
			case .date(let d):
				return "\(d)"
			
			case .bool(let b):
				return b ? "(1=1)" : "(1=0)"
				
			case .invalid:
				return "(1/0)"
				
			case .empty:
				return "NULL"
		}
	}
	
	open func binaryToSQL(_ type: Binary, first: String, second: String) -> String? {
		switch type {
		// Force arguments of numeric comparison operators to numerics, to prevent 'string ordering' comparisons
		// Note that this may impact performance as indexes cannot be used anymore after casting?
		// TODO: only force to numeric when expression is not already numeric (e.g. a double literal).
		case .addition: return "(\(forceNumericExpression(second)) + \(forceNumericExpression(first)))"
		case .subtraction: return "(\(forceNumericExpression(second)) - \(forceNumericExpression(first)))"
		case .multiplication: return "(\(forceNumericExpression(second)) * \(forceNumericExpression(first)))"
		case .division: return "(\(forceNumericExpression(second)) / \(forceNumericExpression(first)))"
		case .modulus:		return "MOD(\(forceNumericExpression(second)), \(forceNumericExpression(first)))"
		case .concatenation: return "CONCAT(\(forceStringExpression(second)), \(forceStringExpression(first)))"
		case .power:		return "POW(\(forceNumericExpression(second)), \(forceNumericExpression(first)))"
		case .greater:		return "(\(self.forceNumericExpression(second)) > \(self.forceNumericExpression(first)))"
		case .lesser:		return "(\(self.forceNumericExpression(second)) < \(self.forceNumericExpression(first)))"
		case .greaterEqual:	return "(\(self.forceNumericExpression(second)) >= \(self.forceNumericExpression(first)))"
		case .lesserEqual:	return "(\(self.forceNumericExpression(second)) <= \(self.forceNumericExpression(first)))"

		case .notEqual:
			if second == "NULL" {
				return "(\(first) IS NOT NULL)"
			}
			else if first == "NULL" {
				return "(\(second) IS NOT NULL)"
			}
			else {
				return "(\(second) <> \(first))"
			}

		case .equal:
			if second == "NULL" {
				return "(\(first) IS NULL)"
			}
			else if first == "NULL" {
				return "(\(second) IS NULL)"
			}
			else {
				return "(\(second) = \(first))"
			}

			/* Most SQL database support the "a LIKE '%b%'" syntax for finding items where column a contains the string b
			(case-insensitive), so that's what we use for ContainsString and ContainsStringStrict. Because Presto doesn't
			support CONCAT with multiple parameters, we use two. */
		case .containsString: return "(LOWER(\(self.forceStringExpression(second))) LIKE CONCAT('%', CONCAT(LOWER(\(self.forceStringExpression(first))),'%')))"
		case .containsStringStrict: return "(\(self.forceStringExpression(second)) LIKE CONCAT('%',CONCAT(\(self.forceStringExpression(first)),'%')))"
		case .matchesRegex: return "(\(self.forceStringExpression(second)) REGEXP \(self.forceStringExpression(first)))"
		case .matchesRegexStrict: return "(\(self.forceStringExpression(second)) REGEXP BINARY \(self.forceStringExpression(first)))"
		}
	}
}

/** Logical fragments in an SQL statement, in order of logical execution. */
public enum SQLFragmentType {
	case from
	case join
	case `where`
	case group
	case having
	case order
	case limit
	case select
	case union
	case offset
	
	var precedingType: SQLFragmentType? {
		switch self {
		case .from: return nil
		case .join: return .from
		case .where: return .join
		case .group: return .where
		case .having: return .group
		case .order: return .having
		case .limit: return .order
		case .offset: return .limit
		case .select: return .offset
		case .union: return .select
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

Note that SQLFragment is not concerned with filling in the actual fragments - that is the job of SQLDataset. */
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
		self.init(type: .from, sql: "FROM \(dialect.tableIdentifier(table,  schema: schema, database: database))", dialect: dialect, alias: table)
	}
	
	public convenience init(query: String, dialect: SQLDialect) {
		let alias = "T\(abs(query.hash))"
		
		// TODO: can use WITH..AS syntax here for DBMS'es that work better with that
		self.init(type: .from, sql: "FROM (\(query)) AS \(dialect.tableIdentifier(alias, schema: nil, database: nil))", dialect: dialect, alias: alias)
	}
	
	/** 
	Returns the table alias to be used in the next call that adds a part; for example:
	  
	let fragment = SQLFragment(table: "test", dialect: ...)
	let newFragment = fragment.sqlOrder(dialect.columnIdentifier("col", table: fragment.aliasFor(.Order)) + " ASC")
	*/
	func aliasFor(_ part: SQLFragmentType) -> String {
		return advance(part, part: "X").alias
	}
	
	// State transitions
	public func sqlWhere(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.where, part: part)
	}
	
	public func sqlJoin(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.join, part: part)
	}
	
	public func sqlGroup(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.group, part: part)
	}
	
	public func sqlHaving(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.having, part: part)
	}
	
	public func sqlOrder(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.order, part: part)
	}
	
	public func sqlLimit(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.limit, part: part)
	}

	public func sqlOffset(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.offset, part: part)
	}
	
	public func sqlSelect(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.select, part: part)
	}
	
	public func sqlUnion(_ part: String?) -> SQLFragment {
		return advance(SQLFragmentType.union, part: part)
	}
	
	/** Add a WHERE or HAVING clause with the given SQL for the condition part, depending on the state the query is 
	currently in. This can be used to add another filter to the query without creating a new subquery layer, only for
	conditions for which WHERE and HAVING have the same effect. */
	public func sqlWhereOrHaving(_ part: String?) -> SQLFragment {
		if self.type == .group {
			return sqlHaving(part)
		}
		return sqlWhere(part)
	}
	
	var asSubquery: SQLFragment { get {
		return SQLFragment(query: self.sqlSelect(nil).sql, dialect: dialect)
	} }
	
	fileprivate func advance(_ toType: SQLFragmentType, part: String?) -> SQLFragment {
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
			case .group:
				fullPart = "\(source.sql) GROUP BY \(p)"

			case .where:
				fullPart = "\(source.sql) WHERE \(p)"

			case .join:
				fullPart = "\(source.sql) \(p)"

			case .having:
				fullPart = "\(source.sql) HAVING \(p)"

			case .order:
				fullPart = "\(source.sql) ORDER BY \(p)"

			case .limit:
				fullPart = "\(source.sql) LIMIT \(p)"

			case .offset:
				fullPart = "\(source.sql) OFFSET \(p)"

			case .select:
				fullPart = "SELECT \(p) \(source.sql)"

			case .union:
				fullPart = "(\(source.sql)) UNION (\(p))";

			case .from:
				fatalError("Cannot advance to FROM with a part")
			}
		}
		else {
			switch toType {
			case .select:
				fullPart = "SELECT * \(source.sql)"

			default:
				fullPart = source.sql
			}
		}
		
		return SQLFragment(type: toType, sql: fullPart, dialect: source.dialect, alias: source.alias)
	}
}

/** SQLDataset implements a general SQL-based data source. It maintains a single SQL statement that (when executed) 
should return the data represented by this data set. This class needs to be subclassed to be able to actually fetch the
data (a subclass implements the raster function to return the fetched data, preferably the stream function to return a
stream of results, and the apply function, to make sure any operations on the data set return a data set of the same
subclassed type). See QBESQLite for an implementation example. */
open class SQLDataset: NSObject, Dataset {
    public let sql: SQLFragment
	public let columns: OrderedSet<Column>
	
	public init(fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.columns = columns
		self.sql = fragment
	}
	
	public init(sql: String, dialect: SQLDialect, columns: OrderedSet<Column>) {
		self.sql = SQLFragment(query: sql, dialect: dialect)
		self.columns = columns
    }
	
	public init(table: String, schema: String?, database: String, dialect: SQLDialect, columns: OrderedSet<Column>) {
		self.sql = SQLFragment(table: table, schema: schema, database: database, dialect: dialect)
		self.columns = columns
	}
	
	private func fallback() -> Dataset {
		return StreamDataset(source: self.stream())
	}
	
	open func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success(columns))
	}
	
	open func raster(_ job: Job, deliver: Delivery, callback: @escaping (Fallible<Raster>, StreamStatus) -> ()) {
		job.async {
			StreamDataset(source: self.stream()).raster(job, deliver: deliver, callback: callback)
		}
	}
	
	/** Transposition is difficult in SQL, and therefore left to RasterDataset. */
   open func transpose() -> Dataset {
		return fallback().transpose()
    }
	
	open func pivot(_ horizontal: OrderedSet<Column>, vertical: OrderedSet<Column>, values: OrderedSet<Column>) -> Dataset {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}
	
	open func flatten(_ valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) -> Dataset {
		return fallback().flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to)
	}
	
	open func union(_ data: Dataset) -> Dataset {
		if let rightSQL = data as? SQLDataset, isCompatibleWith(rightSQL) {
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
	
	open func join(_ join: Join) -> Dataset {
		if let sqlJoinType = sql.dialect.joinType(join.type) {
			switch join.type {
			case .leftJoin, .innerJoin:
				// We need to 'unpack' coalesced data to get to the actual data
				let rightDataset = join.foreignDataset.underlyingDataset
								
				// Check if the other data set is a compatible SQL data set
				if let rightSQL = rightDataset as? SQLDataset, isCompatibleWith(rightSQL) {
					// Get SQL from right dataset
					let rightQuery = rightSQL.sql.sqlSelect(nil).sql
					let leftAlias = self.sql.aliasFor(.join)
					let rightAlias = "F\(abs(rightQuery.hash))"
					
					// Which columns?
					let leftColumns = self.columns
					let rightColumns = rightSQL.columns.filter({!leftColumns.contains($0)})
					if rightColumns.count > 0 {
						let rightSelects = rightColumns.map({return self.sql.dialect.columnIdentifier($0, table: rightAlias, schema: nil, database: nil) + " AS " + self.sql.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil)}).joined(separator: ", ")
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
	
	/** Determines whether another SQLDataset set is 'compatible' with this one. Compatible means that the two data sets 
	are actually in the same database, so that a join (or other merging operation) is possible between these datasets. By
	default, we assume data sets are never compatible. */
	open func isCompatibleWith(_ other: SQLDataset) -> Bool {
		return false
	}
	
	open func calculate(_ calculations: Dictionary<Column, Expression>) -> Dataset {
		var values: [String] = []
		var newColumns = columns
		
		let sourceSQL = sql
		let sourceAlias = sourceSQL.aliasFor(.select)
		
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
		
		let valueString = values.joined(separator: ", ")
		return apply(sourceSQL.sqlSelect(valueString), resultingColumns: newColumns)
    }
	
	open func sort(_ by: [Order]) -> Dataset {
		var error = false
		
		let sqlOrders = by.map({(order) -> (String) in
			if let expression = order.expression, let esql = self.sql.dialect.expressionToSQL(expression, alias: self.sql.aliasFor(.order), foreignAlias: nil,inputValue: nil) {
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
		
		let orderClause = sqlOrders.joined(separator: ", ")
		return apply(sql.sqlOrder(orderClause), resultingColumns: columns)
	}
	
	open func distinct() -> Dataset {
		return apply(self.sql.sqlSelect("DISTINCT *"), resultingColumns: columns)
	}
    
    open func limit(_ numberOfRows: Int) -> Dataset {
		return apply(self.sql.sqlLimit("\(numberOfRows)"), resultingColumns: columns)
    }

	/** This implements OFFSET. It assumed OFFSET can be put after LIMIT, or in the position where LIMIT would be if no
	limit is desired. In T-SQL, the "SELECT TOP x" syntax is used instead. In SQLite, LIMIT is always required, but can
	be set to -1 to obtain all rows (e.g. "LIMIT -1 OFFSET x"). This is not implemented here but is the responsibility 
	of implementing subclasses. */
	open func offset(_ numberOfRows: Int) -> Dataset {
		return apply(sql.sqlOffset("\(numberOfRows)"), resultingColumns: columns)
	}
	
	open func filter(_ condition: Expression) -> Dataset {
		let optimizedCondition = condition.prepare()
		if optimizedCondition.isConstant {
			let constantValue = optimizedCondition.apply(Row(), foreign: nil, inputValue: nil)
			if constantValue == Value(false) {
				// Never return any rows
				return RasterDataset(data: [], columns: self.columns)
			}
			else if constantValue == Value(true) {
				// Return all rows always
				return self
			}
		}

		if let expressionString = sql.dialect.expressionToSQL(condition.prepare(), alias: sql.aliasFor(.where), foreignAlias: nil,inputValue: nil) {
			return apply(sql.sqlWhereOrHaving(expressionString), resultingColumns: columns)
		}
		else {
			return fallback().filter(condition)
		}
	}
	
	open func random(_ numberOfRows: Int) -> Dataset {
		let randomFunction = sql.dialect.unaryToSQL(Function.Random, args: []) ?? "RANDOM()"
		return apply(sql.sqlOrder(randomFunction).sqlLimit("\(numberOfRows)"), resultingColumns: columns)
	}
	
	open func unique(_ expression: Expression, job: Job, callback: @escaping (Fallible<Set<Value>>) -> ()) {
		let q = self.sql.asSubquery
		if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), alias: q.aliasFor(.select), foreignAlias: nil, inputValue: nil) {
			let data = apply(q.sqlSelect("DISTINCT \(expressionString) AS _value"), resultingColumns: ["_value"])
			
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
	
	open func selectColumns(_ columns: OrderedSet<Column>) -> Dataset {
		let colNames = columns.map { self.sql.dialect.columnIdentifier($0, table: nil, schema: nil, database: nil) }.joined(separator: ", ")
		return apply(self.sql.sqlSelect(colNames), resultingColumns: columns)
	}
	
	open func aggregate(_ groups: [Column : Expression], values: [Column : Aggregator]) -> Dataset {
		if groups.isEmpty && values.isEmpty {
			return StreamDataset(source: EmptyStream())
		}

		var groupBy: [String] = []
		var select: [String] = []
		var resultingColumns: OrderedSet<Column> = []

		let alias = groups.count > 0 ? self.sql.aliasFor(.group) : self.sql.aliasFor(.select)

		// Write out grouping expressions
		for (column, expression) in groups {
			if let expressionString = self.sql.dialect.expressionToSQL(expression.prepare(), alias: alias, foreignAlias: nil, inputValue: nil) {
				select.append("\(expressionString) AS \(self.sql.dialect.columnIdentifier(column, table: nil, schema: nil, database: nil))")
				groupBy.append("\(expressionString)")
				resultingColumns.append(column)
			}
			else {
				return fallback().aggregate(groups, values: values)
			}
		}

		/* If there are no groups, we still need to skip the query past the .Group state (with groups, sqlGroup will be 
		called below, which will advance the query state past .Group). This is done here so we know the alias to use in 
		the select expressions. */
		let sql = groups.count == 0 ? self.sql.advance(.group, part: nil) : self.sql
		let aliasInSelect = groups.count == 0 ? sql.aliasFor(.select) : alias
		
		for (column, aggregation) in values {
			if let aggregationSQL = sql.dialect.aggregationToSQL(aggregation, alias: aliasInSelect) {
				select.append("\(aggregationSQL) AS \(sql.dialect.columnIdentifier(column, table: nil, schema: nil, database: nil))")
				resultingColumns.append(column)
			}
			else {
				// Fall back to default implementation for unsupported aggregation functions
				return fallback().aggregate(groups, values: values)
			}
		}
		
		let selectString = select.joined(separator: ", ")
		if groupBy.count>0 {
			let groupString = groupBy.joined(separator: ", ")
			return apply(sql.sqlGroup(groupString).sqlSelect(selectString), resultingColumns: resultingColumns)
		}
		else {
			// No columns to group by, total aggregates it is
			return apply(sql.sqlSelect(selectString), resultingColumns: resultingColumns)
		}
	}
	
	open func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return SQLDataset(fragment: fragment, columns: columns)
	}
	
	open func stream() -> Stream {
		fatalError("Stream() must be implemented by subclass of SQLDataset")
	}
}
