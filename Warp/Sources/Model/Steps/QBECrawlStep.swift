import Foundation
import Alamofire
import WarpCore

/** Specifies a particular way of crawling. */
class QBECrawler: NSObject, NSSecureCoding {
	var targetBodyColumn: Column? = nil
	var targetStatusColumn: Column? = nil
	var targetErrorColumn: Column? = nil
	var targetResponseTimeColumn: Column? = nil
	var urlExpression: Expression
	var maxConcurrentRequests: Int = 50
	var maxRequestsPerSecond: Int? = 256
	
	init(urlExpression: Expression) {
		self.urlExpression = urlExpression
	}
	
	func encode(with coder: NSCoder) {
		coder.encode(urlExpression, forKey: "url")
		coder.encode(targetBodyColumn?.name, forKey: "bodyColumn")
		coder.encode(targetStatusColumn?.name, forKey: "statusColumn")
		coder.encode(targetResponseTimeColumn?.name, forKey: "responseTimeColumn")
		coder.encode(targetErrorColumn?.name, forKey: "errorColumn")
		coder.encode(maxConcurrentRequests, forKey: "maxConcurrentRequests")
		coder.encode(maxRequestsPerSecond ?? -1, forKey: "maxRequestsPerSecond")
	}
	
	required init?(coder: NSCoder) {
		let urlExpression = coder.decodeObject(of: Expression.self, forKey: "url")
		let targetBodyColumn = coder.decodeObject(of: NSString.self, forKey: "bodyColumn") as? String
		let targetStatusColumn = coder.decodeObject(of: NSString.self, forKey: "statusColumn") as? String
		let targetResponseTimeColumn = coder.decodeObject(of: NSString.self, forKey: "responseTimeColumn") as? String
		let targetErrorColumn = coder.decodeObject(of: NSString.self, forKey: "errorColumn") as? String
		
		self.maxConcurrentRequests = coder.decodeInteger(forKey: "maxConcurrentRequests")
		self.maxRequestsPerSecond = coder.decodeInteger(forKey: "maxRequestsPerSecond")
		if self.maxRequestsPerSecond < 1 {
			self.maxRequestsPerSecond = nil
		}
		
		if self.maxConcurrentRequests < 1 {
			self.maxConcurrentRequests = 50
		}
		
		self.urlExpression = urlExpression ?? Literal(Value(""))
		self.targetBodyColumn = targetBodyColumn != nil ? Column(targetBodyColumn!) : nil
		self.targetStatusColumn = targetStatusColumn != nil ? Column(targetStatusColumn!) : nil
		self.targetResponseTimeColumn = targetResponseTimeColumn != nil ? Column(targetResponseTimeColumn!) : nil
		self.targetErrorColumn = targetErrorColumn != nil ? Column(targetErrorColumn!) : nil
	}
	
	static var supportsSecureCoding: Bool = true
}

class QBECrawlStream: WarpCore.Stream {
	let source: WarpCore.Stream
	var sourceColumnNames: Future<Fallible<[Column]>>
	let crawler: QBECrawler
	
	init(source: WarpCore.Stream, crawler: QBECrawler) {
		self.source = source
		self.sourceColumnNames = Future({(j, cb) in source.columns(j, callback: cb) })
		self.crawler = crawler
	}
	
	func columns(_ job: Job, callback: (Fallible<[Column]>) -> ()) {
		self.sourceColumnNames.get(job) { (sourceColumns) in
			callback(sourceColumns.use({ (sourceColumns) -> [Column] in
				var sourceColumns = sourceColumns

				// Add the column in which we're writing the result
				if let tbody = self.crawler.targetBodyColumn {
					if !sourceColumns.contains(tbody) {
						sourceColumns.append(tbody)
					}
				}
				
				if let tstat = self.crawler.targetStatusColumn {
					if !sourceColumns.contains(tstat) {
						sourceColumns.append(tstat)
					}
				}
				
				if let terr = self.crawler.targetErrorColumn {
					if !sourceColumns.contains(terr) {
						sourceColumns.append(terr)
					}
				}
				
				if let tres = self.crawler.targetResponseTimeColumn {
					if !sourceColumns.contains(tres) {
						sourceColumns.append(tres)
					}
				}
				
				return sourceColumns
			}))
		}
	}
	
	func fetch(_ job: Job, consumer: Sink) {
		// First obtain the column names from the source stream
		self.sourceColumnNames.get(job) { (sourceColumnsFallible) in
			switch sourceColumnsFallible {
				case .success(let sourceColumns):
				// Fetch a bunch of rows
				self.source.fetch(job) { (rows, hasMore) -> () in
					switch rows {
					case .success(let rows):
						var outRows: [Tuple] = []
						
						Array(rows).eachConcurrently(self.crawler.maxConcurrentRequests, maxPerSecond: self.crawler.maxRequestsPerSecond, each: { (tuple, callback) -> () in
							// Check if we should continue
							if job.isCancelled {
								callback()
								return
							}
							
							job.async {
								// Find out what URL we need to fetch
								var row = Row(tuple, columns: sourceColumns)
								if let urlString = self.crawler.urlExpression.apply(row, foreign: nil, inputValue: nil).stringValue, let url = URL(string: urlString) {
									let request = NSMutableURLRequest(url: url)
									// TODO: make configurable
									request.httpMethod = "GET"
									request.cachePolicy = .returnCacheDataElseLoad
									
									let startTime = CFAbsoluteTimeGetCurrent()
									Alamofire.request(request as URLRequest).responseString(encoding: String.Encoding.utf8) { response in
										let data = response.result.value

										let duration = CFAbsoluteTimeGetCurrent() - startTime
										
										// Store results in the row
										if let bodyColumn = self.crawler.targetBodyColumn {
											row.setValue(data != nil ? Value(data!) : Value.invalid, forColumn: bodyColumn)
										}
										
										if let statusColumn = self.crawler.targetStatusColumn {
											row.setValue(response.response != nil ? Value(response.response!.statusCode) : Value.invalid, forColumn: statusColumn)
										}
										
										if let errorColumn = self.crawler.targetErrorColumn {
											row.setValue(response.result.isFailure ? Value("\(response.result.error!)") : Value.empty, forColumn: errorColumn)
										}
										
										if let timeColumn = self.crawler.targetResponseTimeColumn {
											row.setValue(Value(duration), forColumn: timeColumn)
										}
										
										asyncMain {
											outRows.append(row.values)
											callback()
										}
									}
								}
								else {
									// Invalid URL
									if let bodyColumn = self.crawler.targetBodyColumn {
										row.setValue(Value.invalid, forColumn: bodyColumn)
									}
									
									if let statusColumn = self.crawler.targetStatusColumn {
										row.setValue(Value.invalid, forColumn: statusColumn)
									}
									
									if let errorColumn = self.crawler.targetErrorColumn {
										row.setValue(Value("Invalid URL"), forColumn: errorColumn)
									}
									
									if let timeColumn = self.crawler.targetResponseTimeColumn {
										row.setValue(Value.invalid, forColumn: timeColumn)
									}

									
									asyncMain {
										outRows.append(row.values)
										callback()
									}
								}
							}
						}, completion: {
							consumer(.success(Array<Tuple>(outRows)), hasMore)
						})
						
					case .failure(let e):
						consumer(.failure(e), hasMore)
					}
				}
				
				case .failure(let e):
					consumer(.failure(e), .finished)
			}
		}
	}

	func clone() -> WarpCore.Stream {
		return QBECrawlStream(source: source.clone(), crawler: crawler)
	}
}

extension Dataset {
	func crawl(_ crawler: QBECrawler) -> Dataset {
		return StreamDataset(source: QBECrawlStream(source: self.stream(), crawler: crawler))
	}
}

class QBECrawlStep: QBEStep {
	var crawler: QBECrawler
	
	required init(coder aDecoder: NSCoder) {
		if let c = aDecoder.decodeObject(of: QBECrawler.self, forKey: "crawler") {
			self.crawler = c
		}
		else {
			self.crawler = QBECrawler(urlExpression: Literal(Value("http://localhost")))
		}
		super.init(coder: aDecoder)
	}
	
	override init(previous: QBEStep?) {
		self.crawler = QBECrawler(urlExpression: Literal(Value("http://localhost")))
		self.crawler.targetBodyColumn = Column(NSLocalizedString("Result", comment: ""))
		super.init(previous: previous)
	}

	required init() {
		self.crawler = QBECrawler(urlExpression: Literal(Value("http://localhost")))
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("For each row, fetch the web page at [#]", comment: ""),
			QBESentenceFormula(expression: self.crawler.urlExpression, locale: locale, callback: { [weak self] (newExpression) -> () in
				self?.crawler.urlExpression = newExpression
			}, contextCallback: self.contextCallbackForFormulaSentence)
		)
	}
	
	override func encode(with coder: NSCoder) {
		coder.encode(self.crawler, forKey: "crawler")
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.crawl(crawler)))
	}
}
