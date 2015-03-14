import Foundation

/** Classes that implement QBESQLDialect provide SQL generating classes with tools to build SQL queries in a particular
dialect. The standard dialect (implemented in QBEStandardSQLDialect) sticks as closely to the SQL92 standard (to implement
a particular dialect, the standard dialect should be subclassed and should only implement the exceptions). **/
protocol QBESQLDialect {
	/** The string that starts and ends a string literal. **/
	var stringQualifier: String { get }
	
	/** The escape character used inside string literals to escape special characters. Usually '\' **/
	var stringEscape: String { get }
	
	/** The string that is used to escape occurrences of the string qualifier in a literal. All occurrences are replaced
	with the escape qualifier before the string is inserted in SQL. **/
	var stringQualifierEscape: String { get }
	
	/** The string that is used to start and end identifiers (e.g. table or column names) in SQL. **/
	var identifierQualifier: String { get }
	
	/** The string that is used to escape the identifier qualifier in identifiers that contain it. **/
	var identifierQualifierEscape: String { get }
	
	/** Returns a column identifier for the given QBEColumn. **/
	func columnIdentifier(column: QBEColumn) -> String
	
	func tableIdentifier(table: String) -> String
	
	/** Transforms the given expression to a SQL string. The inputValue parameter determines the return value of the
	QBEIdentitiyExpression. The function may return nil for expressions it cannot successfully transform to SQL. **/
	func expressionToSQL(formula: QBEExpression, inputValue: String?) -> String?
	
	/** Transforms the given aggregation to an aggregation description that can be incldued as part of a GROUP BY 
	statement. The function may return nil for aggregations it cannot represent or transform to SQL. **/
	func aggregationToSQL(aggregation: QBEAggregation) -> String?
}

class QBESQLDatabase {
	var dialect: QBESQLDialect
	
	internal init(dialect: QBESQLDialect) {
		self.dialect = dialect
	}
}

class QBEStandardSQLDialect: QBESQLDialect {
	let stringQualifier = "\'"
	let stringQualifierEscape = "\\\'"
	let identifierQualifier = "\""
	let identifierQualifierEscape = "\\\""
	let stringEscape = "\\"
	
	func columnIdentifier(column: QBEColumn) -> String {
		return "\(identifierQualifier)\(column.name.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
	}
	
	func tableIdentifier(table: String) -> String {
		return "\(identifierQualifier)\(table.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
	}
	
	private func literalString(str: String) -> String {
		let escaped = str
			.stringByReplacingOccurrencesOfString(stringEscape, withString: stringEscape+stringEscape)
			.stringByReplacingOccurrencesOfString(stringQualifier, withString: stringQualifierEscape)
		return "\(stringQualifier)\(escaped)\(stringQualifier)"
	}
	
	func expressionToSQL(formula: QBEExpression, inputValue: String? = nil) -> String? {
		if formula.isConstant {
			let result = formula.apply([], columns: [], inputValue: nil)
			return valueToSQL(result)
		}
		
		if let f = formula as? QBELiteralExpression {
			fatalError("This code is unreachable since literals should always be constant")
		}
		else if let f = formula as? QBEIdentityExpression {
			return inputValue ?? "???"
		}
		else if let f = formula as? QBESiblingExpression {
			return columnIdentifier(f.columnName)
		}
		else if let f = formula as? QBEBinaryExpression {
			if let first = expressionToSQL(f.first, inputValue: inputValue) {
				if let second = expressionToSQL(f.second, inputValue: inputValue) {
					return binaryToSQL(f.type, first: first, second: second)
				}
			}
			return nil
		}
		else if let f = formula as? QBEFunctionExpression {
			var anyNils = false
			let argValues = f.arguments.map({(e: QBEExpression) -> (String) in
				let r = self.expressionToSQL(e, inputValue: inputValue)
				if r == nil {
					anyNils = true
				}
				return r ?? ""
			})
			return anyNils ? nil : unaryToSQL(f.type, args: argValues)
		}

		return nil
	}
	
	func aggregationToSQL(aggregation: QBEAggregation) -> String? {
		if let expressionSQL = expressionToSQL(aggregation.map, inputValue: nil) {
			switch aggregation.reduce {
				case .Average: return "AVG(\(expressionSQL))"
				case .CountAll: return "COUNT(\(expressionSQL))"
				
				// FIXME: TYPEOF and its return values will be different for other RDBMSes
				case .Count: return "SUM(CASE WHEN TYPEOF(\(expressionSQL)) IN('integer', 'real')) THEN 1 ELSE 0 END)"
				case .Sum: return "SUM(\(expressionSQL))"
				case .Min: return "MIN(\(expressionSQL))"
				case .Max: return "MAX(\(expressionSQL))"
				case .Concat: return "GROUP_CONCAT(\(expressionSQL),'')"
				
				case .Pack:
					return "GROUP_CONCAT(REPLACE(REPLACE(\(expressionSQL),\(literalString(QBEPackEscape)),\(literalString(QBEPackEscapeEscape))),\(literalString(QBEPackSeparator)),\(literalString(QBEPackSeparatorEscape))), \(literalString(QBEPackSeparator)))"
				
				default:
					/* TODO: RandomItem can be implemented using a UDF aggregation function in PostgreSQL. Implementing it in
					SQLite is not easy.. (perhaps QBE can define a UDF from Swift?). */
					return nil
			}
		}
		else {
			return nil
		}
	}

	internal func unaryToSQL(type: QBEFunction, args: [String]) -> String? {
		let value = args.implode(", ") ?? ""
		switch type {
			case .Identity: return value
			case .Negate: return "-\(value)"
			case .Uppercase: return "UPPER(\(value))"
			case .Lowercase: return "LOWER(\(value))"
			case .Absolute: return "ABS(\(value))"
			case .And: return "AND(\(value))"
			case .Or: return "OR(\(value))"
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
			case .Sum: return args.implode(" + ") ?? "0"
			case .Average: return "(" + (args.implode(" + ") ?? "0") + ")/\(args.count)"
			case .Min: return "MIN(\(value))" // Should be LEAST in SQL Server
			case .Max: return "MAX(\(value))" // Might be GREATEST in SQL Server
			case .RandomBetween:
				/* FIXME check this! Using RANDOM() with modulus introduces a bias, but because we're using ABS, the bias
				should be cancelled out. See http://stackoverflow.com/questions/8304204/generating-only-positive-random-numbers-in-sqlite */
				return "(\(args[0]) + ABS(RANDOM() % (\(args[1])-\(args[0]))))"
			
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
			
			
			/* FIXME: These could simply call QBEFunction.Count.apply() if the parameters are constant, but then we need
			the original QBEExpression arguments. */
			case .Count: return nil
			case .CountAll: return nil
			case .Pack: return nil
			
			// FIXME: should be implemented as CASE WHEN i=1 THEN a WHEN i=2 THEN b ... END
			case .Choose: return nil
			
		}
	}
	
	internal func valueToSQL(value: QBEValue) -> String {
		switch value {
			case .StringValue(let s):
				return literalString(s)
				
			case .DoubleValue(let d):
				// FIXME: check decimal separator
				return "\(d)"
				
			case .IntValue(let i):
				return "\(i)"
				
			case .BoolValue(let b):
				return b ? "(1=1)" : "(1=0)"
				
			case .InvalidValue:
				return "(1/0)"
				
			case .EmptyValue:
				return "NULL"
		}
	}
	
	internal func binaryToSQL(type: QBEBinary, first: String, second: String) -> String {
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
		}
	}
}

/** QBESQLData implements a general SQL-based data source. It maintains a single SQL statement that (when executed) 
should return the data represented by this data set. This class needs to be subclassed to be able to actually fetch the
data (a subclass implements the raster function to return the fetched data, preferably the stream function to return a
stream of results, and the apply function, to make sure any operations on the data set return a data set of the same
subclassed type). See QBESQLite for an implementation example. **/
class QBESQLData: NSObject, QBEData {
    internal let sql: String
	let dialect: QBESQLDialect
	var columns: [QBEColumn]
    
	internal init(sql: String, dialect: QBESQLDialect, columns: [QBEColumn]) {
        self.sql = sql
		self.dialect = dialect
		self.columns = columns
    }
	
	private func fallback() -> QBEData {
		return QBEStreamData(source: self.stream())
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(columns)
	}
	
	func raster(job: QBEJob?, callback: (QBERaster) -> ()) {
		QBEStreamData(source: self.stream()).raster(job, callback: callback)
	}
	
	/** Transposition is difficult in SQL, and therefore left to QBERasterData. **/
    func transpose() -> QBEData {
		return fallback().transpose()
    }
	
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		return fallback().pivot(horizontal, vertical: vertical, values: values)
	}
	
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData {
		return fallback().flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to)
	}
    
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		var values: [String] = []
		var targetFound = false
		
		// Re-calculate existing columns first
		for targetColumn in columns {
			if calculations[targetColumn] != nil {
				let expression = calculations[targetColumn]!.prepare()
				if let expressionString = dialect.expressionToSQL(expression, inputValue: dialect.columnIdentifier(targetColumn)) {
					values.append("\(expressionString) AS \(dialect.columnIdentifier(targetColumn))")
				}
				else {
					return fallback().calculate(calculations)
				}
			}
			else {
				values.append(dialect.columnIdentifier(targetColumn))
			}
		}
		
		// New columns are added at the end
		for (targetColumn, expression) in calculations {
			if !columns.contains(targetColumn) {
				if let expressionString = dialect.expressionToSQL(expression.prepare(), inputValue: dialect.columnIdentifier(targetColumn)) {
					values.append("\(expressionString) AS \(dialect.columnIdentifier(targetColumn))")
				}
				else {
					return fallback().calculate(calculations)
				}
			}
		}
		
		if let valueString = values.implode(", ") {
			return apply("SELECT \(valueString) FROM (\(sql))", resultingColumns: columns)
		}
		return QBERasterData()
    }
	
	func distinct() -> QBEData {
		return apply("SELECT DISTINCT * FROM (\(self.sql))", resultingColumns: columns)
	}
    
    func limit(numberOfRows: Int) -> QBEData {
		return apply("SELECT * FROM (\(self.sql)) LIMIT \(numberOfRows)", resultingColumns: columns)
    }
	
	func offset(numberOfRows: Int) -> QBEData {
		// FIXME: T-SQL uses "SELECT TOP x" syntax
		// FIXME: the LIMIT -1 is probably only necessary for SQLite
		return apply("SELECT * FROM (\(self.sql)) LIMIT -1 OFFSET \(numberOfRows)", resultingColumns: columns)
	}
	
	func filter(condition: QBEExpression) -> QBEData {
		if let expressionString = dialect.expressionToSQL(condition.prepare(), inputValue: nil) {
			return apply("SELECT * FROM (\(self.sql)) WHERE \(expressionString)", resultingColumns: columns)
		}
		else {
			return fallback().filter(condition)
		}
	}
	
	func random(numberOfRows: Int) -> QBEData {
		return apply("SELECT * FROM (\(self.sql)) ORDER BY RANDOM() LIMIT \(numberOfRows)", resultingColumns: columns)
	}
	
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) {
		if let expressionString = dialect.expressionToSQL(expression.prepare(), inputValue: nil) {
			let query = "SELECT DISTINCT \(expressionString) AS _value FROM \(self.sql)"
			let data = apply(query, resultingColumns: ["_value"])
			
			data.raster(nil, callback: { (raster) -> () in
				let values = Set<QBEValue>(raster.raster.map({$0[0]}))
				callback(values)
			})
		}
		else {
			return fallback().unique(expression, callback: callback)
		}
	}
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		let colNames = columns.map({self.dialect.columnIdentifier($0)}).implode(", ") ?? ""
		let sql = "SELECT \(colNames) FROM (\(self.sql))"
		return apply(sql, resultingColumns: columns)
	}
	
	func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
		var groupBy: [String] = []
		var select: [String] = []
		var resultingColumns: [QBEColumn] = []
		
		for (column, expression) in groups {
			if let expressionString = dialect.expressionToSQL(expression.prepare(), inputValue: nil) {
				select.append("\(expressionString) AS \(dialect.columnIdentifier(column))")
				groupBy.append("\(expressionString)")
				resultingColumns.append(column)
			}
			else {
				return fallback().aggregate(groups, values: values)
			}
		}
		
		for (column, aggregation) in values {
			if let aggregationSQL = dialect.aggregationToSQL(aggregation) {
				select.append("\(aggregationSQL) AS \(dialect.columnIdentifier(column))")
				resultingColumns.append(column)
			}
			else {
				// Fall back to default implementation for unsupported aggregation functions
				return fallback().aggregate(groups, values: values)
			}
		}
		
		let selectString = select.implode(", ") ?? ""
		if groupBy.count>0, let groupString = groupBy.implode(", ") {
			return apply("SELECT \(selectString) FROM (\(sql)) GROUP BY \(groupString)", resultingColumns: resultingColumns)
		}
		else {
			// No columns to group by, total aggregates it is
			return apply("SELECT \(selectString) FROM (\(sql))", resultingColumns: resultingColumns)
		}
	}
	
	func apply(sql: String, resultingColumns: [QBEColumn]) -> QBEData {
		return QBESQLData(sql: sql, dialect: dialect, columns: columns)
	}
	
	func stream() -> QBEStream {
		fatalError("Stream() must be implemented by subclass of QBESQLData")
	}
}