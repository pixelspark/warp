import Foundation
import WarpCore

class QBEXMLWriter: NSObject, QBEFileWriter, NSStreamDelegate {
	class var fileTypes: Set<String> { get { return Set<String>(["xml"]) } }

	var title: String?

	required init(locale: QBELocale, title: String?) {
		self.title = title
	}

	required init?(coder aDecoder: NSCoder) {
		self.title = aDecoder.decodeStringForKey("title")
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeString(self.title ?? "", forKey: "title")
	}

	static func explain(locale: QBELocale) -> String {
		return NSLocalizedString("XML file", comment: "")
	}
	
	func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ()) {
		let stream = data.stream()
		
		if let writer = TCMXMLWriter(options: UInt(TCMXMLWriterOptionPrettyPrinted), fileURL: file) {
			writer.instructXML()
			writer.tag("graph", attributes: ["xmlns": "http://dialogicplatform.com/data/1.0"]) {
				writer.tag("status", contentText: "ok")
				
				writer.tag("meta") {
					writer.tag("generated", contentText: NSDate().iso8601FormattedUTCDate)
					writer.tag("system", contentText: "Warp")
					writer.tag("domain", contentText: NSHost.currentHost().name ?? "localhost")
					writer.tag("input", contentText: "")
				}
				
				writer.tag("details") {
					writer.tag("type", contentText: "multidimensional")
					writer.tag("title", contentText: self.title ?? "")
					writer.tag("source", contentText: "")
					writer.tag("comment", contentText: "")
				}
				
				writer.tag("axes") {
					writer.tag("axis", attributes: ["pos": "X1"]) { writer.text("X") }
					writer.tag("axis", attributes: ["pos": "Y1"]) { writer.text("Y") }
				}
				
				// Fetch column names
				stream.columnNames(job) { (columnNames) -> () in
					switch columnNames {
						case .Success(let cns):
							writer.openTag("grid")
							
							// Write first row with column names
							writer.tag("row") {
								for cn in cns {
									writer.tag("cell", contentText: cn.name)
								}
							}
							
							// Fetch rows in batches and write rows to XML
							var sink: QBESink? = nil
							sink = { (rows: QBEFallible<Array<QBETuple>>, hasMore: Bool) -> () in
								switch rows {
								case .Success(let rs):
									// Write rows
									for row in rs {
										writer.tag("row") {
											for cell in row {
												writer.tag("cell", contentText: cell.stringValue)
											}
										}
									}
									
									if hasMore {
										stream.fetch(job, consumer: sink!)
									}
									else {
										writer.closeLastTag()
										callback(.Success())
									}
									
								case .Failure(let e):
									callback(.Failure(e))
								}
							}
							
							stream.fetch(job, consumer: sink!)
							
						case .Failure(let e):
							callback(.Failure(e))
					}
				}
			}
		}
	}
}