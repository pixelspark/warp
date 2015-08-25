import Foundation
import Alamofire

/** Specifies a particular way of crawling. */
class QBECrawler: NSObject, NSSecureCoding {
	var targetBodyColumn: QBEColumn? = nil
	var targetStatusColumn: QBEColumn? = nil
	var targetErrorColumn: QBEColumn? = nil
	var targetResponseTimeColumn: QBEColumn? = nil
	var urlExpression: QBEExpression
	var maxConcurrentRequests: Int = 50
	var maxRequestsPerSecond: Int? = 256
	
	init(urlExpression: QBEExpression) {
		self.urlExpression = urlExpression
	}
	
	func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(urlExpression, forKey: "url")
		coder.encodeObject(targetBodyColumn?.name, forKey: "bodyColumn")
		coder.encodeObject(targetStatusColumn?.name, forKey: "statusColumn")
		coder.encodeObject(targetResponseTimeColumn?.name, forKey: "responseTimeColumn")
		coder.encodeObject(targetErrorColumn?.name, forKey: "errorColumn")
		coder.encodeInteger(maxConcurrentRequests, forKey: "maxConcurrentRequests")
		coder.encodeInteger(maxRequestsPerSecond ?? -1, forKey: "maxRequestsPerSecond")
	}
	
	required init?(coder: NSCoder) {
		let urlExpression = coder.decodeObjectOfClass(QBEExpression.self, forKey: "url")
		let targetBodyColumn = coder.decodeObjectOfClass(NSString.self, forKey: "bodyColumn") as? String
		let targetStatusColumn = coder.decodeObjectOfClass(NSString.self, forKey: "statusColumn") as? String
		let targetResponseTimeColumn = coder.decodeObjectOfClass(NSString.self, forKey: "responseTimeColumn") as? String
		let targetErrorColumn = coder.decodeObjectOfClass(NSString.self, forKey: "errorColumn") as? String
		
		self.maxConcurrentRequests = coder.decodeIntegerForKey("maxConcurrentRequests")
		self.maxRequestsPerSecond = coder.decodeIntegerForKey("maxRequestsPerSecond")
		if self.maxRequestsPerSecond < 1 {
			self.maxRequestsPerSecond = nil
		}
		
		if self.maxConcurrentRequests < 1 {
			self.maxConcurrentRequests = 50
		}
		
		self.urlExpression = urlExpression ?? QBELiteralExpression(QBEValue(""))
		self.targetBodyColumn = targetBodyColumn != nil ? QBEColumn(targetBodyColumn!) : nil
		self.targetStatusColumn = targetStatusColumn != nil ? QBEColumn(targetStatusColumn!) : nil
		self.targetResponseTimeColumn = targetResponseTimeColumn != nil ? QBEColumn(targetResponseTimeColumn!) : nil
		self.targetErrorColumn = targetErrorColumn != nil ? QBEColumn(targetErrorColumn!) : nil
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
}

class QBECrawlStream: QBEStream {
	let source: QBEStream
	var sourceColumnNames: QBEFuture<QBEFallible<[QBEColumn]>>
	let crawler: QBECrawler
	
	init(source: QBEStream, crawler: QBECrawler) {
		self.source = source
		self.sourceColumnNames = QBEFuture({(j, cb) in source.columnNames(j, callback: cb) })
		self.crawler = crawler
	}
	
	func columnNames(job: QBEJob, callback: (QBEFallible<[QBEColumn]>) -> ()) {
		self.sourceColumnNames.get { (sourceColumns) in
			callback(sourceColumns.use({ (var sourceColumns) -> [QBEColumn] in
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
	
	func fetch(job: QBEJob, consumer: QBESink) {
		// First obtain the column names from the source stream
		self.sourceColumnNames.get { (sourceColumnsFallible) in
			switch sourceColumnsFallible {
				case .Success(let sourceColumns):
				// Fetch a bunch of rows
				self.source.fetch(job) { (rows, hasMore) -> () in
					switch rows {
					case .Success(let rows):
						var outRows: [QBETuple] = []
						
						Array(rows).eachConcurrently(maxConcurrent: self.crawler.maxConcurrentRequests, maxPerSecond: self.crawler.maxRequestsPerSecond, each: { (tuple, callback) -> () in
							// Check if we should continue
							if job.cancelled {
								callback()
								return
							}
							
							job.async {
								// Find out what URL we need to fetch
								var row = QBERow(tuple, columnNames: sourceColumns)
								if let urlString = self.crawler.urlExpression.apply(row, foreign: nil, inputValue: nil).stringValue, url = NSURL(string: urlString) {
									let request = NSMutableURLRequest(URL: url)
									// TODO: make configurable
									request.HTTPMethod = "GET"
									request.cachePolicy = .ReturnCacheDataElseLoad
									
									let startTime = CFAbsoluteTimeGetCurrent()
									Alamofire.request(request).responseString(encoding: NSUTF8StringEncoding) { (request, response, result) -> Void in
										let data = result.value
										let duration = CFAbsoluteTimeGetCurrent() - startTime
										
										// Store results in the row
										if let bodyColumn = self.crawler.targetBodyColumn {
											row.setValue(data != nil ? QBEValue(data!) : QBEValue.InvalidValue, forColumn: bodyColumn)
										}
										
										if let statusColumn = self.crawler.targetStatusColumn {
											row.setValue(response != nil ? QBEValue(response!.statusCode) : QBEValue.InvalidValue, forColumn: statusColumn)
										}
										
										if let errorColumn = self.crawler.targetErrorColumn {
											row.setValue(result.isFailure ? QBEValue("\(result.error!)") : QBEValue.EmptyValue, forColumn: errorColumn)
										}
										
										if let timeColumn = self.crawler.targetResponseTimeColumn {
											row.setValue(QBEValue(duration), forColumn: timeColumn)
										}
										
										QBEAsyncMain {
											outRows.append(row.values)
											callback()
										}
									}
								}
								else {
									// Invalid URL
									if let bodyColumn = self.crawler.targetBodyColumn {
										row.setValue(QBEValue.InvalidValue, forColumn: bodyColumn)
									}
									
									if let statusColumn = self.crawler.targetStatusColumn {
										row.setValue(QBEValue.InvalidValue, forColumn: statusColumn)
									}
									
									if let errorColumn = self.crawler.targetErrorColumn {
										row.setValue(QBEValue("Invalid URL"), forColumn: errorColumn)
									}
									
									if let timeColumn = self.crawler.targetResponseTimeColumn {
										row.setValue(QBEValue.InvalidValue, forColumn: timeColumn)
									}

									
									QBEAsyncMain {
										outRows.append(row.values)
										callback()
									}
								}
							}
						}, completion: {
							consumer(.Success(ArraySlice<QBETuple>(outRows)), hasMore)
						})
						
					case .Failure(let e):
						consumer(.Failure(e), hasMore)
					}
				}
				
				case .Failure(let e):
					consumer(.Failure(e), false)
			}
		}
	}

	func clone() -> QBEStream {
		return QBECrawlStream(source: source, crawler: crawler)
	}
}

extension QBEData {
	func crawl(crawler: QBECrawler) -> QBEData {
		return QBEStreamData(source: QBECrawlStream(source: self.stream(), crawler: crawler))
	}
}

class QBECrawlStep: QBEStep {
	var crawler: QBECrawler
	
	required init(coder aDecoder: NSCoder) {
		if let c = aDecoder.decodeObjectOfClass(QBECrawler.self, forKey: "crawler") {
			self.crawler = c
		}
		else {
			self.crawler = QBECrawler(urlExpression: QBELiteralExpression(QBEValue("http://localhost")))
		}
		super.init(coder: aDecoder)
	}
	
	override init(previous: QBEStep?) {
		self.crawler = QBECrawler(urlExpression: QBELiteralExpression(QBEValue("http://localhost")))
		self.crawler.targetBodyColumn = QBEColumn(NSLocalizedString("Result", comment: ""))
		super.init(previous: previous)
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence(format: NSLocalizedString("For each row, fetch the web page at [#]", comment: ""),
			QBESentenceFormula(expression: self.crawler.urlExpression, locale: locale, callback: { [weak self] (newExpression) -> () in
				self?.crawler.urlExpression = newExpression
			})
		)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.crawler, forKey: "crawler")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(data.crawl(crawler)))
	}
}