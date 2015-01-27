import Foundation

/** Classes that implement QBESQLDialect provide SQL generating classes with tools to build SQL queries in a particular
dialect. The standard dialect (implemented in QBEStandardSQLDialect) sticks as closely to the SQL92 standard (to implement
a particular dialect, the standard dialect should be subclassed and should only implement the exceptions). **/
protocol QBESQLDialect {
	/** The string that starts and ends a string literal. **/
	var stringQualifier: String { get }
	
	/** The string that is used to escape occurrences of the string qualifier in a literal. All occurrences are replaced
	with the escape qualifier before the string is inserted in SQL. **/
	var stringQualifierEscape: String { get }
	
	/** The string that is used to start and end identifiers (e.g. table or column names) in SQL. **/
	var identifierQualifier: String { get }
	
	/** The string that is used to escape the identifier qualifier in identifiers that contain it. **/
	var identifierQualifierEscape: String { get }
	
	/** Returns a column identifier for the given QBEColumn. **/
	func columnIdentifier(column: QBEColumn) -> String
	
	/** Transforms the given expression to a SQL string. The inputValue parameter determines the return value of the
	QBEIdentitiyExpression. **/
	func expressionToSQL(formula: QBEExpression, inputValue: String?) -> String
	
	/** Transforms the given aggregation to an aggregation description that can be incldued as part of a GROUP BY 
	statement. **/
	func aggregationToSQL(aggregation: QBEAggregation) -> String
}

class QBEStandardSQLDialect: QBESQLDialect {
	let stringQualifier = "\'"
	let stringQualifierEscape = "\\\'"
	let identifierQualifier = "\""
	let identifierQualifierEscape = "\\\""
	
	func columnIdentifier(column: QBEColumn) -> String {
		return "\(identifierQualifier)\(column.name.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
	}
	
	func tableIdentifier(table: String) -> String {
		return "\(identifierQualifier)\(table.stringByReplacingOccurrencesOfString(identifierQualifier, withString: identifierQualifierEscape))\(identifierQualifier)"
	}
	
	func expressionToSQL(formula: QBEExpression, inputValue: String? = nil) -> String {
		if let f = formula as? QBELiteralExpression {
			return valueToSQL(f.value)
		}
		else if let f = formula as? QBEIdentityExpression {
			return inputValue ?? "???"
		}
		else if let f = formula as? QBESiblingExpression {
			return columnIdentifier(f.columnName)
		}
		else if let f = formula as? QBEBinaryExpression {
			let first = expressionToSQL(f.first, inputValue: inputValue)
			let second = expressionToSQL(f.second, inputValue: inputValue)
			return binaryToSQL(first, second: second, type: f.type)
		}
		else if let f = formula as? QBEFunctionExpression {
			let argValues = f.arguments.map({self.expressionToSQL($0, inputValue: inputValue)})
			return unaryToSQL(argValues, type: f.type)
		}

		return "???"
	}
	
	func aggregationToSQL(aggregation: QBEAggregation) -> String {
		switch aggregation.reduce {
			case .Average: return "AVG(\(expressionToSQL(aggregation.map, inputValue: nil))"
			case .CountAll: return "COUNT(\(expressionToSQL(aggregation.map, inputValue: nil)))"
			// FIXME: TYPEOF and its return values will be different for other RDBMSes
			case .Count: return "SUM(CASE WHEN TYPEOF(\(expressionToSQL(aggregation.map, inputValue: nil)) IN('integer', 'real')) THEN 1 ELSE 0 END)"
			case .Sum: return "SUM(\(expressionToSQL(aggregation.map, inputValue: nil)))"
			case .Min: return "MIN(\(expressionToSQL(aggregation.map, inputValue: nil)))"
			case .Max: return "MAX(\(expressionToSQL(aggregation.map, inputValue: nil)))"
			
			/* FIXME: RandomItem can be implemented using a UDF aggregation function in PostgreSQL. Implementing it in 
			SQLite is not easy.. (perhaps QBE can define a UDF from Swift?). */
			case .RandomItem: fatalError("Not implemented")
			
			default:
				fatalError("Not implemented")
		}
	}
	
	private func unaryToSQL(args: [String], type: QBEFunction) -> String {
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
			case .Left: return "LEFT(\(args[0]), \(args[1]))"
			case .Right: return "RIGHT(\(args[0]), \(args[1]))"
			case .Mid: return "SUBSTRING(\(args[0]), \(args[1]), \(args[2]))"
			case .Length: return "LEN(\(args[0]))"
			case .Trim: return "TRIM(\(args[0]))"
				
			// FIXME: Log can receive either one parameter (log 10) or two parameters (log base)
			case .Log: return "LOG(\(value))"
			case .Not: return "NOT(\(value))"
			case .Substitute: return "REPLACE(\(args[0]), \(args[1]), \(args[2]))"
			case .Xor: return "((\(args[0])<>\(args[1])) AND (\(args[0]) OR \(args[1])))"
			case .Coalesce: return "COALESCE(\(value))"
			case .IfError: return "IFNULL(\(args[0]), \(args[1]))" // In SQLite, the result of (1/0) equals NULL
			case .Sum: return args.implode(" + ") ?? "0"
			case .Average: return "(" + (args.implode(" + ") ?? "0") + ")/\(args.count)"
			case .Min: return "MIN(\(value))" // Should be LEAST in SQL Server
			case .Max: return "MAX(\(value))" // Might be GREATEST in SQL Server
			case .RandomItem: return (args.count > 0) ? args[Int.random(0..<args.count)] : "NULL"
			
			/* FIXME: These could simply call QBEFunction.Count.apply() if the parameters are constant, but then we need 
			the original QBEExpression arguments. */
			case .Count: fatalError("Not implemented")
			case .CountAll:  fatalError("Not implemented")
			
			// FIXME: implement Pack in SQL (use REPLACE etc.)
			case .Pack: fatalError("Not implemented")
		}
	}
	
	private func valueToSQL(value: QBEValue) -> String {
		switch value {
			case .StringValue(let s):
				return "\(stringQualifier)\(s.stringByReplacingOccurrencesOfString(stringQualifier, withString: stringQualifierEscape))\(stringQualifier)"
				
			case .DoubleValue(let d):
				// FIXME: check decimal separator
				return "\(d)"
				
			case .IntValue(let i):
				return "\(i)"
				
			case .BoolValue(let b):
				return b ? "TRUE" : "FALSE"
				
			case .InvalidValue:
				return "(1/0)"
				
			case .EmptyValue:
				return "NULL"
		}
	}
	
	private func binaryToSQL(first: String, second: String, type: QBEBinary) -> String {
		switch type {
			case .Addition:		return "(\(first)+\(second))"
			case .Subtraction:	return "(\(first)-\(second))"
			case .Multiplication: return "(\(first)*\(second))"
			case .Division:		return "(\(first)/\(second))"
			case .Modulus:		return "MOD(\(first), \(second))"
			case .Concatenation: return "CONCAT(\(first),\(second))"
			case .Power:		return "POW(\(first), \(second))"
			case .Greater:		return "(\(first)>\(second))"
			case .Lesser:		return "(\(first)<\(second))"
			case .GreaterEqual:	return "(\(first)>=\(second))"
			case .LesserEqual:	return "(\(first)<=\(second))"
			case .Equal:		return "(\(first)=\(second))"
			case .NotEqual:		return "(\(first)<>\(second))"
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
	private var columns: [QBEColumn]
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(columns)
	}
	
	func raster(callback: (QBERaster) -> ()) {
		fatalError("Raster should be implemented by sublcass")
	}
    
	internal init(sql: String, dialect: QBESQLDialect, columns: [QBEColumn]) {
        self.sql = sql
		self.dialect = dialect
		self.columns = columns
    }
	
	/** Transposition is difficult in SQL, and therefore left to QBERasterData. **/
    func transpose() -> QBEData {
		return QBERasterData(future: { (cb) -> () in
			self.raster(cb)
		}).transpose()
    }
    
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		var values: [String] = []
		var targetFound = false
		
		// Re-calculate existing columns first
		for targetColumn in columns {
			if calculations[targetColumn] != nil {
				let expression = calculations[targetColumn]!
				values.append("\(dialect.expressionToSQL(expression, inputValue: dialect.columnIdentifier(targetColumn))) AS \(dialect.columnIdentifier(targetColumn))")
			}
			else {
				values.append(targetColumn.name)
			}
		}
		
		// New columns are added at the end
		for (targetColumn, expression) in calculations {
			if !columns.contains(targetColumn) {
				values.append("\(dialect.expressionToSQL(expression, inputValue: dialect.columnIdentifier(targetColumn))) AS \(dialect.columnIdentifier(targetColumn))")
			}
		}
		
		if let valueString = values.implode(", ") {
			return apply("SELECT \(valueString) FROM (\(sql))", resultingColumns: columns)
		}
		return QBERasterData()
    }
    
    func limit(numberOfRows: Int) -> QBEData {
		return apply("SELECT * FROM (\(self.sql)) LIMIT \(numberOfRows)", resultingColumns: columns)
    }
	
	func random(numberOfRows: Int) -> QBEData {
		return apply("SELECT * FROM (\(self.sql)) ORDER BY RANDOM() LIMIT \(numberOfRows)", resultingColumns: columns)
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
			select.append("\(dialect.expressionToSQL(expression, inputValue: nil)) AS \(dialect.columnIdentifier(column))")
			groupBy.append("\(dialect.expressionToSQL(expression, inputValue: nil))")
			resultingColumns.append(column)
		}
		
		for (column, aggregation) in values {
			select.append("\(dialect.aggregationToSQL(aggregation)) AS \(dialect.columnIdentifier(column))")
			resultingColumns.append(column)
		}
		
		let selectString = select.implode(", ") ?? ""
		if let groupString = groupBy.implode(", ") {
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
	
	func stream() -> QBEStream? {
		/* The default implementation just fetches a raster and streams that, which obviously is not very efficient for 
		large data sets, as it eats up a lot of memory that is not needed (that's what streaming is good for in the first 
		place). Subclasses are encouraged to implement this more efficiently (e.g. by stepping through their result sets). */
		return QBERasterData(future: { (cb) -> () in
			self.raster(cb)
		}).stream()
	}
}