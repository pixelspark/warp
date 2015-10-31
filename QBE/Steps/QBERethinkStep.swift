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
			R.connect(url) { (err, connection) in
				if let e = err {
					callback(.Failure(e))
				}
				else {
					if let s = self {
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

class QBERethinkData: QBEStreamData {
	private let url: NSURL
	private let query: ReQuerySequence
	private let columns: [QBEColumn]? // List of all columns in the result, or nil if unknown

	/** Create a data object with the result of the given query from the server at the given URL. If the array of column
	names is set, the query *must* never return any other columns than the given columns (missing columns lead to empty
	values). In order to guarantee this, add a .withFields(columns) to any query given to this constructor. */
	init(url: NSURL, query: ReQuerySequence, columns: [QBEColumn]? = nil) {
		self.url = url
		self.query = query
		self.columns = columns
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

class QBERethinkStore: QBEStore {
	let url: NSURL
	let databaseName: String
	let tableName: String

	init(url: NSURL, databaseName: String, tableName: String) {
		self.url = url
		self.databaseName = databaseName
		self.tableName = tableName
	}

	func canPerformMutation(mutation: QBEMutation) -> Bool {
		switch mutation {
		case .Truncate, .Drop:
			return true
		}
	}

	func performMutation(mutation: QBEMutation, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
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
					case .Truncate:
						q = R.db(self.databaseName).table(self.tableName).delete()

					case .Drop:
						q = R.db(self.databaseName).tableDrop(self.tableName)
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
		super.init(previous: nil)
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

	private var url: NSURL? { get {
		if let u = self.authenticationKey where !u.isEmpty {
			let urlString = "rethinkdb://\(u.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLUserAllowedCharacterSet())!)@\(self.server.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!):\(self.port)"
			return NSURL(string: urlString)
		}
		else {
			let urlString = "rethinkdb://\(self.server.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!):\(self.port)"
			return NSURL(string: urlString)
		}
	} }

	private func sourceData() -> QBEFallible<QBEData> {
		if let u = url {
			var q: ReQuerySequence = R.db(self.database).table(self.table)
			if self.columns.count > 0 {
				q = q.withFields(self.columns.map { return R.expr($0.name) })
			}
			return .Success(QBERethinkData(url: u, query: q, columns: self.columns.count > 0 ? self.columns : nil))
		}
		else {
			return .Failure(NSLocalizedString("The location of the RethinkDB server is invalid.", comment: ""))
		}
	}

	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		callback(sourceData())
	}

	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		callback(sourceData().use { d in
			return d.limit(maxInputRows)
		})
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

	override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Read table [#] from database [#]", comment: ""),
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

	override var store: QBEStore? {
		if let u = self.url {
			return QBERethinkStore(url: u, databaseName: self.database, tableName: self.table)
		}
		return nil
	}
}