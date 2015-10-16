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

	init(url: NSURL, query: ReQuery) {
		self.url = url
		self.query = query
		self.connection = nil
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
									callback(.Success(result))
									s.continueWith(cnt, job: job)
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
						$0(.Success([]), false)
					}
					s.waitingList.removeAll()
					s.firstResponse = nil
					s.continuation = nil
				}
			}
		}
	}

	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		self.connection.get(job) { res in
			callback(res.use { return $0.1 })
		}
	}

	private func ingest(response: ReResponse, consumer: QBESink, job: QBEJob) {
		switch response {
			case .Error(let e):
				consumer(.Failure(e), false)

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
								consumer(.Success(rows), continuation == nil)
								self.continueWith(continuation, job: job)
							}

						case .Failure(let e):
							consumer(.Failure(e), false)
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
					consumer(.Failure("Received single value: \(v)"), false)
				}

			case .Unknown:
				consumer(.Failure("Unknown response received"), false)
		}
	}

	func fetch(job: QBEJob, consumer: QBESink) {
		self.connection.get(job) { resFallible in
			dispatch_async(self.queue) {
				if self.ended {
					resFallible.maybe({ (connection, columns) -> Void in
						connection.close()
					})
					consumer(.Success([]), false)
					return
				}

				if let fr = self.firstResponse {
					self.firstResponse = nil
					self.ingest(fr, consumer: consumer, job: job)
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
		return QBERethinkStream(url: self.url, query: self.query)
	}

	deinit {
		print("Stream deinit")
	}
}

class QBERethinkData: QBEStreamData {
	private let url: NSURL
	private let query: ReQuerySequence

	init(url: NSURL, query: ReQuerySequence) {
		self.url = url
		self.query = query
		super.init(source: QBERethinkStream(url: url, query: query))
	}

	override func limit(numberOfRows: Int) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.limit(numberOfRows))
	}

	override func offset(numberOfRows: Int) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.skip(numberOfRows))
	}

	override func random(numberOfRows: Int) -> QBEData {
		return QBERethinkData(url: self.url, query: self.query.sample(numberOfRows))
	}
}

class QBERethinkSourceStep: QBEStep {
	var database: String = "test"
	var table: String = "test"
	var server: String = "localhost"
	var port: Int = 28015
	var authenticationKey: String? = nil

	required override init(previous: QBEStep?) {
		super.init(previous: nil)
	}

	required init(coder aDecoder: NSCoder) {
		self.server = aDecoder.decodeStringForKey("server") ?? "localhost"
		self.server = aDecoder.decodeStringForKey("table") ?? "test"
		self.server = aDecoder.decodeStringForKey("database") ?? "test"
		self.port = max(1, min(65535, aDecoder.decodeIntegerForKey("port") ?? 28015));
		self.authenticationKey = aDecoder.decodeStringForKey("authenticationKey")
		super.init(coder: aDecoder)
	}

	private var url: NSURL? { get {
		if let u = self.authenticationKey {
			return NSURL(string: "rethinkdb://\(u.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLUserAllowedCharacterSet())!)@\(self.server.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())):\(self.port)")
		}
		else {
			let urlString = "rethinkdb://\(self.server.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLHostAllowedCharacterSet())!):\(self.port)"
			return NSURL(string: urlString)
		}
	} }

	private func sourceData() -> QBEFallible<QBEData> {
		if let u = url {
			return .Success(QBERethinkData(url: u, query: R.db(self.database).table(self.table)))
		}
		else {
			return .Failure(NSLocalizedString("The location of the Rethink database is invalid.", comment: ""))
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
		if let s = self.authenticationKey {
			coder.encodeString(s, forKey: "authenticationKey")
		}
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Read table [#] from database [#] at RethinkDB server [#] port [#]", comment: ""),
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
			}),

			QBESentenceTextInput(value: self.server, callback: { (s) -> (Bool) in
				if s.isEmpty { return false }
				self.server = s
				return true
			}),

			QBESentenceTextInput(value: "\(self.port)", callback: { (s) -> (Bool) in
				if let p = s.toInt() where p>0 && p<65536 {
					self.port = p
					return true
				}
				return false
			})
		)
	}
}