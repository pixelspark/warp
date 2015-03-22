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

/** Specification of a sort **/
class QBEOrder: NSObject, NSCoding {
	var expression: QBEExpression?
	var ascending: Bool = true
	var numeric: Bool = true
	
	init(expression: QBEExpression, ascending: Bool, numeric: Bool) {
		self.expression = expression
		self.ascending = ascending
		self.numeric = numeric
	}
	
	required init(coder aDecoder: NSCoder) {
		self.expression = (aDecoder.decodeObjectForKey("expression") as? QBEExpression) ?? nil
		self.ascending = aDecoder.decodeBoolForKey("ascending")
		self.numeric = aDecoder.decodeBoolForKey("numeric")
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(expression, forKey: "expression")
		aCoder.encodeBool(ascending, forKey: "ascending")
		aCoder.encodeBool(numeric, forKey: "numeric")
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
	
	/** Skip the specified number of rows in the data set. The number of rows does not include column headers. The number
	 of rows cannot be negative (but can be zero, in which case offset is a no-op).**/
	func offset(numberOfRows: Int) -> QBEData
	
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
	func stream() -> QBEStream
	
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
	
	/** Sort the dataset in the indicates ways. The sorts are applied in-order, e.g. the dataset is sorted by the first
	order specified, in case of ties by the second, et cetera. If there are ties and there is no further order to sort by,
	ordering is unspecified. If no orders are specified, sort is a no-op. **/
	func sort(by: [QBEOrder]) -> QBEData
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
	func stream() -> QBEStream { return data.stream() }
	func raster(job: QBEJob?, callback: (QBERaster) -> ()) { return data.raster(job, callback: callback) }
	func columnNames(callback: ([QBEColumn]) -> ()) { return data.columnNames(callback) }
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData { return data.flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to) }
	func offset(numberOfRows: Int) -> QBEData { return data.offset(numberOfRows) }
	func sort(by: [QBEOrder]) -> QBEData { return data.sort(by) }
}

/** QBECoalescedData is a class that optimizes data operations by combining (coalescing) them. For instance, the operation
data.limit(10).limit(5) can be simplified to data.limit(5). QBECoalescedData is a first optimization step that acts purely
at the highest level of the QBEData interface. Implementation (e.g. QBESQLData) are encouraged to implement further 
optimizations (e.g. coalescing multiple data operations into a single SQL statement).

Technically, QBECoalescedData represents a QBEData coupled with a data operation that is deferred (e.g.
QBECoalescedData.Limiting(data, 10) means it should eventually be equivalent to the result of data.limit(10)). Operations
on QBECoalescedData will either cause the deferred operation to be executed (before the new one is applied) or to combine
the deferred operation with the newly applied operation.**/
enum QBECoalescedData: QBEData {
	case None(QBEData)
	case Limiting(QBEData, Int)
	case Offsetting(QBEData, Int)
	case Transposing(QBEData)
	case Filtering(QBEData, QBEExpression)
	case Sorting(QBEData, [QBEOrder])
	case SelectingColumns(QBEData, [QBEColumn])
	case Distincting(QBEData)
	
	init(_ data: QBEData) {
		self = QBECoalescedData.None(data)
	}
	
	/** Applies the deferred operation represented by this coalesced data object and returns the result. **/
	private var data: QBEData { get {
		switch self {
			case .Limiting(let data, let numberOfRows):
				return data.limit(numberOfRows)
			
			case .Transposing(let data):
				return data.transpose()
			
			case .Offsetting(let data, let nr):
				return data.offset(nr)
			
			case .Filtering(let data, let filter):
				return data.filter(filter)
			
			case .Sorting(let data, let order):
				return data.sort(order)
			
			case .SelectingColumns(let data, let cols):
				return data.selectColumns(cols)
			
			case .Distincting(let data):
				return data.distinct()
			
			case .None(let data):
				return data
		}
	} }
	
	/** data.transpose().transpose() is equivalent to data. **/
	func transpose() -> QBEData {
		switch self {
		case .Transposing(let data):
			return QBECoalescedData.None(data)
			
		default:
			return QBECoalescedData.Transposing(self.data)
		}
	}
	
	func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		/* TODO: calculatings can be combined if the new calculation does not depend on the old one. Also, calculate() 
		can be combined with selectColumns. */
		return QBECoalescedData.None(data.calculate(calculations))
	}
	
	/** data.limit(x).limit(y) is equivalent to data.limit(min(x,y)) **/
	func limit(numberOfRows: Int) -> QBEData {
		switch self {
			case .Limiting(let data, let nr):
				return QBECoalescedData.Limiting(data, min(numberOfRows, nr))
			
			default:
				return QBECoalescedData.Limiting(self.data, numberOfRows)
		}
	}
	
	func random(numberOfRows: Int) -> QBEData {
		return QBECoalescedData.None(data.random(numberOfRows))
	}
	
	/** data.distinct().distinct() is equivalent to data.distinct() (after the first distinct(), there are only distinct
	rows left). **/
	func distinct() -> QBEData {
		switch self {
			case .Distincting(let data):
				return self
			
			default:
				return QBECoalescedData.Distincting(self.data)
		}
	}
	
	/** This function relies on the following axioms:
		- data.filter(a).filter(b) is equivalent to data.filter(QBEFunctionExpression(a,b,QBEFunction.And)) 
		- data.filter(e) is equivalent to an empty data set if e is a constant expression evaluating to false
		- data.filter(e) is equivalent to data if e is a constant expression evaluating to true
	**/
	func filter(condition: QBEExpression) -> QBEData {
		let prepared = condition.prepare()
		if prepared.isConstant {
			let value = prepared.apply([], columns: [], inputValue: nil)
			if value == QBEValue.BoolValue(false) {
				// This will never return any rows
				return QBERasterData()
			}
			else if value == QBEValue.BoolValue(true) {
				// This filter operation will never filter out any rows
				return self
			}
		}
		
		switch self {
			case .Filtering(let data, let oldFilter):
				return QBECoalescedData.Filtering(data, QBEFunctionExpression(arguments: [oldFilter, condition], type: QBEFunction.And))
				
			default:
				return QBECoalescedData.Filtering(self.data, condition)
		}
	}
	
	func unique(expression: QBEExpression, callback: (Set<QBEValue>) -> ()) {
		return data.unique(expression, callback: callback)
	}
	
	/** data.selectColumns(a).selectColumns(b) is equivalent to data.selectColumns(c), where c is b without any columns
	that are not contained in a (selectColumns is specified to ignore any column names that do not exist). **/
	func selectColumns(columns: [QBEColumn]) -> QBEData {
		switch self {
			case .SelectingColumns(let data, let oldColumns):
				let oldSet = Set(oldColumns)
				let newColumns = columns.filter({return oldSet.contains($0)})
				return QBECoalescedData.SelectingColumns(data, newColumns)
			
			default:
				return QBECoalescedData.SelectingColumns(data, columns)
		}
	}
	
	func aggregate(groups: [QBEColumn: QBEExpression], values: [QBEColumn: QBEAggregation]) -> QBEData {
		return QBECoalescedData.None(data.aggregate(groups, values: values))
	}
	
	func pivot(horizontal: [QBEColumn], vertical: [QBEColumn], values: [QBEColumn]) -> QBEData {
		return QBECoalescedData.None(data.pivot(horizontal, vertical: vertical, values: values))
	}
	
	func stream() -> QBEStream {
		return data.stream()
	}
	
	func raster(job: QBEJob?, callback: (QBERaster) -> ()) {
		return data.raster(job, callback: callback)
	}
	
	func columnNames(callback: ([QBEColumn]) -> ()) {
		return data.columnNames(callback)
	}
	
	func flatten(valueTo: QBEColumn, columnNameTo: QBEColumn?, rowIdentifier: QBEExpression?, to: QBEColumn?) -> QBEData {
		return QBECoalescedData.None(data.flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to))
	}
	
	/** data.offset(x).offset(y) is equivalent to data.offset(x+y).**/
	func offset(numberOfRows: Int) -> QBEData {
		assert(numberOfRows > 0)
		
		switch self {
			case .Offsetting(let data, let offset):
				return QBECoalescedData.Offsetting(data, offset + numberOfRows)
			
			default:
				return QBECoalescedData.Offsetting(data, numberOfRows)
		}
	}
	
	/** - data.sort([a,b]).sort([c,d]) is equivalent to data.sort([c,d, a,b]) 
		- data.sort([]) is equivalent to data. **/
	func sort(orders: [QBEOrder]) -> QBEData {
		if orders.count == 0 {
			return self
		}
		
		switch self {
			case .Sorting(let data, let oldOrders):
				return QBECoalescedData.Sorting(data, orders + oldOrders)
			
			default:
				return QBECoalescedData.Sorting(self.data, orders)
		}
	}
}