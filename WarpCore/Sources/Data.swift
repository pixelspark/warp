import Foundation

public typealias Tuple = [Value]

public struct Row {
	public internal(set) var values: Tuple
	public internal(set) var columnNames: [Column]
	
	public init() {
		self.values = []
		self.columnNames = []
	}
	
	public init(_ values: Tuple, columnNames: [Column]) {
		assert(values.count == columnNames.count, "All values should have column names")
		self.values = values
		self.columnNames = columnNames
	}
	
	public func indexOfColumnWithName(name: Column) -> Int? {
		return columnNames.indexOf(name)
	}
	
	public subscript(column: Column) -> Value? {
		get {
			if let i = columnNames.indexOf(column) {
				return values[i]
			}
			return nil
		}
	}
	
	public mutating func setValue(value: Value, forColumn column: Column) {
		if let i = columnNames.indexOf(column) {
			values[i] = value
		}
		else {
			columnNames.append(column)
			values.append(value)
		}
	}
}

/** Column represents a column (identifier) in a Data dataset. Column names in Data are case-insensitive when
compared, but do retain case. There cannot be two or more columns in a Data dataset that are equal to each other when
compared case-insensitively. */
public struct Column: StringLiteralConvertible, Hashable, CustomDebugStringConvertible {
	public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
	public typealias UnicodeScalarLiteralType = StringLiteralType
	
	public let name: String
	
	public init(_ name: String) {
		self.name = name
	}
	
	public init(stringLiteral value: StringLiteralType) {
		self.name = value
	}
	
	public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
		self.name = value
	}
	
	public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
		self.name = value
	}

	public var hashValue: Int { get {
		return self.name.lowercaseString.hashValue
	} }
	
	public var debugDescription: String { get {
		return "Column(\(name))"
	} }

	/** Returns a new, unique name for the next column given a set of existing columns. */
	public static func defaultNameForNewColumn(existing: [Column]) -> Column {
		var index = existing.count
		while true {
			let newName = Column.defaultNameForIndex(index)
			if !existing.contains(newName) {
				return newName
			}
			index = index + 1
		}
	}

	/** Return Excel-style column name for column at a given index (starting at 0). Note: do not use to generate the name
	of a column that is to be added to an existing set (column names must be unique). Use defaultNameForNewColumn to 
	generate a new, unique name. */
	public static func defaultNameForIndex(index: Int) -> Column {
		var myIndex = index
		let x = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
		var str: String = ""
		
		repeat {
			let i = ((myIndex) % 26)
			str = x[i] + str
			myIndex -= i
			myIndex /= 26
		} while myIndex > 0
		return Column(str)
	}
	
	public func newName(accept: (Column) -> Bool) -> Column {
		var i = 0
		repeat {
			let newName = Column("\(self.name)_\(Column.defaultNameForIndex(i).name)")
			let accepted = accept(newName)
			if accepted {
				return newName
			}
			i++
		} while true
	}
}

/** Column names retain case, but they are compared case-insensitively */
public func == (lhs: Column, rhs: Column) -> Bool {
	return lhs.name.caseInsensitiveCompare(rhs.name) == NSComparisonResult.OrderedSame
}

public func != (lhs: Column, rhs: Column) -> Bool {
	return !(lhs == rhs)
}

/** This helper function can be used to create a lazily-computed variable. */
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

/** Specification of a sort */
public class Order: NSObject, NSCoding {
	public var expression: Expression?
	public var ascending: Bool = true
	public var numeric: Bool = true
	
	public init(expression: Expression, ascending: Bool, numeric: Bool) {
		self.expression = expression
		self.ascending = ascending
		self.numeric = numeric
	}
	
	public required init?(coder aDecoder: NSCoder) {
		self.expression = (aDecoder.decodeObjectForKey("expression") as? Expression) ?? nil
		self.ascending = aDecoder.decodeBoolForKey("ascending")
		self.numeric = aDecoder.decodeBoolForKey("numeric")
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(expression, forKey: "expression")
		aCoder.encodeBool(ascending, forKey: "ascending")
		aCoder.encodeBool(numeric, forKey: "numeric")
	}

	public override func isEqual(object: AnyObject?) -> Bool {
		if let o = object as? Order where o.ascending == self.ascending && o.numeric == self.numeric && o.expression == self.expression {
			return true
		}
		return false
	}
}

/** An aggregator collects values and summarizes them. The map expression generates values (it is called for each item 
and included in the set if it is non-empty). The reduce function receives the mapped items as arguments and reduces them 
to a single value. Note that the reduce function can be called multiple times with different sets (e.g. 
reduce(reduce(a,b), reduce(c,d)) should be equal to reduce(a,b,c,d).  */
public struct Aggregator {
	public var map: Expression
	public var reduce: Function
}

/** Specification of an aggregation, which is an aggregator that generates a particular target column. */
public class Aggregation: NSObject, NSCoding {
	public var aggregator: Aggregator
	public var targetColumnName: Column
	
	public init(map: Expression, reduce: Function, targetColumnName: Column) {
		self.aggregator = Aggregator(map: map, reduce: reduce)
		self.targetColumnName = targetColumnName
	}
	
	required public init?(coder: NSCoder) {
		targetColumnName = Column((coder.decodeObjectForKey("targetColumnName") as? String) ?? "")
		let map = (coder.decodeObjectForKey("map") as? Expression) ?? Identity()
		let reduce: Function
		if let rawReduce = coder.decodeObjectForKey("reduce") as? String {
			reduce = Function(rawValue: rawReduce) ?? Function.Identity
		}
		else {
			reduce = Function.Identity
		}
		self.aggregator = Aggregator(map: map, reduce: reduce)
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(targetColumnName.name, forKey: "targetColumnName")
		aCoder.encodeObject(aggregator.map, forKey: "map")
		aCoder.encodeObject(aggregator.reduce.rawValue, forKey: "reduce")
	}
}

public enum JoinType: String {
	/** In a left join, rows of the 'left'  table match with a row in the 'right' table if the join condition returns
	true. The result set will contain all columns from the left table, and all columns in the right table that do not
	appear in the left table. The following rules determine which rows appear in the result set:
	
	- If a row in the left table has no matching rows in the right table, it will appear in the result set once, with 
	  empty values in those columns only present in the right table;
	- If a row in the left table has exactly one matching row in the right table, it will appear in the result set once,
	  and the values of the matching right row will appear in those columns that are only present in the right table;
	- If a row in the left table matches with more than one row in the right table, the left row is repeated for each
	  match in the result table; for each repeated row, the columns only present in the right table are filled with the
	  data from the matching right row. */
	case LeftJoin = "left"
	
	/** The inner join is similar to the left join, except that when a row in the left table has no matches in the right
	 table, it will be omitted in the result set. This type of join will not add any NULLs to the result set in any case. */
	case InnerJoin = "inner"
}

/** Join represents a join of an unknown data set with a known, foreign data set based on a row matching expression. 
The expression should reference both columns from the source table (sibling references) as well as columns in the foreign
database (foreign references). */
public struct Join {
	public let type: JoinType
	public let foreignData: Data
	public let expression: Expression
	
	public init(type: JoinType, foreignData: Data, expression: Expression) {
		self.type = type
		self.foreignData = foreignData
		self.expression = expression
	}
}

/** HashComparison represents a comparison between rows in two tables, in which the expression on either side of the 
comparison can be used as a hash. This can be used to implement hash joins (the result of the expression for the left
side can be calculated and used as an index into a hash tables of results for rows on the right side). 

Note that neither the left nor the right expression is allowed to contain foreign references; sibling references refer to
columns in the left resp. right side data set. */
internal struct HashComparison {
	let leftExpression: Expression
	let rightExpression: Expression
	let comparisonOperator: Binary
	
	init(leftExpression: Expression, rightExpression: Expression, comparisonOperator: Binary) {
		assert(!leftExpression.dependsOnForeigns, "left side of a HashComparison should not depend on foreign columns")
		assert(!rightExpression.dependsOnForeigns, "right side of a HashComparison should not depend on foreign columns")
		self.leftExpression = leftExpression
		self.rightExpression = rightExpression
		self.comparisonOperator = comparisonOperator
	}
	
	/** Attempts to transform the given expression to a hash comparison by factoring the given expression into a comparison
	 between two expressions where one exclusively depends on the source table (ony sibling references) and the other 
	exclusively depends on the foreign table (only foreign references). */
	init?(expression: Expression) {
		if expression.dependsOnForeigns && expression.dependsOnSiblings {
			/* If this expression is a binary expression where one side depends only on siblings and the other side only 
			depends on foreigns, then we can transform this into a hash comparison. */
			if let binary = expression as? Comparison {
				self.comparisonOperator = binary.type
				if !binary.first.dependsOnSiblings && binary.second.dependsOnSiblings {
					self.leftExpression = binary.second
					self.rightExpression = binary.first.expressionForForeignFiltering()!
				}
				else if binary.first.dependsOnSiblings && !binary.second.dependsOnSiblings {
					self.leftExpression = binary.first
					self.rightExpression = binary.second.expressionForForeignFiltering()!
				}
				else {
					return nil
				}
			}
			else {
				// TODO: this can be made more smart; e.g. AND(a=Fa; b=Fb) can become (a,b)=(Fa,Fb)
				// Also, we should support ORs and INs by returning multiple hash comparisons.
				return nil
			}
		}
		else {
			// This expression just uses data from one side; it cannot be represented as a hash comparison
			return nil
		}
	}
}

/** Data represents a data set. A data set consists of a set of column names (Column) and rows that each have a
value for all columns in the data set. Values are represented as Value. Data supports various data manipulation
operations. The exact semantics of the operations are described here, but Data does not implement the operations. 
Internally, Data may be represented as a two-dimensional array of Value, which may or may not include the column
names ('column header row'). Data manipulations do not operate on the column header row unless explicitly stated otherwise. */
public protocol Data {
	/** Transpose the data set, e.g. columns become rows and vice versa. In the full raster (including column names), a
	cell at [x][y] will end up at position [y][x]. */
	func transpose() -> Data
	
	/** For each row, compute the given expressions and put the result in the desired columns. If that column does not
	yet exist in the data set, it is created and appended as last column. The order of existing columns remains intact.
	If the column already exists, the column's values are overwritten by the results of the calculation. Note that in this
	case the old value in the column is an input value to the formula (this value is Value.EmptyValue in the case where
	the target column doesn't exist yet). Calculations do not apply to the column headers. 
	
	The specified calculations are executed in no particular order. Expressions that read data from the row (e.g. from
	another column) are read from the previous version of the row as if none of the specified calculations have 
	happened. */
	func calculate(calculations: Dictionary<Column, Expression>) -> Data
	
	/** Limit the number of rows in the data set to the specified number of rows. The number of rows does not include
	column headers. */
	func limit(numberOfRows: Int) -> Data
	
	/** Skip the specified number of rows in the data set. The number of rows does not include column headers. The number
	of rows cannot be negative (but can be zero, in which case offset is a no-op). */
	func offset(numberOfRows: Int) -> Data
	
	/** Randomly select the indicated amount of rows from the source data set, using sampling without replacement. If the
	number of rows specified is greater than the number of rows available in the set, the resulting data set will contain
	all rows of the original data set. */
	func random(numberOfRows: Int) -> Data
	
	/** Returns a dataset with only unique rows from the data set. */
	func distinct() -> Data
	
	/** Selects only those rows from the data set for which the supplied expression evaluates to a value that equals
	Value.BoolValue(true). */
	func filter(condition: Expression) -> Data
	
	/** Returns a set of all unique result values in this data set for the given expression. */
	func unique(expression: Expression, job: Job, callback: (Fallible<Set<Value>>) -> ())
	
	/** Select only the columns from the data set that are in the array, in the order specified. If a column named in the
	array does not exist, it is ignored. */
	func selectColumns(columns: [Column]) -> Data
	
	/** Aggregate data in this set. The 'groups' parameter defines different aggregation 'buckets'. Items are mapped in
	into each bucket. Subsequently, the aggregations specified in the 'values' parameter are run on each bucket 
	separately. The resulting data set starts with the group identifier columns, followed by the aggregation results. */
	func aggregate(groups: [Column: Expression], values: [Column: Aggregator]) -> Data
	
	func pivot(horizontal: [Column], vertical: [Column], values: [Column]) -> Data
	
	/** Request streaming of the data contained in this dataset to the specified callback. */
	func stream() -> Stream
	
	/** Flattens a data set. For each cell in the source data set, a row is generated that contains the following columns
	(in the following order):
	- A column containing the original column's name (if columnNameTo is non-nil)
	- A column containing the result of applying the rowIdentifier expression on the original row (if rowIdentifier is
	  non-nil AND the to parameter is non-nil)
	- The original cell value */
	func flatten(valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) -> Data
	
	/** Returns an in-memory representation (Raster) of the data set. */
	func raster(job: Job, callback: (Fallible<Raster>) -> ())
	
	/** Returns the names of the columns in the data set. The list of column names is ordered. */
	func columnNames(job: Job, callback: (Fallible<[Column]>) -> ())
	
	/** Sort the dataset in the indicates ways. The sorts are applied in-order, e.g. the dataset is sorted by the first
	order specified, in case of ties by the second, et cetera. If there are ties and there is no further order to sort by,
	ordering is unspecified. If no orders are specified, sort is a no-op. */
	func sort(by: [Order]) -> Data
	
	/** Perform the specified join operation on this data set and return the resulting data. */
	func join(join: Join) -> Data
	
	/**	Combine all rows from the first data set with all rows from the second data set in no particular order. Duplicate
	rows are retained (i.e. this works like SQL's UNION ALL, not UNION). The resulting data set contains the union of
	columns from both data sets (no duplicates). Rows have empty values inserted for values of columns not present in
	the source data set. */
	func union(data: Data) -> Data
}

/** Utility class that allows for easy swapping of Data objects. This can for instance be used to swap-in a cached
version of a particular data object. */
public class ProxyData: NSObject, Data {
	public var data: Data
	
	public init(data: Data) {
		self.data = data
	}
	
	public func transpose() -> Data { return data.transpose() }
	public func calculate(calculations: Dictionary<Column, Expression>) -> Data { return data.calculate(calculations) }
	public func limit(numberOfRows: Int) -> Data { return data.limit(numberOfRows) }
	public func random(numberOfRows: Int) -> Data { return data.random(numberOfRows) }
	public func distinct() -> Data { return data.distinct() }
	public func filter(condition: Expression) -> Data { return data.filter(condition) }
	public func unique(expression: Expression,  job: Job, callback: (Fallible<Set<Value>>) -> ()) { return data.unique(expression, job: job, callback: callback) }
	public func selectColumns(columns: [Column]) -> Data { return data.selectColumns(columns) }
	public func aggregate(groups: [Column: Expression], values: [Column: Aggregator]) -> Data { return data.aggregate(groups, values: values) }
	public func pivot(horizontal: [Column], vertical: [Column], values: [Column]) -> Data { return data.pivot(horizontal, vertical: vertical, values: values) }
	public func stream() -> Stream { return data.stream() }
	public func raster(job: Job, callback: (Fallible<Raster>) -> ()) { return data.raster(job, callback: callback) }
	public func columnNames(job: Job, callback: (Fallible<[Column]>) -> ()) { return data.columnNames(job, callback: callback) }
	public func flatten(valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) -> Data { return data.flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to) }
	public func offset(numberOfRows: Int) -> Data { return data.offset(numberOfRows) }
	public func sort(by: [Order]) -> Data { return data.sort(by) }
	public func join(join: Join) -> Data { return data.join(join) }
	public func union(data: Data) -> Data { return data.union(data) }
}

public extension Data {
	var coalesced: Data { get {
		return CoalescedData(self)
	} }
}

/** CoalescedData is a class that optimizes data operations by combining (coalescing) them. For instance, the operation
data.limit(10).limit(5) can be simplified to data.limit(5). CoalescedData is a first optimization step that acts purely
at the highest level of the Data interface. Implementation (e.g. SQLData) are encouraged to implement further 
optimizations (e.g. coalescing multiple data operations into a single SQL statement).

Technically, CoalescedData represents a Data coupled with a data operation that is deferred (e.g.
CoalescedData.Limiting(data, 10) means it should eventually be equivalent to the result of data.limit(10)). Operations
on CoalescedData will either cause the deferred operation to be executed (before the new one is applied) or to combine
the deferred operation with the newly applied operation. */
enum CoalescedData: Data {
	case None(Data)
	case Limiting(Data, Int)
	case Offsetting(Data, Int)
	case Transposing(Data)
	case Filtering(Data, Expression)
	case Sorting(Data, [Order])
	case SelectingColumns(Data, [Column])
	case Calculating(Data, [Column: Expression])
	case CalculatingThenSelectingColumns(Data, OrderedDictionary<Column, Expression>)
	case Distincting(Data)
	
	init(_ data: Data) {
		self = CoalescedData.None(data)
	}
	
	/** Applies the deferred operation represented by this coalesced data object and returns the result. */
	var data: Data { get {
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
			
			case .Calculating(let data, let calculations):
				return data.calculate(calculations)
			
			case .CalculatingThenSelectingColumns(let data, let calculations):
				return data.calculate(calculations.values).selectColumns(calculations.keys)
			
			case .None(let data):
				return data
		}
	} }
	
	/** data.transpose().transpose() is equivalent to data. */
	func transpose() -> Data {
		switch self {
		case .Transposing(let data):
			return CoalescedData.None(data)
			
		default:
			return CoalescedData.Transposing(self.data)
		}
	}

	/** No optimzations are currently done on joins. */
	func join(join: Join) -> Data {
		return CoalescedData.None(data.join(join))
	}
	
	/** Combine calculations under the following circumstances:
	- calculate(A: x).calculate(B: y) is equivalent to calculate(A: x, B: y) if y does not depend on A and A!=B
	- calculate(A: x).calculate(A: y) is equivalent to calculate(A: y) if x is an identity expression (e.g. just returns
	  the content A had before the calculation) */
	func calculate(calculations: Dictionary<Column, Expression>) -> Data {
		var newCalculations = OrderedDictionary<Column, Expression>()
		
		let source: Data
		let keepOrder: Bool
		switch self {
			case .Calculating(let data, let calculations):
				newCalculations = OrderedDictionary(dictionaryInAnyOrder: calculations)
				source = data
				keepOrder = false
			
			case .CalculatingThenSelectingColumns(let data, let calculations):
				newCalculations = calculations
				source = data
				keepOrder = true
			
			default:
				source = self.data
				keepOrder = false
				break
		}
		
		/* Calculations that do not depend on any columns already being calculated in this batch can be combined with the
		current batch. The rest will be put in a new step (note that ordering *between* calculations sent to the calculate
		function is undefined). */
		var deferred = Dictionary<Column, Expression>()
		for (targetColumn, expression) in calculations {
			// Find out if the new calculation depends on anything that was calculated earlier
			var dependsOnCurrent = false
			
			if let se = newCalculations[targetColumn] as? Sibling where se.columnName == targetColumn {
				// The old calculation is just an identity one, it can safely be overwritten
			}
			else if newCalculations[targetColumn] is Identity {
				// The old calculation is just an identity one, it can safely be overwritten
			}
			else {
				// Iterate over all column dependencies of the new expression
				expression.visit({ (subexpression) -> () in
					if let se = subexpression as? Sibling {
						if newCalculations[se.columnName] != nil {
							dependsOnCurrent = true
						}
					}
				})
			}

			if dependsOnCurrent {
				deferred[targetColumn] = expression
			}
			else {
				newCalculations[targetColumn] = expression
			}
		}
		
		let result: CoalescedData
		if keepOrder {
			result = CoalescedData.CalculatingThenSelectingColumns(source, newCalculations)
		}
		else {
			result = CoalescedData.Calculating(source, newCalculations.values)
		}
		
		// If we have deferred some of the calculations to a second call to calculate, append it here
		if deferred.count > 0 {
			return CoalescedData.Calculating(result.data, deferred)
		}
		
		return result
	}
	
	/** Axioms for limit:
	data.limit(x).limit(y) is equivalent to data.limit(min(x,y))
	data.calculate(...).limit(x) is equivalent to data.limit(x).calculate(...) */
	func limit(numberOfRows: Int) -> Data {
		switch self {
			case .Calculating(let data, let calculations):
				return CoalescedData.Calculating(CoalescedData.Limiting(data, numberOfRows), calculations)

			case .Limiting(let data, let nr):
				return CoalescedData.Limiting(data, min(numberOfRows, nr))
			
			default:
				return CoalescedData.Limiting(self.data, numberOfRows)
		}
	}
	
	func random(numberOfRows: Int) -> Data {
		return CoalescedData.None(data.random(numberOfRows))
	}
	
	/** data.distinct().distinct() is equivalent to data.distinct() (after the first distinct(), there are only distinct
	rows left). */
	func distinct() -> Data {
		switch self {
			case .Distincting(_):
				return self
			
			default:
				return CoalescedData.Distincting(self.data)
		}
	}
	
	/** This function relies on the following axioms:
		- data.filter(a).filter(b) is equivalent to data.filter(Call(a,b,Function.And))
		- data.filter(e) is equivalent to data if e is a constant expression evaluating to true 
		- data.filter(e).calculate(...) is equivalent to data.calculate(...).filter(e) if the filter does not rely on 
		  the outcome of the calculate operation
	*/
	func filter(condition: Expression) -> Data {
		let prepared = condition.prepare()
		if prepared.isConstant {
			let value = prepared.apply(Row(), foreign: nil, inputValue: nil)
			if value == Value.BoolValue(true) {
				// This filter operation will never filter out any rows
				return self
			}
		}
		
		switch self {
		case .Sorting(let data, let order):
			/** Filtering is transparent to ordering, and so should be ordered before it, so it is 'closer to the index'. */
			return CoalescedData.Sorting(CoalescedData.Filtering(data, condition), order)

		case .Calculating(let data, let calculations):
			/** If the filter does not depend on the outcome of the calculations, then it can be ordered before the 
			calculations. This is usually more efficient, because the less steps away from the source data, the higher
			the chance that there is a usable index. */
			let deps = prepared.siblingDependencies
			if deps.isDisjointWith(calculations.keys) {
				return CoalescedData.Calculating(CoalescedData.Filtering(data, condition), calculations)
			}
			else {
				return CoalescedData.Filtering(self.data, condition)
			}

		case .Filtering(let data, let oldFilter):
			return CoalescedData.Filtering(data, Call(arguments: [oldFilter, condition], type: Function.And))

		default:
			return CoalescedData.Filtering(self.data, condition)
		}
	}

	func unique(expression: Expression, job: Job, callback: (Fallible<Set<Value>>) -> ()) {
		return data.unique(expression, job: job, callback: callback)
	}
	
	/**  The following optimizations are performed on selectColumns:
		- data.selectColumns(a).selectColumns(b) is equivalent to data.selectColumns(c), where c is b without any columns
		  that are not contained in a (selectColumns is specified to ignore any column names that do not exist).
		- data.selectColumns(a) is equivalent to an empty data set if a is empty
		- data.calculate().selectColumns() can be combined: calculations that result into columns that are not selected 
		  are not included */
	func selectColumns(columns: [Column]) -> Data {
		if columns.isEmpty {
			return RasterData()
		}
		
		switch self {
			case .SelectingColumns(let data, let oldColumns):
				let oldSet = Set(oldColumns)
				let newColumns = columns.filter({return oldSet.contains($0)})
				return CoalescedData.SelectingColumns(data, newColumns)
			
			case .Calculating(let data, let calculations):
				var newCalculations = OrderedDictionary<Column, Expression>()
				for column in columns {
					if let expression = calculations[column] {
						newCalculations.append(expression, forKey: column)
					}
					else {
						newCalculations.append(Identity(), forKey: column)
					}
				}
				return CoalescedData.CalculatingThenSelectingColumns(data, newCalculations)
			
			case .CalculatingThenSelectingColumns(let data, let calculations):
				var newCalculations = calculations
				newCalculations.filterAndOrder(columns)
				return CoalescedData.CalculatingThenSelectingColumns(data, newCalculations)
			
			default:
				return CoalescedData.SelectingColumns(data, columns)
		}
	}
	
	func aggregate(groups: [Column: Expression], values: [Column: Aggregator]) -> Data {
		return CoalescedData.None(data.aggregate(groups, values: values))
	}
	
	func pivot(horizontal: [Column], vertical: [Column], values: [Column]) -> Data {
		return CoalescedData.None(data.pivot(horizontal, vertical: vertical, values: values))
	}
	
	func stream() -> Stream {
		return data.stream()
	}
	
	func raster(job: Job, callback: (Fallible<Raster>) -> ()) {
		return data.raster(job, callback: callback)
	}
	
	func columnNames(job: Job, callback: (Fallible<[Column]>) -> ()) {
		return data.columnNames(job, callback: callback)
	}
	
	func flatten(valueTo: Column, columnNameTo: Column?, rowIdentifier: Expression?, to: Column?) -> Data {
		return CoalescedData.None(data.flatten(valueTo, columnNameTo: columnNameTo, rowIdentifier: rowIdentifier, to: to))
	}
	
	func union(data: Data) -> Data {
		return CoalescedData.None(self.data.union(data))
	}
	
	/** Axioms for offset:
	- data.offset(x).offset(y) is equivalent to data.offset(x+y).
	- data.calculate(...).offset(x) is equivalent to data.offset(x).calculate(...)
	*/
	func offset(numberOfRows: Int) -> Data {
		assert(numberOfRows > 0)
		
		switch self {
		case .Calculating(let data, let calculations):
			return CoalescedData.Calculating(CoalescedData.Offsetting(data, numberOfRows),calculations)

		case .Offsetting(let data, let offset):
			return CoalescedData.Offsetting(data, offset + numberOfRows)

		default:
			return CoalescedData.Offsetting(data, numberOfRows)
		}
	}
	
	/** - data.sort([a,b]).sort([c,d]) is equivalent to data.sort([c,d, a,b]) 
		- data.sort([]) is equivalent to data. */
	func sort(orders: [Order]) -> Data {
		if orders.isEmpty {
			return self
		}
		
		switch self {
			case .Sorting(let data, let oldOrders):
				return CoalescedData.Sorting(data, orders + oldOrders)
			
			default:
				return CoalescedData.Sorting(self.data, orders)
		}
	}
}