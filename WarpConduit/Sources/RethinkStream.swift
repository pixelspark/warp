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
import Rethink
import WarpCore

fileprivate extension Value {
	var rethinkValue: ReQueryValue {
		switch self {
		case .string(let s): return R.expr(s)
		case .bool(let b): return R.expr(b)
		case .double(let d): return R.expr(d)
		case .date(let d): return R.expr(d) // FIXME!
		case .int(let i): return R.expr(i)
		case .invalid: return R.expr(1).div(0)
		case .empty: return R.expr()
		}
	}
}

final public class RethinkStream: NSObject, WarpCore.Stream {
	let url: URL
	let query: ReQuery

	private var queue = DispatchQueue(label: "nl.pixelspark.Warp.RethinkStream")
	private var connection: Future<Fallible<(ReConnection, OrderedSet<Column>)>>!
	private var continuation: ReResponse.ContinuationCallback? = nil
	private var firstResponse: ReResponse? = nil
	private var waitingList: [Sink] = []
	private var ended = false
	private var columns: OrderedSet<Column>? = nil // A list of all columns in the result set, or nil if unknown

	public init(url: URL, query: ReQuery, columns: OrderedSet<Column>? = nil) {
		self.url = url
		self.query = query
		self.connection = nil
		self.columns = columns
		super.init()
		self.connection = Future<Fallible<(ReConnection, OrderedSet<Column>)>>({ [weak self] (job, callback) -> () in
			if let s = self {
				R.connect(url) { (err, connection) in
					if let e = err {
						callback(.failure(e.localizedDescription))
					}
					else {
						s.query.run(connection) { response in
							s.queue.sync {
								s.firstResponse = response
							}

							switch response {
							case .unknown:
								callback(.failure("Unknown first response"))

							case .error(let e):
								callback(.failure(e))

							case .Value(let v):
								if let av = v as? [AnyObject] {
									// Check if the array contains documents
									var colSet = OrderedSet<Column>()
									for d in av {
										if let doc = d as? [String: AnyObject] {
											doc.keys.forEach { k in colSet.append(Column(k)) }
										}
										else {
											callback(.failure("Received array value that contains non-document: \(v)"))
											return
										}
									}

									// Treat as any other regular result set
									let result = (connection, colSet)
									callback(.success(result))
								}
								else {
									callback(.failure("Received non-array value \(v)"))
								}

							case .rows(let docs, let cnt):
								// Find columns and set them now
								var colSet = OrderedSet<Column>()
								for d in docs {
									d.keys.forEach { k in colSet.append(Column(k)) }
								}
								let result = (connection, colSet)
								s.continuation = cnt
								//s.continueWith(cnt, job: job)
								callback(.success(result))
							}
						}
					}
				}
			}
			else {
				callback(.failure("Stream was destroyed"))
			}
			})
	}

	private func continueWith(_ continuation: ReResponse.ContinuationCallback?, job: Job) {
		self.queue.async { [weak self] in
			if let s = self {
				// We first have to get rid of the first response
				if let fr = s.firstResponse {
					assert(s.continuation == nil)
					if s.waitingList.count > 0 {
						s.firstResponse = nil
						s.continuation = continuation
						let first = s.waitingList.removeFirst()
						s.ingest(fr, consumer: first, job: job)
						return
					}
					else {
						s.continuation = continuation
						return
					}
				}
				else if let c = continuation {
					// Are there any callbacks waiting
					if s.waitingList.count > 0 {
						assert(s.continuation == nil, "there must not be an existing continuation")
						s.continuation = nil
						let firstWaiting = s.waitingList.removeFirst()
						c { (response) in
							s.ingest(response, consumer: firstWaiting, job: job)
						}
					}
					else {
						// Wait for the next request
						s.continuation = continuation
					}
				}
				else {
					s.ended = true

					// Done, empty the waiting list
					s.waitingList.forEach {
						$0(.success([]), .finished)
					}
					s.waitingList.removeAll()
					s.firstResponse = nil
					s.continuation = nil
				}
			}
		}
	}

	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		if let fc = self.columns {
			callback(.success(fc))
		}
		else {
			self.connection.get(job) { res in
				callback(res.use { p in
					/* Capture `self` explicitly here so it doesn't get destroyed while we are performing self.connection.get. */
					self.columns = p.1
					return .success(p.1)
				})
			}
		}
	}

	private func ingest(_ response: ReResponse, consumer: @escaping Sink, job: Job) {
		switch response {
		case .error(let e):
			consumer(.failure(e), .finished)

		case .rows(let docs, let continuation):
			self.columns(job, callback: { (columnsFallible) -> () in
				switch columnsFallible {
				case .success(let columns):
					let rows = docs.map { (document) -> [Value] in
						var newDocument: [Value] = []
						for column in columns {
							if let value = document[column.name] {
								if let x = value as? NSNumber {
									newDocument.append(Value.double(x.doubleValue))
								}
								else if let y = value as? String {
									newDocument.append(Value.string(y))
								}
								else if let _ = value as? NSNull {
									newDocument.append(Value.empty)
								}
								else if let x = value as? Date {
									newDocument.append(Value(x))
								}
								else {
									// Probably arrays (NSArray), dictionaries (NSDictionary) and binary data (NSData)
									newDocument.append(Value.invalid)
								}
							}
							else {
								newDocument.append(Value.empty)
							}
						}
						return newDocument
					}

					self.queue.async {
						consumer(.success(rows), continuation != nil ? .hasMore : .finished)
						self.continueWith(continuation, job: job)
					}

				case .failure(let e):
					consumer(.failure(e), .finished)
				}
			})

		case .Value(let v):
			// Maybe this value is an array that contains rows
			if let av = v as? [ReDocument] {
				// Treat as any other regular result set
				self.ingest(ReResponse.rows(av, nil), consumer: consumer, job: job)
			}
			else if let av = v as? ReDocument {
				// Treat as single document
				self.ingest(ReResponse.rows([av], nil), consumer: consumer, job: job)
			}
			else {
				consumer(.failure("Received single value: \(v)"), .finished)
			}

		case .unknown:
			consumer(.failure("Unknown response received"), .finished)
		}
	}

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		self.connection.get(job) { resFallible in
			(self.queue).async {
				if self.ended {
					resFallible.maybe({ (connection, columns) -> Void in
						connection.close()
					})
					consumer(.success([]), .finished)
					return
				}

				if let fr = self.firstResponse {
					self.firstResponse = nil
					self.continuation = nil
					self.ingest(fr, consumer: consumer, job: job)
				}
				else if self.waitingList.count > 0 {
					self.waitingList.append(consumer)
				}
				else if let cnt = self.continuation {
					self.continuation = nil
					cnt { (response) in
						self.ingest(response, consumer: consumer, job: job)
					}
				}
				else {
					self.waitingList.append(consumer)
				}
			}
		}
	}

	public func clone() -> WarpCore.Stream {
		return RethinkStream(url: self.url, query: self.query, columns: self.columns)
	}
}

/** This class provides the expressionToQuery function that translates Expression expression trees to ReSQL expressions. */
private class RethinkExpression {
	static func expressionToQuery(_ expression: Expression, prior: ReQueryValue? = nil) -> ReQueryValue? {
		if let sibling = expression as? Sibling, let p = prior {
			return p[sibling.column.name]
		}
		else if let literal = expression as? Literal {
			switch literal.value {
			case .double(let d): return R.expr(d)
			case .bool(let b): return R.expr(b)
			case .string(let s): return R.expr(s)
			case .int(let i): return R.expr(i)
			case .empty: return R.expr()
			default: return nil
			}
		}
		else if let unary = expression as? Call {
			// Check arity
			if !unary.type.arity.valid(unary.arguments.count) {
				return nil
			}

			let f = unary.arguments.first != nil ? expressionToQuery(unary.arguments.first!, prior: prior) : nil

			switch unary.type {
			case .UUID: return R.uuid()
			case .Negate: return f?.mul(R.expr(-1))
			case .Uppercase: return f?.coerceTo(.String).upcase()
			case .Lowercase: return f?.coerceTo(.String).downcase()
			case .Identity: return f
			case .Floor: return f?.floor()
			case .Ceiling: return f?.ceil()
			case .Round:
				if unary.arguments.count == 1 {
					return f?.round()
				}
				/* ReQL does not support rounding to an arbitrary number of decimals. A workaround like
				f.mul(R.expr(10).pow(decimals)).round().div(R.expr(10).pow(decimals)) should work (although there may be
				issues with floating point precision), but unfortunately ReQL does not even provide the pow function. */
				return nil

			case .If:
				// Need to use f.eq(true) because branch(...) will consider anything else than false or null to be ' true'
				if let condition = f?.eq(R.expr(true)),
					let trueAction = expressionToQuery(unary.arguments[1], prior: prior),
					let falseAction = expressionToQuery(unary.arguments[2], prior: prior) {
					return condition.branch(trueAction, falseAction)
				}
				return nil

			case .And:
				if var first = f {
					for argIndex in 1..<unary.arguments.count {
						if let second = expressionToQuery(unary.arguments[argIndex], prior: prior) {
							first = first.and(second)
						}
						else {
							return nil
						}
					}
					return first
				}
				return R.expr(true) // AND() without arguments should return true (see Function)

			case .Or:
				if var first = f {
					for argIndex in 1..<unary.arguments.count {
						if let second = expressionToQuery(unary.arguments[argIndex], prior: prior) {
							first = first.or(second)
						}
						else {
							return nil
						}
					}
					return first
				}
				return R.expr(false) // OR() without arguments should return false (see Function)

			case .Xor:
				if let first = f, let second = expressionToQuery(unary.arguments[1], prior: prior) {
					return first.xor(second)
				}
				return nil

			case .Concat:
				if var first = f?.coerceTo(.String) {
					for argIndex in 1..<unary.arguments.count {
						if let second = expressionToQuery(unary.arguments[argIndex], prior: prior) {
							first = first.add(second.coerceTo(.String))
						}
						else {
							return nil
						}
					}
					return first
				}
				return nil

			case .Random:
				return R.random()

			case .RandomBetween:
				if let lower = f, let upper = expressionToQuery(unary.arguments[1], prior: prior) {
					/* RandomBetween should generate integers between lower and upper, inclusive. The ReQL random function
					generates between [lower, upper). Also the arguments are forced to an integer (rounding down). */
					return R.random(lower.floor(), upper.floor().add(1), float: false)
				}

			case .Nth:
				if let array = f, let index = expressionToQuery(unary.arguments[1], prior: prior) {
					return array[index.coerceTo(.Number)]
				}
				return nil

			case .ValueForKey:
				if let array = f, let index = expressionToQuery(unary.arguments[1], prior: prior) {
					return array[index.coerceTo(.String)]
				}
				return nil

			default: return nil
			}
		}
		else if let binary = expression as? Comparison {
			if let s = RethinkExpression.expressionToQuery(binary.first, prior: prior), let f = RethinkExpression.expressionToQuery(binary.second, prior: prior) {
				switch binary.type {
				case .addition: return f.coerceTo(.Number).add(s.coerceTo(.Number))
				case .subtraction: return f.coerceTo(.Number).sub(s.coerceTo(.Number))
				case .multiplication: return f.coerceTo(.Number).mul(s.coerceTo(.Number))
				case .division: return f.coerceTo(.Number).div(s.coerceTo(.Number))
				case .equal: return f.eq(s)
				case .notEqual: return f.ne(s)
				case .greater: return f.coerceTo(.Number).gt(s.coerceTo(.Number))
				case .lesser: return f.coerceTo(.Number).lt(s.coerceTo(.Number))
				case .greaterEqual: return f.coerceTo(.Number).ge(s.coerceTo(.Number))
				case .lesserEqual: return f.coerceTo(.Number).le(s.coerceTo(.Number))
				case .modulus: return f.coerceTo(.Number).mod(s.coerceTo(.Number))
				case .matchesRegexStrict: return f.coerceTo(.String).match(s.coerceTo(.String)).eq(R.expr()).not()

					/* The 'match' function accepts Re2 syntax. By prefixing the pattern with '(?i)', the matching is
					case-insensitive. (http://rethinkdb.com/api/javascript/match/) */
				case .matchesRegex: return f.coerceTo(.String).match(R.expr("(?i)").add(s.coerceTo(.String))).eq(R.expr()).not()
				default: return nil
				}
			}
		}

		return nil
	}
}

public class RethinkDataset: StreamDataset {
	fileprivate let url: URL
	fileprivate let query: ReQuerySequence
	private let columns: OrderedSet<Column>? // List of all columns in the result, or nil if unknown
	private let indices: Set<Column>? // List of usable indices, or nil if no indices can be used

	/** Create a data object with the result of the given query from the server at the given URL. If the array of column
	names is set, the query *must* never return any other columns than the given columns (missing columns lead to empty
	values). In order to guarantee this, add a .withFields(columns) to any query given to this constructor. */
	public init(url: URL, query: ReQuerySequence, columns: OrderedSet<Column>? = nil, indices: Set<Column>? = nil) {
		self.url = url
		self.query = query
		self.columns = columns
		self.indices = indices
		super.init(source: RethinkStream(url: url, query: query, columns: columns))
	}

	override public func limit(_ numberOfRows: Int) -> Dataset {
		return RethinkDataset(url: self.url, query: self.query.limit(numberOfRows), columns: columns)
	}

	override public func offset(_ numberOfRows: Int) -> Dataset {
		return RethinkDataset(url: self.url, query: self.query.skip(numberOfRows), columns: columns)
	}

	override public func random(_ numberOfRows: Int) -> Dataset {
		return RethinkDataset(url: self.url, query: self.query.sample(numberOfRows), columns: columns)
	}

	override public func distinct() -> Dataset {
		return RethinkDataset(url: self.url, query: self.query.distinct(), columns: columns)
	}

	override public func filter(_ condition: Expression) -> Dataset {
		let optimized = condition.prepare()

		if RethinkExpression.expressionToQuery(optimized, prior: R.expr()) != nil {
			/* A filter is much faster if it can use an index. If this data set represents a table *and* the filter is
			of the form column=value, *and* we have an index for that column, then use getAll. */
			if let tbl = self.query as? ReQueryTable, let binary = optimized as? Comparison, binary.type == .equal {
				if let (sibling, literal) = binary.commutativePair(Sibling.self, Literal.self) {
					if self.indices?.contains(sibling.column) ?? false {
						// We can use a secondary index
						return RethinkDataset(url: self.url, query: tbl.getAll(RethinkExpression.expressionToQuery(literal)!, index: sibling.column.name), columns: columns)
					}
				}
			}

			return RethinkDataset(url: self.url, query: self.query.filter {
				i in return RethinkExpression.expressionToQuery(optimized, prior: i)!
			}, columns: columns)
		}
		return super.filter(condition)
	}

	override public func calculate(_ calculations: Dictionary<Column, Expression>) -> Dataset {
		/* Some calculations cannot be translated to ReQL. If there is one in the list, fall back. This is to satisfy
		the requirement that calculations fed to calculate() 'see' the old values in columns even while that column is
		also recalculated by the calculation set. */
		for (_, expression) in calculations {
			if RethinkExpression.expressionToQuery(expression, prior: R.expr()) == nil {
				return super.calculate(calculations)
			}
		}

		// Write the ReQL query
		let q = self.query.map { row in
			var merges: [String: ReQueryValue] = [:]
			for (column, expression) in calculations {
				merges[column.name] = RethinkExpression.expressionToQuery(expression, prior: row)
			}
			return row.merge(R.expr(merges))
		}

		// Check to see what the new list of columns will be
		let newColumns: OrderedSet<Column>?
		if let columns = self.columns {
			// Add newly added columns to the end in no particular order
			let newlyAdded = Set(calculations.keys).subtracting(columns)
			var all = columns
			all.append(contentsOf: newlyAdded)
			newColumns = all
		}
		else {
			newColumns = nil
		}

		return RethinkDataset(url: self.url, query: q, columns: newColumns)
	}

	override public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		// If the column names are known for this data set, simply return them
		if let c = self.columns {
			callback(.success(c))
			return
		}

		return super.columns(job, callback: callback)
	}

	override public func selectColumns(_ columns: OrderedSet<Column>) -> Dataset {
		return RethinkDataset(url: self.url, query: self.query.withFields(columns.map { return R.expr($0.name) }), columns: columns)
	}

	private func isCompatibleWith(_ data: RethinkDataset) -> Bool {
		return data.url == self.url
	}

	override public func union(_ data: Dataset) -> Dataset {
		if let d = data as? RethinkDataset, self.isCompatibleWith(d) {
			// Are the columns for the other data set known?
			let resultingColumns: OrderedSet<Column>?
			if let dc = d.columns, var oc = self.columns {
				oc.append(contentsOf: dc)
				resultingColumns = oc
			}
			else {
				resultingColumns = nil
			}

			return RethinkDataset(url: self.url, query: self.query.union(d.query), columns: resultingColumns)
		}
		else {
			return super.union(data)
		}
	}
}

class RethinkDatasetWarehouse: Warehouse {
	let url: URL
	let databaseName: String
	let hasFixedColumns: Bool = false
	let hasNamedTables: Bool = true

	init(url: URL, databaseName: String) {
		self.url = url
		self.databaseName = databaseName
	}

	func canPerformMutation(_ mutation: WarehouseMutation) -> Bool {
		switch mutation {
		case .create(_,_):
			return true
		}
	}

	func performMutation(_ mutation: WarehouseMutation, job: Job, callback: @escaping (Fallible<MutableDataset?>) -> ()) {
		if !canPerformMutation(mutation) {
			callback(.failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		switch mutation {
		case .create(let name, _):
			R.connect(self.url, callback: { (error, connection) -> () in
				if error != nil {
					callback(.failure(error!.localizedDescription))
					return
				}

				R.db(self.databaseName).tableCreate(name).run(connection) { response in
					switch response {
					case .error(let e):
						callback(.failure(e))

					default:
						callback(.success(RethinkMutableDataset(url: self.url, databaseName: self.databaseName, tableName: name)))
					}
				}
			})
		}
	}
}

private class RethinkInsertPuller: StreamPuller {
	let columns: OrderedSet<Column>
	let connection: ReConnection
	let table: ReQueryTable
	var callback: ((Fallible<Void>) -> ())?

	init(stream: WarpCore.Stream, job: Job, columns: OrderedSet<Column>, table: ReQueryTable, connection: ReConnection, callback: @escaping (Fallible<Void>) -> ()) {
		self.callback = callback
		self.table = table
		self.connection = connection
		self.columns = columns
		super.init(stream: stream, job: job)
	}

	override func onReceiveRows(_ rows: [Tuple], callback: @escaping (Fallible<Void>) -> ()) {
		self.mutex.locked {
			let documents = rows.map { row -> ReDocument in
				assert(row.count == self.columns.count, "Mismatching column counts")
				var document: ReDocument = [:]
				for (index, element) in self.columns.enumerated()
				{
					document[element.name] = row[index].nativeValue ?? NSNull()
				}
				return document
			}

			self.table.insert(documents).run(self.connection) { result in
				switch result {
				case .error(let e):
					callback(.failure(e))

				default:
					callback(.success())
				}
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

public class RethinkMutableDataset: MutableDataset {
	public let url: URL
	public let databaseName: String
	public let tableName: String

	public var warehouse: Warehouse { return RethinkDatasetWarehouse(url: url, databaseName: databaseName) }

	public init(url: URL, databaseName: String, tableName: String) {
		self.url = url
		self.databaseName = databaseName
		self.tableName = tableName
	}

	public func identifier(_ job: Job, callback: @escaping (Fallible<Set<Column>?>) -> ()) {
		R.connect(self.url) { err, connection in
			if let e = err {
				callback(.failure(e.localizedDescription))
				return
			}

			R.db(self.databaseName).table(self.tableName).info().run(connection) { response in
				if case ReResponse.error(let e) = response {
					callback(.failure(e))
					return
				}
				else {
					if let info = response.value as? [String: AnyObject] {
						if let pk = info["primary_key"] as? String {
							callback(.success(Set<Column>([Column(pk)])))
						}
						else {
							callback(.failure("RethinkDB failed to tell us what the primary key is"))
						}
					}
					else {
						callback(.failure("RethinkDB returned unreadable information on the table"))
					}
				}
			}
		}
	}

	public func data(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(RethinkDataset(url: self.url, query: R.db(databaseName).table(tableName))))
	}

	public func canPerformMutation(_ mutation: DatasetMutation) -> Bool {
		switch mutation {
		case .truncate, .drop, .import(_,_), .alter(_), .update(_,_,_,_), .insert(row: _), .delete(keys: _), .rename(_):
			return true

		case .edit(_,_,_,_), .remove(rows: _):
			return false
		}
	}

	public func performMutation(_ mutation: DatasetMutation, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		if !canPerformMutation(mutation) {
			callback(.failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		job.async {
			R.connect(self.url, callback: once { (err, connection) -> () in
				if let e = err {
					callback(.failure(e.localizedDescription))
					return
				}

				var q2: ReQuery? = nil
				let q: ReQuery
				switch mutation {
				case .alter:
					// RethinkDB does not have fixed columns, hence Alter is a no-op
					callback(.success())
					return

				case .update(let key, let column, _, let newValue):
					// the identifier function returns only the primary key for this table as key. Updates may not use any other key.
					if let pkeyValue = key.first {
						let document: ReDocument = [column.name: newValue.nativeValue ?? NSNull()]
						q = R.db(self.databaseName).table(self.tableName).get(pkeyValue.1.nativeValue ?? NSNull()).update(document)
					}
					else {
						return callback(.failure("Invalid key"))
					}

				case .truncate:
					q = R.db(self.databaseName).table(self.tableName).delete()

				case .drop:
					q = R.db(self.databaseName).tableDrop(self.tableName)

				case .import(let sourceDataset, _):
					/* If the source rows are produced on the same server, we might as well let the server do the
					heavy lifting. */
					if let sourceRethinkDataset = sourceDataset as? RethinkDataset, sourceRethinkDataset.url == self.url {
						q = sourceRethinkDataset.query.forEach { doc in R.db(self.databaseName).table(self.tableName).insert([doc]) }
					}
					else {
						let stream = sourceDataset.stream()

						stream.columns(job) { cns in
							switch cns {
							case .success(let columns):
								let table = R.db(self.databaseName).table(self.tableName)
								let puller = RethinkInsertPuller(stream: stream, job: job, columns: columns, table: table, connection: connection, callback: callback)
								puller.start()

							case .failure(let e):
								callback(.failure(e))
							}
						}
						return
					}

				case .insert(let row):
					var doc = ReDocument()
					for name in row.columns {
						doc[name.name] = row[name].nativeValue ?? NSNull()
					}
					q = R.db(self.databaseName).table(self.tableName).insert([doc])

				case .delete(keys: let keys):
					// TODO: if we're deleting by primary key, then .get(pk).delete() is much faster than .filter().delete()
					q = R.db(self.databaseName).table(self.tableName).filter({ row in
						var predicate: ReQueryValue = R.expr(false)

						for key in keys {
							var subPredicate = R.expr(true)
							for (col, value) in key {
								subPredicate = subPredicate.and(row[col.name].eq(value.rethinkValue))
							}

							predicate = predicate.or(subPredicate)
						}
						return predicate
					}).delete()

				case .rename(let renames):
					let newCols = renames.map { return $1 }
					var remove: [String] = []
					for (v, _) in renames {
						if !newCols.contains(v) {
							remove.append(v.name)
						}
					}

					q = R.db(self.databaseName).table(self.tableName).update({ (row: ReQueryValue) -> [String: ReQuery] in
						var changes: [String: ReQuery] = [:]
						for (old, new) in renames {
							changes[new.name] = row[old.name]
						}
						return changes
					})

					q2 = R.db(self.databaseName).table(self.tableName).replace({ (row: ReQueryValue) -> ReQuery in
						return row.without(fields: remove.map { return R.expr($0) })
					})

				case .edit(_,_,_,_), .remove(rows: _):
					fatalError("Not supported")
				}

				q.run(connection, callback: { (response) -> () in
					if case ReResponse.error(let e) = response {
						callback(.failure(e))
						return
					}
					else {
						// If there is a second query to run, run it now
						// Note, this is not atomic as RethinkDB does not support transactions
						if let q2 = q2 {
							q2.run(connection, callback: { (response) -> () in
								if case ReResponse.error(let e) = response {
									callback(.failure(e))
									return
								}
								else {
									callback(.success())
								}
							})
						}
						else {
							callback(.success())
						}
					}
				})
			})
		}
	}
}
