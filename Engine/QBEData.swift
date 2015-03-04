import Foundation

typealias QBERow = [QBEValue]

/** QBEColumn represents a column (identifier) in a QBEData dataset. Column names in QBEData are case-insensitive when
compared, but do retain case. There cannot be two or more columns in a QBEData dataset that are equal to each other when
compared case-insensitively. **/
struct QBEColumn: StringLiteralConvertible, Hashable, DebugPrintable {
	typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
	typealias UnicodeScalarLiteralType = StringLiteralType
	
	let name: String
	
	init(_ name: String) {
		self.name = name
	}
	
	init(stringLiteral value: StringLiteralType) {
		self.name = value
	}
	
	init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
		self.name = value
	}
	
	init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
		self.name = value
	}
	
	var hashValue: Int { get {
		return self.name.lowercaseString.hashValue
	} }
	
	var debugDescription: String { get {
		return "QBEColumn(\(name))"
	} }
	
	/** Return Excel-style column name for column at a given index (starting at 0). **/
	static func defaultColumnForIndex(var index: Int) -> QBEColumn {
		let x = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
		var str: String = ""
		
		do {
			let i = ((index) % 26)
			str = x[i] + str
			index -= i
			index /= 26
		} while index > 0
		return QBEColumn(str)
	}
}

/** Column names retain case, but they are compared case-insensitively **/
func == (lhs: QBEColumn, rhs: QBEColumn) -> Bool {
	return lhs.name.caseInsensitiveCompare(rhs.name) == NSComparisonResult.OrderedSame
}

func != (lhs: QBEColumn, rhs: QBEColumn) -> Bool {
	return !(lhs == rhs)
}

/** This helper function can be used to create a lazily-computed variable. **/
func memoize<T>(result: () -> T) -> () -> T {
	var cached: T? = nil
	
	return {() in
		if let v = cached {
			return v
		}
		else {
			cached = result()
			return cached!
		}
	}
}

/** Specification of an aggregation. The map expression generates values (it is called for each item and included in the
set if it is non-empty). The reduce function receives the mapped items as arguments and reduces them to a single value.
Note that the reduce function can be called multiple times with different sets (e.g. reduce(reduce(a,b), reduce(c,d)) 
should be equal to reduce(a,b,c,d). **/
class QBEAggregation: NSObject, NSCoding {
	var map: QBEExpression
	var reduce: QBEFunction
	var targetColumnName: QBEColumn
	
	init(map: QBEExpression, reduce: QBEFunction, targetColumnName: QBEColumn) {
		self.map = map
		self.reduce = reduce
		self.targetColumnName = targetColumnName
	}
	
	required init(coder: NSCoder) {
		targetColumnName = QBEColumn((coder.decodeObjectForKey("targetColumnName") as? String) ?? "")
		map = (coder.decodeObjectForKey("map") as? QBEExpression) ?? QBEIdentityExpression()
		if let rawReduce = coder.decodeObjectForKey("reduce") as? String {
			reduce = QBEFunction(rawValue: rawReduce) ?? QBEFunction.Identity
		}
		else {
			reduce = QBEFunction.Identity
		}
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(targetColumnName.name, forKey: "targetColumnName")
		aCoder.encodeObject(map, forKey: "map")
		aCoder.encodeObject(reduce.rawValue, forKey: "reduce")
	}
}

/** QBEData represents a data set. A data set consists of a set of column names (QBEColumn) and rows that each have a 
value for all columns in the data set. Values are represented as QBEValue. QBEData supports various data manipulation
operations. The exact semantics of the operations are described here, but QBEData does not implement the operations. 
Internally, QBEData may be represented as a two-dimensional array of QBEValue, which may or may not include the column
names ('column header row'). Data manipulations do not operate on the column header row unless explicitly stated otherwise.
**/
protocol QBEData {
	/** Transpose the data set, e.g. columns become rows and vice versa. In the full raster (including column names), a
	cell at [x][y] will end up at position [y][x]. **/
	func transpose() -> QBEData
	
	/** For each row, compute the given expressions and put the result in the desired columns. If that column does not 
	yet exist in the data set, it is created and appended as last column. The order of existing columns remains intact.
	If the column already exists, the column's values are overwritten by the results of the calculation. Note that in this
	case the old value in the column is an input value to the formula (this value is QBEValue.EmptyValue in the case where
	the target column doesn't exist yet). Calculations do not apply to the column headers. The specified calculations are
	executed in no particular order. **/
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData
	
	/** Limit the number of rows in the data set to the specified number of rows. The number of rows does not include
	column headers. **/
	func limit(numberOfRows: Int) -> QBEData
	
	/** Randomly select the indicated amount of rows from the source data set, using sampling without replacement. If the
	number of rows specified is greater than the number of rows available in the set, the resulting data set will contain
	all rows of the original data set. **/
	func random(numberOfRows: Int) -> QBEData
	
	/** Returns a dataset with only unique rows from the data set. **/
	func distinct() -> QBEData
	
	/** Selects only those rows from the data set for which the supplied expression evaluates to a value that equals
	QBEValue.BoolValue(true). **/
	func filter(condition: QBEExpression) -> QBEData
	
	/** Returns a data set in which there is not more than one row with the same result for the given expression. **/
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ())
	
	/* Select only the columns from the data set that are in the array, in the order specified. If a column named in the 
	array does not exist, it is ignored. */
	func selectColumns(columns: [QBEColumn]) -> QBEData
	
	/** Aggregate data in this set. The 'groups' parameter defines different aggregation 'buckets'. Items are mapped in
	into each bucket. Subsequently, the aggregations specified in the 'values' parameter are run on each bucket 
	separately. The resulting data set starts with the group identifier columns, followed by the aggregation results. **/
	func aggregate(groups: [QBEColumn: QBEExpression], values: [QBEColumn: QBEAggregation]) -> QBEData
	
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData
	
	/** Request streaming of the data contained in this dataset to the specified callback. **/
	func stream() -> QBEStream?
	
	/** Flattens a data set. For each cell in the source data set, a row is generated that contains the following columns
	(in the following order):
	- A column containing the original column's name (if columnNameTo is non-nil)
	- A column containing the result of applying the rowIdentifier expression on the original row (if rowIdentifier is 
	  non-nil AND the to parameter is non-nil)
	- The original cell value **/
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData
	
	/** An in-memory representation (QBERaster) of the data set. **/
	func raster(job: QBEJob?, callback: (QBERaster) -> ())
	
	/** Returns the names of the columns in the data set. The list of column names is ordered. **/
	func columnNames(callback: ([QBEColumn]) -> ())
}

/** Utility class that allows for easy swapping of QBEData objects. This can for instance be used to swap-in a cached
version of a particular data object. **/
class QBEProxyData: NSObject, QBEData {
	var data: QBEData
	
	init(data: QBEData) {
		self.data = data
	}
	
	func transpose() -> QBEData { return data.transpose() }
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData { return data.calculate(calculations) }
	func limit(numberOfRows: Int) -> QBEData { return data.limit(numberOfRows) }
	func random(numberOfRows: Int) -> QBEData { return data.random(numberOfRows) }
	func distinct() -> QBEData { return data.distinct() }
	func filter(condition: QBEExpression) -> QBEData { return data.filter(condition) }
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) { return data.unique(expression, callback: callback) }
	func selectColumns(columns: [QBEColumn]) -> QBEData { return data.selectColumns(columns) }
	func aggregate(groups: [QBEColumn: QBEExpression], values: [QBEColumn: QBEAggregation]) -> QBEData { return data.aggregate(groups, values: values) }
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData { return data.pivot(horizontal, vertical: vertical, values: values) }
	func stream() -> QBEStream? { return data.stream() }
	func raster(job: QBEJob?, callback: (QBERaster) -> ()) { return data.raster(job, callback: callback) }
	func columnNames(callback: ([QBEColumn]) -> ()) { return data.columnNames(callback) }
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData { return data.flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to) }
}