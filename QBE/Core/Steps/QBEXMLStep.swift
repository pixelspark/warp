import Foundation

class QBEXMLWriter: QBEFileWriter, NSStreamDelegate {
	let title: String?
	
	required init(locale: QBELocale, title: String? = nil) {
		self.title = title
		super.init(locale: locale, title: title)
	}
	
	override func writeData(data: QBEData, toFile file: NSURL, job: QBEJob, callback: () -> ()) {
		let stream = data.stream()
		
		if let writer = TCMXMLWriter(options: UInt(TCMXMLWriterOptionPrettyPrinted), fileURL: file) {
			writer.instructXML()
			writer.tag("graph", attributes: ["xmlns": "http://dialogicplatform.com/data/1.0"]) {
				writer.tag("status", contentText: "ok")
				
				writer.tag("meta") {
					writer.tag("generated", contentText: NSDate().iso8601FormattedDate)
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
					writer.openTag("grid")
					
					// Write first row with column names
					writer.tag("row") {
						for cn in columnNames {
							writer.tag("cell", contentText: cn.name)
						}
					}
					
					// Fetch rows in batches and write rows to XML
					var sink: QBESink? = nil
					sink = {[unowned self] (rows: ArraySlice<QBETuple>, hasMore: Bool) -> () in
						// Write rows
						for row in rows {
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
							callback()
						}
					}
					
					stream.fetch(job, consumer: sink!)
				}
			}
		}
	}
}