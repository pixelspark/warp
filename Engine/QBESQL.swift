import Foundation

protocol QBESQLDialect {
	var stringQualifier: String { get }
	var stringQualifierEscape: String { get }
	var identifierQualifier: String { get }
	var identifierQualifierEscape: String { get }
	func columnIdentifier(column: QBEColumn) -> String
	func expressionToSQL(formula: QBEExpression, inputValue: String?) -> String
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

class QBESQLData: NSObject, QBEData {
    internal let sql: String
	let dialect: QBESQLDialect
	var columnNames: [QBEColumn] { get {
		fatalError("Sublcass should implement")
	} }
    
	internal init(sql: String, dialect: QBESQLDialect) {
        self.sql = sql
		self.dialect = dialect
    }
    
    func transpose() -> QBEData {
		return QBERasterData(raster: self.raster()).transpose()
    }
    
    func calculate(targetColumn: QBEColumn, formula: QBEExpression) -> QBEData {
		var values: [String] = []
		var targetFound = false
		for column in columnNames {
			if column == targetColumn {
				targetFound = true
				values.append("\(dialect.expressionToSQL(formula, inputValue: dialect.columnIdentifier(targetColumn))) AS \(dialect.columnIdentifier(column))")
			}
			else {
				values.append(column.name)
			}
		}
		
		// If a new column is calculated, add it near the end
		if !targetFound {
			values.append("\(dialect.expressionToSQL(formula, inputValue: dialect.columnIdentifier(targetColumn))) AS \(dialect.columnIdentifier(targetColumn))")
		}
		
		if let valueString = values.implode(", ") {
			return apply("SELECT \(valueString) FROM (\(sql))")
		}
		return QBERasterData()
    }
    
    func limit(numberOfRows: Int) -> QBEData {
		return apply("SELECT * FROM (\(self.sql)) LIMIT \(numberOfRows)")
    }
	
	func random(numberOfRows: Int) -> QBEData {
		return apply("SELECT * FROM (\(self.sql)) ORDER BY RANDOM() LIMIT \(numberOfRows)")
	}
	
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		let colNames = columns.map({$0.name}).implode(", ") ?? ""
		let sql = "SELECT \(colNames) FROM (\(self.sql))"
		return apply(sql)
	}
    
    var raster: QBEFuture { get {
		fatalError("This should be implemented by a subclass")
    }}
	
	func apply(sql: String) -> QBEData {
		return QBESQLData(sql: sql, dialect: dialect)
	}
	
	func stream(receiver: ([[QBEValue]]) -> ()) {
		// FIXME: batch this, perhaps just send the whole raster at once to receiver() (but do not send column names)
		let r = raster();
		let cols = r.columnNames.map({QBEValue($0.name)})
		receiver([cols])
		for rowNumber in 0..<r.rowCount {
			receiver([r[rowNumber]])
		}
	}
}