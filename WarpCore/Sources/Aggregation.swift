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

/** A Reducer is a function that takes multiple arguments, but can receive them in batches in order to calculate the
result, and does not have to store all values. The 'average'  function for instance can maintain a sum of values received
as well as a count, and determine the result at any point by dividing the sum by the count. */
// TODO: implement hierarchical reducers (e.g. so that two SumReducers can be summed, and the reduction can be done in parallel)
public protocol Reducer {
	mutating func add(_ values: [Value])
	var result: Value { get }
}

/** An aggregator collects values and summarizes them. The map expression generates values (it is called for each item
and included in the set if it is non-empty). The reduce function receives the mapped items as arguments and reduces them
to a single value. Note that the reduce function can be called multiple times with different sets (e.g.
reduce(reduce(a,b), reduce(c,d)) should be equal to reduce(a,b,c,d).  */
public struct Aggregator {
	public var map: Expression
	public var reduce: Function
	public var minimumCount: Int? = nil

	public init(map: Expression, reduce: Function) {
		self.map = map
		self.reduce = reduce
	}

	public var reducer: Reducer? {
		let r = self.reduce.reducer
		if let mn = self.minimumCount, let r = r {
			return MinimumCellReducer(r, minimum: mn)
		}
		return r
	}
}

/** Specification of an aggregation, which is an aggregator that generates a particular target column. */
public class Aggregation: NSObject, NSCoding {
	public var aggregator: Aggregator
	public var targetColumn: Column

	public init(aggregator: Aggregator, targetColumn: Column) {
		self.aggregator = aggregator
		self.targetColumn = targetColumn
	}

	public init(map: Expression, reduce: Function, targetColumn: Column) {
		self.aggregator = Aggregator(map: map, reduce: reduce)
		self.targetColumn = targetColumn
	}

	required public init?(coder: NSCoder) {
		targetColumn = Column((coder.decodeObject(forKey: "targetColumnName") as? String) ?? "")
		let map = (coder.decodeObject(forKey: "map") as? Expression) ?? Identity()
		let reduce: Function
		if let rawReduce = coder.decodeObject(forKey: "reduce") as? String {
			reduce = Function(rawValue: rawReduce) ?? Function.identity
		}
		else {
			reduce = Function.identity
		}

		self.aggregator = Aggregator(map: map, reduce: reduce)

		if coder.containsValue(forKey: "minimumCount") {
			self.aggregator.minimumCount = coder.decodeInteger(forKey: "minimumCount")
		}
	}

	public func encode(with aCoder: NSCoder) {
		aCoder.encode(targetColumn.name, forKey: "targetColumnName")
		aCoder.encode(aggregator.map, forKey: "map")
		aCoder.encode(aggregator.reduce.rawValue, forKey: "reduce")

		if let mv = aggregator.minimumCount {
			aCoder.encode(mv, forKey: "minimumCount")
		}
	}
}

/** A reducer that guarantees that an aggregate result is based on at least a certain amount of values. Useful for
guaranteeing minimum cell size in statistics. When at least `minimum` valid, non-empty values were fed to the reducer,
the original reducer's result will be returned (any invalid/empty values will have been fed to it). If not, an empty
value will be returned. */
private struct MinimumCellReducer: Reducer {
	private let minimum: Int
	private var reducer: Reducer
	private var count: Int

	public init(_ reducer: Reducer, minimum: Int) {
		self.reducer = reducer
		self.minimum = minimum
		self.count = 0
	}

	public mutating func add(_ values: [Value]) {
		self.count += values.reduce(0, { (r, v) -> Int in
			if v.isValid && !v.isEmpty {
				return r + 1
			}
			return r
		})
		self.reducer.add(values)
	}

	public var result: Value {
		if self.count >= self.minimum {
			return self.reducer.result
		}
		return Value.empty
	}
}
