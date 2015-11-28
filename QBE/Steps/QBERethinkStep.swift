import Foundation
import WarpCore
import  Rethink

final class QBERethinkStream: NSObject, QBEStream {
	let url: NSURL
	let query: ReQuery

	private var queue = dispatch_queue_create("nl.pixelspark.Warp.QBERethinkStream", DISPATCH_QUEUE_SERIAL)
	private var connection: QBEFuture<QBEFallible<(ReConnection, [QBEColumn])>>!
	private var continuation: ReResponse.ContinuationCallback? = nil
	private var firstResponse: ReResponse? = nil
	private var waitingList: [QBESink] = []
	private var ended = false
	private var columns: [QBEColumn]? = nil // A list of all columns in the result set, or nil if unknown

	init(url: NSURL, query: ReQuery, columns: [QBEColumn]? = nil) {
		self.url = url
		self.query = query
		self.connection = nil
		self.columns = columns
		super.init()
		self.connection = QBEFuture<QBEFallible<(ReConnection, [QBEColumn])>>({ [weak self] (job, callback) -> () in
			if let s = self {
				R.connect(url) { (err, connection) in
					if let e = err {
						callback(.Failure(e))
					}
					else {
						s.query.run(connection) { response in
							dispatch_sync(s.queue) {
								s.firstResponse = response
							}

							switch response {
							case .Unknown:
								callback(.Failure("Unknown first response"))

							case .Error(let e):
								callback(.Failure(e))

							case .Value(let v):
								if let av = v as? [AnyObject] {
									// Check if the array contains documents
									var colSet = Set<QBEColumn>()
									for d in av {
										if let doc = d as? [String: AnyObject] {
											doc.keys.forEach { k in colSet.insert(QBEColumn(k)) }
										}
										else {
											callback(.Failure("Received array value that contains non-document: \(v)"))
											return
										}
									}

									// Treat as any other regular result set
									let columns = Array(colSet)
									let result = (connection, columns)
									callback(.Success(result))
								}
								else {
									callback(.Failure("Received non-array value \(v)"))
								}

							case .Rows(let docs, let cnt):
								// Find columns and set them now
								var colSet = Set<QBEColumn>()
								for d in docs {
									d.keys.forEach { k in colSet.insert(QBEColumn(k)) }
								}
								let columns = Array(colSet)
								let result = (connection, columns)
								s.continuation = cnt
								//s.continueWith(cnt, job: job)
								callback(.Success(result))
							}
						}
					}
				}
			}
		})
	}

	private func continueWith(continuation: ReResponse.ContinuationCallback?, job: QBEJob) {
		dispatch_async(self.queue) { [weak self] in
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
						$0(.Success([]), .Finished)
					}
					s.waitingList.removeAll()
					s.firstResponse = nil
					s.continuation = nil
				}
			}
		}
	}

	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		if let fc = self.columns {
			callback(.Success(fc))
		}
		else {
			self.connection.get(job) { res in
				callback(res.use { return $0.1 })
			}
		}
	}

	private func ingest(response: ReResponse, consumer: QBESink, job: QBEJob) {
		switch response {
			case .Error(let e):
				consumer(.Failure(e), .Finished)

			case .Rows(let docs, let continuation):
				self.columnNames(job, callback: { (columnsFallible) -> () in
					switch columnsFallible {
						case .Success(let columns):
							let rows = docs.map { (document) -> [QBEValue] in
								var newDocument: [QBEValue] = []
								for column in columns {
									if let value = document[column.name] {
										if let x = value as? NSNumber {
											newDocument.append(QBEValue.DoubleValue(x.doubleValue))
										}
										else if let y = value as? String {
											newDocument.append(QBEValue.StringValue(y))
										}
										else if let _ = value as? NSNull {
											newDocument.append(QBEValue.EmptyValue)
										}
										else if let x = value as? NSDate {
											newDocument.append(QBEValue(x))
										}
										else {
											// Probably arrays (NSArray), dictionaries (NSDictionary) and binary data (NSData)
											newDocument.append(QBEValue.InvalidValue)
										}
									}
									else {
										newDocument.append(QBEValue.EmptyValue)
									}
								}
								return newDocument
							}

							dispatch_async(self.queue) {
								consumer(.Success(rows), continuation != nil ? .HasMore : .Finished)
								self.continueWith(continuation, job: job)
							}

						case .Failure(let e):
							consumer(.Failure(e), .Finished)
					}
				})

			case .Value(let v):
				// Maybe this value is an array that contains rows
				if let av = v as? [ReDocument] {
					// Treat as any other regular result set
					self.ingest(ReResponse.Rows(av, nil), consumer: consumer, job: job)
				}
				else if let av = v as? ReDocument {
					// Treat as single document
					self.ingest(ReResponse.Rows([av], nil), consumer: consumer, job: job)
				}
				else {
					consumer(.Failure("Received single value: \(v)"), .Finished)
				}

			case .Unknown:
				consumer(.Failure("Unknown response received"), .Finished)
		}
	}

	func fetch(job: QBEJob, consumer: QBESink) {
		self.connection.get(job) { resFallible in
			dispatch_async(self.queue) {
				if self.ended {
					resFallible.maybe({ (connection, columns) -> Void in
						connection.close()
					})
					consumer(.Success([]), .Finished)
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

	func clone() -> QBEStream {
		return QBERethinkStream(url: self.url, query: self.query, columns: self.columns)
	}
}

/** This class provides the expressionToQuery function that translates QBEExpression expression trees to ReSQL expressions. */
private class QBERethinkExpression {
	static func expressionToQuery(expression: QBEExpression, prior: ReQueryValue? = nil) -> ReQueryValue? {
		if let sibling = expression as? QBESiblingExpression, let p = prior {
			return p[sibling.columnName.name]
		}
		else if let literal = expression as? QBELiteralExpression {
			switch literal.value {
			case .DoubleValue(let d): return R.expr(d)
			case .BoolValue(let b): return R.expr(b)
			case .StringValue(let s): return R.expr(s)
			case .IntValue(let i): return R.expr(i)
			case .EmptyValue: return R.expr()
			default: return nil
			}
		}
		else if let unary = expression as? QBEFunctionExpression {
			// Check arity
			if !unary.type.arity.valid(unary.arguments.count) {
				return nil
			}

			let f = unary.arguments.first != nil ? expressionToQuery(unary.arguments.first!, prior: prior) : nil

			switch unary.type {
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
				return R.expr(true) // AND() without arguments should return true (see QBEFunction)

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
				return R.expr(false) // OR() without arguments should return false (see QBEFunction)

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

			default: return nil
			}
		}
		else if let binary = expression as? QBEBinaryExpression {
			if let s = QBERethinkExpression.expressionToQuery(binary.first, prior: prior), let f = QBERethinkExpression.expressionToQuery(binary.second, prior: prior) {
				switch binary.type {
				case .Addition: return f.coerceTo(.Number).add(s.coerceTo(.Number))
				case .Subtraction: return f.coerceTo(.Number).sub(s.coerceTo(.Number))
				case .Multiplication: return f.coerceTo(.Number).mul(s.coerceTo(.Number))
				case .Division: return f.coerceTo(.Number).div(s.coerceTo(.Number))
				case .Equal: return f.eq(s)
				case .NotEqual: return f.ne(s)
				case .Greater: return f.gt(s)
				case .Lesser: return f.lt(s)
				case .GreaterEqual: return f.ge(s)
				case .LesserEqual: return f.le(s)
				case .Modulus: return f.mod(s)
				default: return nil
				}
			}
		}

		return nil
	}
}

class QBERethinkData: QBEStreamData {
	private let url: NSURL
	private let query: ReQuerySequence
	private let columns: [QBEColumn]? // List of all columns in the result, or nil if unknown
	private let indices: Set<QBEColumn>? // List of usable indices, or nil if no indices can be used

	/** Create a data object with the result of the given query from the server at the given URL. If the array of column
	names is set, the query *must* never return any other columns than the given columns (missing columns lead to empty
	values). In order to guarantee this, add a .withFields(columns) to any query given to this constructor. */
	init(url: NSURL, query: ReQuerySequence, columns: [QBEColumn]? = nil, indices: Set<QBEColumn>? = nil) {
		self.url = url
		self.query = query
		self.columns = columns
		self.indices = indices
		super.init(source: QBERethinkStream(url: url, query: query, columns: columns))
	}

	override func limit(numberOfRows: Int) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.limit(numberOfRows), columns: columns)
	}

	override func offset(numberOfRows: Int) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.skip(numberOfRows), columns: columns)
	}

	override func random(numberOfRows: Int) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.sample(numberOfRows), columns: columns)
	}

	override func distinct() -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.distinct(), columns: columns)
	}

	override func filter(condition: QBEExpression) -> QBEData {
		let optimized = condition.prepare()

		if QBERethinkExpression.expressionToQuery(optimized, prior: R.expr()) != nil {
			/* A filter is much faster if it can use an index. If this data set represents a table *and* the filter is
			of the form column=value, *and* we have an index for that column, then use getAll. */
			if let tbl = self.query as? ReQueryTable, let binary = optimized as? QBEBinaryExpression where binary.type == .Equal {
				if let (sibling, literal) = binary.commutativePair(QBESiblingExpression.self, QBELiteralExpression.self) {
					if self.indices?.contains(sibling.columnName) ?? false {
						// We can use a secondary index
						return QBERethinkData(url: self.url, query: tbl.getAll(QBERethinkExpression.expressionToQuery(literal)!, index: sibling.columnName.name), columns: columns)
					}
				}
			}

			return QBERethinkData(url: self.url, query: self.query.filter {
				i in return QBERethinkExpression.expressionToQuery(optimized, prior: i)!
			}, columns: columns)
		}
		return super.filter(condition)
	}

	override func calculate(calculations: Dictionary<QBEColumn, QBEExpression>) -> QBEData {
		/* Some calculations cannot be translated to ReQL. If there is one in the list, fall back. This is to satisfy
		the requirement that calculations fed to calculate() 'see' the old values in columns even while that column is
		also recalculated by the calculation set. */
		for (_, expression) in calculations {
			if QBERethinkExpression.expressionToQuery(expression, prior: R.expr()) == nil {
				return super.calculate(calculations)
			}
		}

		// Write the ReQL query
		let q = self.query.map { row in
			var merges: [String: ReQueryValue] = [:]
			for (column, expression) in calculations {
				merges[column.name] = QBERethinkExpression.expressionToQuery(expression, prior: row)
			}
			return row.merge(R.expr(merges))
		}

		// Check to see what the new list of columns will be
		let newColumns: [QBEColumn]?
		if let columns = self.columns {
			// Add newly added columns to the end in no particular order
			let newlyAdded = Set(calculations.keys).subtract(columns)
			var all = columns
			all.appendContentsOf(newlyAdded)
			newColumns = all
		}
		else {
			newColumns = nil
		}

		return QBERethinkData(url: self.url, query: q, columns: newColumns)
	}

	override func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		// If the column names are known for this data set, simply return them
		if let c = self.columns {
			callback(.Success(c))
			return
		}

		return super.columnNames(job, callback: callback)
	}

	override func selectColumns(columns: [QBEColumn]) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.withFields(columns.map { return R.expr($0.name) }), columns: columns)
	}

	private func isCompatibleWith(data: QBERethinkData) -> Bool {
		return data.url == self.url
	}

	override func union(data: QBEData) -> QBEData {
		if let d = data as? QBERethinkData where self.isCompatibleWith(d) {
			// Are the columns for the other data set known?
			let resultingColumns: [QBEColumn]?
			if let dc = d.columns, var oc = self.columns {
				oc.appendContentsOf(dc)
				resultingColumns = Array(Set(oc))
			}
			else {
				resultingColumns = nil
			}

			return QBERethinkData(url: self.url, query: self.query.union(d.query), columns: resultingColumns)
		}
		else {
			return super.union(data)
		}
	}
}

class QBERethinkDataWarehouse: QBEDataWarehouse {
	let url: NSURL
	let databaseName: String
	let hasFixedColumns: Bool = false
	let hasNamedTables: Bool = true

	init(url: NSURL, databaseName: String) {
		self.url = url
		self.databaseName = databaseName
	}

	func canPerformMutation(mutation: QBEWarehouseMutation) -> Bool {
		switch mutation {
		case .Create(_,_):
			return true
		}
	}

	func performMutation(mutation: QBEWarehouseMutation, job: QBEJob, callback: (QBEFallible<QBEMutableData?>) -> ()) {
		if !canPerformMutation(mutation) {
			callback(.Failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		switch mutation {
		case .Create(let name, _):
			R.connect(self.url, callback: { (error, connection) -> () in
				if error != nil {
					callback(.Failure(error!))
					return
				}

				R.db(self.databaseName).tableCreate(name).run(connection) { response in
					switch response {
					case .Error(let e):
						callback(.Failure(e))

					default:
						callback(.Success(QBERethinkMutableData(url: self.url, databaseName: self.databaseName, tableName: name)))
					}
				}
			})
		}
	}
}

private class QBERethinkInsertPuller: QBEStreamPuller {
	let columnNames: [QBEColumn]
	let connection: ReConnection
	let table: ReQueryTable
	var callback: ((QBEFallible<Void>) -> ())?

	init(stream: QBEStream, job: QBEJob, columnNames: [QBEColumn], table: ReQueryTable, connection: ReConnection, callback: (QBEFallible<Void>) -> ()) {
		self.callback = callback
		self.table = table
		self.connection = connection
		self.columnNames = columnNames
		super.init(stream: stream, job: job)
	}

	override func onReceiveRows(rows: [QBETuple], callback: (QBEFallible<Void>) -> ()) {
		self.mutex.locked {
			let documents = rows.map { row -> ReDocument in
				assert(row.count == self.columnNames.count, "Mismatching column counts")
				var document: ReDocument = [:]
				for (index, element) in self.columnNames.enumerate()
				{
					document[element.name] = row[index].stringValue
				}
				return document
			}

			self.table.insert(documents).run(self.connection) { result in
				switch result {
				case .Error(let e):
					callback(.Failure(e))

				default:
					callback(.Success())
				}
			}
		}
	}

	override func onDoneReceiving() {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil
			self.job.async {
				cb(.Success())
			}
		}
	}

	override func onError(error: String) {
		self.mutex.locked {
			let cb = self.callback!
			self.callback = nil

			self.job.async {
				cb(.Failure(error))
			}
		}
	}
}

class QBERethinkMutableData: QBEMutableData {
	let url: NSURL
	let databaseName: String
	let tableName: String

	var warehouse: QBEDataWarehouse { return QBERethinkDataWarehouse(url: url, databaseName: databaseName) }

	init(url: NSURL, databaseName: String, tableName: String) {
		self.url = url
		self.databaseName = databaseName
		self.tableName = tableName
	}

	func data(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(QBERethinkData(url: self.url, query: R.db(databaseName).table(tableName))))
	}

	func canPerformMutation(mutation: QBEDataMutation) -> Bool {
		switch mutation {
		case .Truncate, .Drop, .Insert(_,_), .Alter(_):
			return true
		}
	}

	func performMutation(mutation: QBEDataMutation, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		if !canPerformMutation(mutation) {
			callback(.Failure(NSLocalizedString("The selected action cannot be performed on this data set.", comment: "")))
			return
		}

		job.async {
			R.connect(self.url) { (err, connection) -> () in
				if let e = err {
					callback(.Failure(e))
					return
				}

				let q: ReQuery
				switch mutation {
					case .Alter:
						// RethinkDB does not have fixed columns, hence Alter is a no-op
						callback(.Success())
						return

					case .Truncate:
						q = R.db(self.databaseName).table(self.tableName).delete()

					case .Drop:
						q = R.db(self.databaseName).tableDrop(self.tableName)

					case .Insert(let sourceData, _):
						/* If the source rows are produced on the same server, we might as well let the server do the 
						heavy lifting. */
						if let sourceRethinkData = sourceData as? QBERethinkData where sourceRethinkData.url == self.url {
							q = sourceRethinkData.query.forEach { doc in R.db(self.databaseName).table(self.tableName).insert([doc]) }
						}
						else {
							let stream = sourceData.stream()

							stream.columnNames(job) { cns in
								switch cns {
								case .Success(let columnNames):
									let table = R.db(self.databaseName).table(self.tableName)
									let puller = QBERethinkInsertPuller(stream: stream, job: job, columnNames: columnNames, table: table, connection: connection, callback: callback)
									puller.start()

								case .Failure(let e):
									callback(.Failure(e))
								}
							}
							return
						}
				}

				q.run(connection, callback: { (response) -> () in
					if case ReResponse.Error(let e) = response {
						callback(.Failure(e))
						return
					}
					else {
						callback(.Success())
					}
				})
			}
		}
	}
}

class QBERethinkSourceStep: QBEStep {
	var database: String = "test"
	var table: String = "test"
	var server: String = "localhost"
	var port: Int = 28015
	var authenticationKey: String? = nil
	var columns: [QBEColumn] = []

	required override init(previous: QBEStep?) {
		super.init()
	}

	required init() {
		super.init()
	}

	required init(coder aDecoder: NSCoder) {
		self.server = aDecoder.decodeStringForKey("server") ?? "localhost"
		self.table = aDecoder.decodeStringForKey("table") ?? "test"
		self.database = aDecoder.decodeStringForKey("database") ?? "test"
		self.port = max(1, min(65535, aDecoder.decodeIntegerForKey("port") ?? 28015));
		self.authenticationKey = aDecoder.decodeStringForKey("authenticationKey")
		let cols = (aDecoder.decodeObjectForKey("columns") as? [String]) ?? []
		self.columns = cols.map { return QBEColumn($0) }
		super.init(coder: aDecoder)
	}

	internal var url: NSURL? { get {
		if let u = self.authenticationKey where !u.isEmpty {
			let urlString = "rethinkdb://\(u.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLUserAllowedCharacterSet())!)@\(self.server.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!):\(self.port)"
			return NSURL(string: urlString)
		}
		else {
			let urlString = "rethinkdb://\(self.server.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!):\(self.port)"
			return NSURL(string: urlString)
		}
	} }

	private func sourceData(callback: (QBEFallible<QBEData>) -> ()) {
		if let u = url {
			let table = R.db(self.database).table(self.table)

			if self.columns.count > 0 {
				let q = table.withFields(self.columns.map { return R.expr($0.name) })
				callback(.Success(QBERethinkData(url: u, query: q, columns: self.columns.count > 0 ? self.columns : nil)))
			}
			else {
				R.connect(u, callback: { (err, connection) -> () in
					if let e = err {
						callback(.Failure(e))
						return
					}

					table.indexList().run(connection) { response in
						if case .Value(let indices) = response, let indexList = indices as? [String] {
							callback(.Success(QBERethinkData(url: u, query: table, columns: !self.columns.isEmpty ? self.columns : nil, indices: Set(indexList.map { return QBEColumn($0) }))))
						}
						else {
							// Carry on without indexes
							callback(.Success(QBERethinkData(url: u, query: table, columns: !self.columns.isEmpty ? self.columns : nil, indices: nil)))
						}
					}
				})
			}
		}
		else {
			callback(.Failure(NSLocalizedString("The location of the RethinkDB server is invalid.", comment: "")))
		}
	}

	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		sourceData(callback)
	}

	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		sourceData { t in
			switch t {
			case .Failure(let e): callback(.Failure(e))
			case .Success(let d): callback(.Success(d.limit(maxInputRows)))
			}
		}
	}

	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeString(self.server, forKey: "server")
		coder.encodeString(self.database, forKey: "database")
		coder.encodeString(self.table, forKey: "table")
		coder.encodeInteger(self.port, forKey: "port")
		coder.encodeObject(NSArray(array: self.columns.map { return $0.name }), forKey: "columns")
		if let s = self.authenticationKey {
			coder.encodeString(s, forKey: "authenticationKey")
		}
	}

	override func sentence(locale: QBELocale, variant: QBESentenceVariant) -> QBESentence {
		let template: String
		switch variant {
		case .Read, .Neutral: template = "Read table [#] from RethinkDB database [#]"
		case .Write: template = "Write to table [#] in RethinkDB database [#]";
		}

		return QBESentence(format: NSLocalizedString(template, comment: ""),
			QBESentenceList(value: self.table, provider: { pc in
				R.connect(self.url!, callback: { (err, connection) in
					if err != nil {
						pc(.Failure(err!))
						return
					}

					R.db(self.database).tableList().run(connection) { (response) in
						/* While it is not strictly necessary to close the connection explicitly, we do it here to keep 
						a reference to the connection, as to keep the connection alive until the query returns. */
						connection.close()
						if case .Error(let e) = response {
							pc(.Failure(e))
							return
						}

						if let v = response.value as? [String] {
							pc(.Success(v))
						}
						else {
							pc(.Failure("invalid list received"))
						}
					}
				})
				}, callback: { (newTable) -> () in
					self.table = newTable
				}),


			QBESentenceList(value: self.database, provider: { pc in
				R.connect(self.url!, callback: { (err, connection) in
					if err != nil {
						pc(.Failure(err!))
						return
					}

					R.dbList().run(connection) { (response) in
						/* While it is not strictly necessary to close the connection explicitly, we do it here to keep
						a reference to the connection, as to keep the connection alive until the query returns. */
						connection.close()
						if case .Error(let e) = response {
							pc(.Failure(e))
							return
						}

						if let v = response.value as? [String] {
							pc(.Success(v))
						}
						else {
							pc(.Failure("invalid list received"))
						}
					}
				})
			}, callback: { (newDatabase) -> () in
				self.database = newDatabase
			})
		)
	}

	override var mutableData: QBEMutableData? {
		if let u = self.url where !self.table.isEmpty {
			return QBERethinkMutableData(url: u, databaseName: self.database, tableName: self.table)
		}
		return nil
	}
}