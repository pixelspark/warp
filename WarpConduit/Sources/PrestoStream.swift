/* Copyright (c) 2014-2017 Pixelspark, Tommy van der Vorst

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
import WarpCore
import Alamofire

private class PrestoSQLDialect: StandardSQLDialect {
	fileprivate override func forceNumericExpression(_ expression: String) -> String {
		return "TRY_CAST(\(expression) AS DOUBLE)"
	}

	fileprivate override func forceStringExpression(_ expression: String) -> String {
		return "CAST(\(expression) AS VARCHAR)"
	}

	override var supportsWindowFunctions: Bool {
		return false
	}
}

public class PrestoStream: NSObject, WarpCore.Stream {
	let url: URL
	let sql: String
	let catalog: String
	let schema: String

	private var buffer: [Tuple] = []
	private var columns: Fallible<OrderedSet<Column>>?
	private var stopped: Bool = false
	private var started: Bool = false
	private var nextURI: URL?
	private var columnsFuture: Future<Fallible<OrderedSet<Column>>>! = nil
	private var mutex = Mutex()
	private var queryId: String? = nil

	init(url: URL, sql: String, catalog: String, schema: String) {
		self.url = url
		self.sql = sql
		self.schema = schema
		self.catalog = catalog
		self.nextURI = self.url.appendingPathComponent("/v1/statement")
		super.init()

		let c = { [weak self] (job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) -> () in
			self?.awaitColumns(job) { result in
				switch result {
				case .success():
					callback(self?.columns ?? .failure(NSLocalizedString("Could not load column names from Presto.", comment: "")))

				case .failure(let e):
					callback(.failure(e))
				}
			}
		}

		self.columnsFuture = Future<Fallible<OrderedSet<Column>>>(c)
	}

	public func close(_ job: Job? = nil, callback: ((Fallible<Void>) -> ())? = nil) {
		self.mutex.locked {
			if let qid = queryId {
				job?.log("Presto close \(qid)")
				let deleteURL = self.url.appendingPathComponent("/v1/query/\(qid)")
				let request = NSMutableURLRequest(url: deleteURL)
				request.httpMethod = "DELETE";
				request.setValue("Warp", forHTTPHeaderField: "User-Agent")

				Alamofire.request(request as URLRequest).responseJSON(options: [], completionHandler: { response in
					if response.result.isSuccess {
						job?.log("Presto close \(qid): success")
						callback?(.success())
						return
					}
					else {
						job?.log("Presto close \(qid): failure")
						callback?(.failure("Cannot close query \(qid)"))
						return
					}
				})
			}
			else {
				job?.log("Presto cannot close query, because we have no query ID (SQL=\(sql))")
				callback?(.success())
				return
			}
		}
	}

	/** Request the next batch of result data from Presto. */
	private func request(_ job: Job, callback: @escaping (Fallible<()>) -> ()) {
		if job.isCancelled {
			self.close()
		}

		self.mutex.locked { () -> () in
			if stopped {
				return callback(.success())
			}

			if let endpoint = self.nextURI {
				let request = NSMutableURLRequest(url: endpoint)
				request.setValue("Warp", forHTTPHeaderField: "User-Agent")

				if !started {
					// Initial request
					started = true
					request.httpMethod = "POST"
					request.setValue("Warp", forHTTPHeaderField: "X-Presto-User")
					request.setValue("Warp", forHTTPHeaderField: "X-Presto-Source")
					request.setValue(self.catalog, forHTTPHeaderField: "X-Presto-Catalog")
					request.setValue(self.schema, forHTTPHeaderField: "X-Presto-Schema")

					if let sqlQueryData = sql.data(using: String.Encoding.utf8, allowLossyConversion: false) {
						request.httpBody = sqlQueryData
					}
					job.log("Presto SQL: \(sql)")
				}
				else {
					// Follow-up request
					request.httpMethod = "GET"
				}

				Alamofire.request(request as URLRequest).responseJSON(options: [], completionHandler: { response in
					if response.result.isSuccess {
						// Let's see if the response got something useful
						if let d = response.result.value as? [String: AnyObject] {
							// Do we have a query ID?
							if let qid = d["id"] as? String {
								self.mutex.locked {
									self.queryId = qid
								}
							}

							// Was there an error?
							if let error = d["error"] as? [String: AnyObject] {
								let errorName = error["errorName"] as? String ?? "(unknown)"
								let message: String
								if let failureInfo = error["failureInfo"] as? [String: AnyObject] {
									message = (failureInfo["message"] as? String) ?? "(no further information)"
								}
								else {
									message = ""
								}

								self.mutex.locked {
									self.nextURI = nil
									self.stopped = true
								}

								callback(.failure(String(format: "Presto error %@: %@", errorName, message)))
								return
							}

							// Get progress data from response
							if let stats = d["stats"] as? [String: AnyObject] {
								if let completedSplits = stats["completedSplits"] as? Int,
									let queuedSplits = stats["queuedSplits"] as? Int {
									if (completedSplits + queuedSplits) > 0 {
										let progress = Double(completedSplits) / Double(completedSplits + queuedSplits)
										job.reportProgress(progress, forKey: self.hash)
									}
								}
							}

							self.mutex.locked {
								// Does the response tell us where to look next?
								if let nu = (d["nextUri"] as? String) {
									self.nextURI = URL(string: nu)
								}
								else {
									self.nextURI = nil
									self.stopped = true
								}
							}

							// Does the response include column information?
							if self.columns == nil {
								if let columns = d["columns"] as? [AnyObject] {
									var newColumns: OrderedSet<Column> = []

									for columnSpec in columns {
										if let columnInfo = columnSpec as? [String: AnyObject] {
											if let name = columnInfo["name"] as? String {
												newColumns.append(Column(name))
											}
										}
									}
									self.columns = .success(newColumns)
								}
							}

							// Does the response contain any data?
							if let data = d["data"] as? [AnyObject] {
								job.time("Presto fetch", items: data.count, itemType: "row") {
									var templateRow: [Value] = []
									for row in data {
										if let rowArray = row as? [AnyObject] {
											for cell in rowArray {
												if let value = cell as? NSNumber {
													templateRow.append(Value(value.doubleValue))
												}
												else if let value = cell as? String {
													templateRow.append(Value(value))
												}
												else if cell is NSNull {
													templateRow.append(Value.empty)
												}
												else {
													templateRow.append(Value.invalid)
												}
											}
										}
										self.buffer.append(templateRow)
										templateRow.removeAll(keepingCapacity: true)
									}
								}

							}

							return callback(.success())
						}
						else {
							self.nextURI = nil
							self.stopped = true
							return callback(.failure("returned response has an invalid format"))
						}
					}
					else {
						if response.response?.statusCode == 503 {
							// Status code 503 means that we should wait a bit
							job.log("Presto returned status code 503, waiting for a while")
							let queue = DispatchQueue.global(qos: .userInitiated)
							queue.asyncAfter(deadline: DispatchTime.now() + 0.1) {
								callback(.success())
							}
							return
						}
						else if response.response?.statusCode == 410 {
							// Status code 410 indicates a temporary error
							job.log("Presto returned status code 410, waiting for a while")
							let queue = DispatchQueue.global(qos: .userInitiated)
							queue.asyncAfter(deadline: DispatchTime.now() + 1.0) {
								callback(.success())
							}
							return
						}
						else {
							self.mutex.locked {
								// Any status code other than 200 means trouble
								self.stopped = true
								self.nextURI = nil
							}
							let ss = response.response?.statusCode ?? 0
							let ld = response.result.error?.localizedDescription ?? ""
							return callback(.failure("Presto error \(ss): \(ld))"))
						}
					}
				})
			}
		}
	}

	private func awaitColumns(_ job: Job, callback: @escaping (Fallible<()>) -> ()) {
		request(job) { result in
			switch result {
			case .success():
				if self.columns == nil && !self.stopped {
					job.async {
						self.awaitColumns(job, callback: callback)
					}
				}
				else {
					callback(.success())
				}
			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		request(job) { result in
			switch result {
			case .success():
				let (rows, stopped) = self.mutex.locked { () -> ([Tuple], Bool) in
					let rows = self.buffer
					self.buffer.removeAll(keepingCapacity: true)
					return (rows, self.stopped)
				}
				consumer(.success(Array(rows)), stopped ? .finished : .hasMore)

			case .failure(let e):
				consumer(.failure(e), .finished)
			}
		}
	}

	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		let s = self
		self.columnsFuture.get(job) { result in
			// The mutex locking is just here to keep 'self' alive while columns are being fetched.
			s.mutex.locked {
				callback(result)
			}
		}
	}

	public func clone() -> WarpCore.Stream {
		return PrestoStream(url: self.url, sql: self.sql, catalog: self.catalog, schema: self.schema)
	}
}

public class PrestoDatabase {
	let url: URL
	let schema: String
	let catalog: String
	let dialect: SQLDialect = PrestoSQLDialect()

	public init(url: URL, catalog: String, schema: String) {
		self.url = url
		self.catalog = catalog
		self.schema = schema
	}

	public func query(_ sql: String) -> PrestoStream {
		return PrestoStream(url: url, sql: sql, catalog: catalog, schema: schema)
	}

	public func run(_ sql: [String], job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		var sql = sql
		let mutex = Mutex() // To protect the list of queryes

		// TODO check for memory leaks
		var consume: (() -> ())? = nil
		consume = { () -> () in
			mutex.locked {
				let q = sql.removeFirst()
				let stream = self.query(q)
				stream.fetch(job) { (res, _) -> () in
					mutex.locked {
						if case .failure(let e) = res {
							callback(.failure(e))
						}
						else {
							job.async {
								consume?()
							}
						}
					}
				}
			}
		}

		consume!()
	}

	var tableNames: [String]? { get {
		return []
	} }
}

public class PrestoDataset: SQLDataset {
	private let db: PrestoDatabase

	public class func tableDataset(_ job: Job, db: PrestoDatabase, tableName: String, schemaName: String, catalogName: String, callback: @escaping (Fallible<PrestoDataset>) -> ()) {
		let alias = tableName
		let sql = "SELECT * FROM \(db.dialect.tableIdentifier(tableName, schema: schemaName, database: catalogName)) AS \(db.dialect.tableIdentifier(alias, schema: nil, database: nil)) LIMIT 1"

		let qs = db.query(sql)
		qs.columns(job) { (columns) -> () in
			qs.close(job)
			callback(columns.use({return PrestoDataset(db: db, fragment: SQLFragment(table: tableName, schema: schemaName, database: catalogName, dialect: db.dialect), columns: $0)}))
		}

	}

	public init(db: PrestoDatabase, fragment: SQLFragment, columns: OrderedSet<Column>) {
		self.db = db
		super.init(fragment: fragment, columns: columns)
	}

	override public  func apply(_ fragment: SQLFragment, resultingColumns: OrderedSet<Column>) -> Dataset {
		return PrestoDataset(db: self.db, fragment: fragment, columns: resultingColumns)
	}

	override public func stream() -> WarpCore.Stream {
		return db.query(self.sql.sqlSelect(nil).sql)
	}

	override public func isCompatibleWith(_ other: SQLDataset) -> Bool {
		/* Presto queries can be combined as long as they are on the same cluster. Here we check whether both are using
		the same coordinating server. */
		if let otherPresto = other as? PrestoDataset {
			return otherPresto.db.url == self.db.url
		}
		return false
	}
}
