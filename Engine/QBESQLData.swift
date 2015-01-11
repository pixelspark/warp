import Foundation

struct QBESQLDialect {
	let stringQualifier = "\""
	let stringQualifierEscape = "\\\""
	
	func columnIdentifier(columnName: String) -> String {
		return columnName
	}
	
	func expressionToSQL(formula: QBEExpression) -> String {
		if let f = formula as? QBELiteralExpression {
			return valueToSQL(f.value)
		}
		else if let f = formula as? QBESiblingExpression {
			return columnIdentifier(f.columnName.name)
		}
		else if let f = formula as? QBEBinaryExpression {
			return binaryToSQL(expressionToSQL(f.first), second: expressionToSQL(f.second), type: f.type)
		}
		else if let f = formula as? QBEFunctionExpression {
			let argValues = f.arguments.map({(a) -> String in return self.expressionToSQL(a)})
			return unaryToSQL(argValues, type: f.type)
		}

		return "??"
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
		}
	}
	
	private func valueToSQL(value: QBEValue) -> String {
		return "\(stringQualifier)\(value.stringValue.stringByReplacingOccurrencesOfString(stringQualifier, withString: stringQualifierEscape))\(stringQualifier)"
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
    private let sql: String
	let columnNames: [QBEColumn]
	let dialect: QBESQLDialect = QBESQLDialect()
    
	init(sql: String, columnNames: [QBEColumn]) {
        self.sql = sql
		self.columnNames = columnNames
    }
    
    func transpose() -> QBEData {
		return QBESQLData(sql: "TRANSPOSE(\(self.sql))", columnNames: self.columnNames)
    }
    
    func calculate(targetColumn: QBEColumn, formula: QBEExpression) -> QBEData {
		var values: [String] = []
		for column in columnNames {
			if column == targetColumn {
				values.append("\(dialect.expressionToSQL(formula)) AS \(column.name)")
			}
			else {
				values.append(column.name)
			}
		}
		
		if let valueString = values.implode(", ") {
			return QBESQLData(sql: "SELECT \(valueString) FROM \(sql)", columnNames: self.columnNames)
		}
		return QBERasterData()
    }
    
    func limit(numberOfRows: Int) -> QBEData {
        return QBESQLData(sql: "SELECT * FROM \(self.sql) LIMIT \(numberOfRows)", columnNames: self.columnNames)
    }
    
    func replace(value: QBEValue, withValue: QBEValue, inColumn: QBEColumn) -> QBEData {
        return QBESQLData(sql: "SELECT REPLACE(\(value), \(withValue), \(inColumn.name)) AS \(inColumn.name) FROM (\(sql))", columnNames: self.columnNames)
    }
    
    var raster: QBEFuture { get {
		println("SQL raster query=\(sql)")
		
        return {() -> QBERaster in
            let d: [[QBEValue]] = [[QBEValue("SQL")], [QBEValue(self.sql)]]
            return QBERaster(d)
        }
    }}
	
	func stream(receiver: ([[QBEValue]]) -> ()) {
		// FIXME: batch this, perhaps just send the whole raster at once to receiver() (but do not send column names)
		let r = raster();
		for rowNumber in 0..<r.rowCount {
			receiver([r[rowNumber]])
		}
	}
}