import Foundation

/** The QBESQL family of classes enables data operations to be pushed down to SQL for efficient execution. In order for 
this to work properly and consistently, the calculations need to behave exactly like the (in-memory) reference 
implementations provided by QBERaster/QBEStream. There are two problems associated with that:

- The SQL type system is different than the QBE type system. A lot has been done to align the two type systems closely.
  * The QBEValue types map rougly to the basic SQL types VARCHAR/TEXT (StringValue), BOOL or INT (BoolValue), DOUBLE
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
   
   In order to overcome the differences between DBMS'es, QBE uses the concept of a "SQL Dialect" which defines the mapping
   from and to SQL for different SQL vendors. The default dialect closely matches SQL/92. For each vendor, a subclass of
   QBESQLDialect defines exceptions.

- The DBMS may use a different locale than the application. Care is taken not to rely too much on locale-dependent parts.

Even with the measures above in place, there may still be differences between our reference implementation and SQL. **/

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
	
	func unaryToSQL(type: QBEFunction, args: [String]) -> String?
	func binaryToSQL(type: QBEBinary, first: String, second: String) -> String?
	
	/** Transforms the given aggregation to an aggregation description that can be incldued as part of a GROUP BY 
	statement. The function may return nil for aggregations it cannot represent or transform to SQL. **/
	func aggregationToSQL(aggregation: QBEAggregation) -> String?
	
	/** Create an expression that forces the specified expression to a numeric type (DOUBLE or INT in SQL). **/
	func forceNumericExpression(expression: String) -> String
	
	/** Create an expression that forces the specified expression to a string type (e.g. VARCHAR or TEXT in SQL). **/
	func forceStringExpression(expression: String) -> String
}

class QBESQLDatabase {
	var dialect: QBESQLDialect
	
	internal init(dialect: QBESQLDialect) {
		self.dialect = dialect
	}
}

class QBEStandardSQLDialect: QBESQLDialect {
	var stringQualifier: String { get { return "\'" } }
	var stringQualifierEscape: String { get { return "\\\'" } }
	var identifierQualifier: String { get { return "\"" } }
	var identifierQualifierEscape: String { get { return "\\\"" } }
	var stringEscape: String { get { return "\\" } }
	
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
	
	func forceNumericExpression(expression: String) -> String {
		return "CAST(\(expression) AS NUMERIC)"
	}
	
	func forceStringExpression(expression: String) -> String {
		return "CAST(\(expression) AS TEXT)"
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
				case .CountAll: return "COUNT(*)"
				case .Sum: return "SUM(\(expressionSQL))"
				case .Min: return "MIN(\(expressionSQL))"
				case .Max: return "MAX(\(expressionSQL))"
				case .Concat: return "GROUP_CONCAT(\(expressionSQL),'')"
				
				case .Pack:
					return "GROUP_CONCAT(REPLACE(REPLACE(\(expressionSQL),\(literalString(QBEPack.Escape)),\(literalString(QBEPack.EscapeEscape))),\(literalString(QBEPack.Separator)),\(literalString(QBEPack.SeparatorEscape))), \(literalString(QBEPack.Separator)))"
				
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
			
			case .And:
				let ands = args.implode(" AND ") ?? "FALSE"
				return "(\(ands))"
				
			case .Or:
				let ors = args.implode(" OR ") ?? "TRUE"
				return "(\(ors))"
			
			case .RandomBetween:
				/* FIXME check this! Using RANDOM() with modulus introduces a bias, but because we're using ABS, the bias
				should be cancelled out. See http://stackoverflow.com/questions/8304204/generating-only-positive-random-numbers-in-sqlite */
				let rf = self.unaryToSQL(QBEFunction.Random, args: []) ?? "RANDOM()"
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
			
			
			/* FIXME: These could simply call QBEFunction.Count.apply() if the parameters are constant, but then we need
			the original QBEExpression arguments. */
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
				return "''"
		}
	}
	
	internal func binaryToSQL(type: QBEBinary, first: String, second: String) -> String? {
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

/** Logical fragments in an SQL statement, in order of logical execution. **/
internal enum QBESQLFragmentType {
	case From
	case Where
	case Group
	case Having
	case Order
	case Limit
	case Select
	
	var precedingType: QBESQLFragmentType? {
		switch self {
		case .From: return nil
		case .Where: return .From
		case .Group: return .Where
		case .Having: return .Group
		case .Order: return .Having
		case .Limit: return .Order
		case .Select: return .Limit
		}
	}
}

/** QBESQLFragment is used to generate SQL queries in an efficient manner, by taking the logical execution order of an SQL
statement into account. Fragments can be added to an existing fragment by calling one of the sql* functions. If the 
fragment logically followed the existing one (e.g. a LIMIT after a WHERE), it will be added to the fragment. If however
the added fragment does *not* logically follow the existing fragment (e.g. a WHERE after a LIMIT), the existing fragment
is made to be a subquery of a new query in which the added fragment is put. 

Why go through all this trouble? Some RDBMS'es execute subqueries naively, leading to very large temporary tables. By 
combining as much limiting factors in a subquery as possible, the size of intermediate results can be decreased, resulting
in higher performance. Another issue is that indexes can often not be used to accelerate lookups on derived tables. By
combining operations in a single query, they stay 'closer' to the original table, and the chance we can use an available
index is higher.

Note that QBESQLFragment is not concerned with filling in the actual fragments - that is the job of QBESQLData. **/
internal class QBESQLFragment {
	let type: QBESQLFragmentType
	let sql: String
	let dialect: QBESQLDialect
	let alias: String
	
	init(type: QBESQLFragmentType, sql: String, dialect: QBESQLDialect, alias: String) {
		self.type = type
		self.sql = sql
		self.dialect = dialect
		self.alias = alias
	}
	
	convenience init(table: String, dialect: QBESQLDialect) {
		self.init(type: .From, sql: "FROM \(dialect.tableIdentifier(table))", dialect: dialect, alias: table)
	}
	
	convenience init(query: String, dialect: QBESQLDialect) {
		let alias = "T\(abs(query.hash))"
		
		// TODO: can use WITH..AS syntax here for DBMS'es that work better with that
		self.init(type: .From, sql: "FROM (\(query)) AS \(dialect.tableIdentifier(alias))", dialect: dialect, alias: alias)
	}
	
	// State transitions
	func sqlWhere(part: String?) -> QBESQLFragment {
		return advance(QBESQLFragmentType.Where, part: part)
	}
	
	func sqlGroup(part: String?) -> QBESQLFragment {
		return advance(QBESQLFragmentType.Group, part: part)
	}
	
	func sqlHaving(part: String?) -> QBESQLFragment {
		return advance(QBESQLFragmentType.Having, part: part)
	}
	
	func sqlOrder(part: String?) -> QBESQLFragment {
		return advance(QBESQLFragmentType.Order, part: part)
	}
	
	func sqlLimit(part: String?) -> QBESQLFragment {
		return advance(QBESQLFragmentType.Limit, part: part)
	}
	
	func sqlSelect(part: String?) -> QBESQLFragment {
		return advance(QBESQLFragmentType.Select, part: part)
	}
	
	private func advance(toType: QBESQLFragmentType, part: String?) -> QBESQLFragment {
		// From which state can one go to the to-state?
		let precedingType = toType.precedingType
		let source: QBESQLFragment
		
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
			source = QBESQLFragment(query: self.sqlSelect(nil).sql, dialect: dialect)
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
				
				case .Having:
					fullPart = "\(source.sql) HAVING \(p)"
				
				case .Order:
					fullPart = "\(source.sql) ORDER BY \(p)"
				
				case .Limit:
					fullPart = "\(source.sql) LIMIT \(p)"
				
				case .Select:
					fullPart = "SELECT \(p) \(source.sql)"
				
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
		
		return QBESQLFragment(type: toType, sql: fullPart, dialect: source.dialect, alias: source.alias)
	}
}

/** QBESQLData implements a general SQL-based data source. It maintains a single SQL statement that (when executed) 
should return the data represented by this data set. This class needs to be subclassed to be able to actually fetch the
data (a subclass implements the raster function to return the fetched data, preferably the stream function to return a
stream of results, and the apply function, to make sure any operations on the data set return a data set of the same
subclassed type). See QBESQLite for an implementation example. **/
class QBESQLData: NSObject, QBEData {
    internal let sql: QBESQLFragment
	var columns: [QBEColumn]
	
	internal init(fragment: QBESQLFragment, columns: [QBEColumn]) {
		self.columns = columns
		self.sql = fragment
	}
	
	internal init(sql: String, dialect: QBESQLDialect, columns: [QBEColumn]) {
		self.sql = QBESQLFragment(query: sql, dialect: dialect)
		self.columns = columns
    }
	
	internal init(table: String, dialect: QBESQLDialect, columns: [QBEColumn]) {
		self.sql = QBESQLFragment(table: table, dialect: dialect)
		self.columns = columns
	}
	
	private func fallback() -> QBEData {
		return QBEStreamData(source: self.stream())
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		callback(columns)
	}
	
	func raster(job: QBEJob?, callback: (QBERaster) -> ()) {
		QBEAsyncBackground {
			QBEStreamData(source: self.stream()).raster(job, callback: callback)
		}
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
		var newColumns = columns
		
		// Re-calculate existing columns first
		for targetColumn in columns {
			if calculations[targetColumn] != nil {
				let expression = calculations[targetColumn]!.prepare()
				if let expressionString = sql.dialect.expressionToSQL(expression, inputValue: sql.dialect.columnIdentifier(targetColumn)) {
					values.append("\(expressionString) AS \(sql.dialect.columnIdentifier(targetColumn))")
				}
				else {
					return fallback().calculate(calculations)
				}
			}
			else {
				values.append(sql.dialect.columnIdentifier(targetColumn))
			}
		}
		
		// New columns are added at the end
		for (targetColumn, expression) in calculations {
			if !columns.contains(targetColumn) {
				if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), inputValue: sql.dialect.columnIdentifier(targetColumn)) {
					values.append("\(expressionString) AS \(sql.dialect.columnIdentifier(targetColumn))")
				}
				else {
					return fallback().calculate(calculations)
				}
				newColumns.append(targetColumn)
			}
		}
		
		if let valueString = values.implode(", ") {
			return apply(sql.sqlSelect(valueString), resultingColumns: newColumns)
		}
		return QBERasterData()
    }
	
	func sort(by: [QBEOrder]) -> QBEData {
		var error = false
		
		let sqlOrders = by.map({(order) -> (String) in
			if let expression = order.expression, let esql = self.sql.dialect.expressionToSQL(expression, inputValue: nil) {
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
		
		if let orderClause = sqlOrders.implode(", ") {
			return apply(sql.sqlOrder(orderClause), resultingColumns: columns)
		}
		return self
	}
	
	func distinct() -> QBEData {
		return apply(self.sql.sqlSelect("DISTINCT *"), resultingColumns: columns)
	}
    
    func limit(numberOfRows: Int) -> QBEData {
		return apply(self.sql.sqlLimit("\(numberOfRows)"), resultingColumns: columns)
    }
	
	func offset(numberOfRows: Int) -> QBEData {
		// FIXME: T-SQL uses "SELECT TOP x" syntax
		// FIXME: the LIMIT -1 is probably only necessary for SQLite
		return apply(sql.sqlLimit("-1 OFFSET \(numberOfRows)"), resultingColumns: columns)
	}
	
	func filter(condition: QBEExpression) -> QBEData {
		if let expressionString = sql.dialect.expressionToSQL(condition.prepare(), inputValue: nil) {
			return apply(sql.sqlWhere(expressionString), resultingColumns: columns)
		}
		else {
			return fallback().filter(condition)
		}
	}
	
	func random(numberOfRows: Int) -> QBEData {
		let randomFunction = sql.dialect.unaryToSQL(QBEFunction.Random, args: []) ?? "RANDOM()"
		return apply(sql.sqlOrder(randomFunction).sqlLimit("\(numberOfRows)"), resultingColumns: columns)
	}
	
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) {
		if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), inputValue: nil) {
			let data = apply(self.sql.sqlSelect("DISTINCT \(expressionString) AS _value"), resultingColumns: ["_value"])
			
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
		let colNames = columns.map({self.sql.dialect.columnIdentifier($0)}).implode(", ") ?? ""
		return apply(self.sql.sqlSelect(colNames), resultingColumns: columns)
	}
	
	func aggregate(groups: [QBEColumn : QBEExpression], values: [QBEColumn : QBEAggregation]) -> QBEData {
		var groupBy: [String] = []
		var select: [String] = []
		var resultingColumns: [QBEColumn] = []
		
		for (column, expression) in groups {
			if let expressionString = sql.dialect.expressionToSQL(expression.prepare(), inputValue: nil) {
				select.append("\(expressionString) AS \(sql.dialect.columnIdentifier(column))")
				groupBy.append("\(expressionString)")
				resultingColumns.append(column)
			}
			else {
				return fallback().aggregate(groups, values: values)
			}
		}
		
		for (column, aggregation) in values {
			if let aggregationSQL = sql.dialect.aggregationToSQL(aggregation) {
				select.append("\(aggregationSQL) AS \(sql.dialect.columnIdentifier(column))")
				resultingColumns.append(column)
			}
			else {
				// Fall back to default implementation for unsupported aggregation functions
				return fallback().aggregate(groups, values: values)
			}
		}
		
		let selectString = select.implode(", ") ?? ""
		if groupBy.count>0, let groupString = groupBy.implode(", ") {
			return apply(sql.sqlGroup(groupString).sqlSelect(selectString), resultingColumns: resultingColumns)
		}
		else {
			// No columns to group by, total aggregates it is
			return apply(sql.sqlSelect(selectString), resultingColumns: resultingColumns)
		}
	}
	
	func apply(fragment: QBESQLFragment, resultingColumns: [QBEColumn]) -> QBEData {
		return QBESQLData(fragment: fragment, columns: columns)
	}
	
	func stream() -> QBEStream {
		fatalError("Stream() must be implemented by subclass of QBESQLData")
	}
}