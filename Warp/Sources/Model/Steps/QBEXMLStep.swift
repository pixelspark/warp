/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore
import WarpConduit

class QBEXMLWriter: NSObject, QBEFileWriter, StreamDelegate {
	class var fileTypes: Set<String> { get { return Set<String>(["xml"]) } }

	var title: String?

	required init(locale: Language, title: String?) {
		self.title = title
	}

	required init?(coder aDecoder: NSCoder) {
		self.title = aDecoder.decodeString(forKey:"title")
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encodeString(self.title ?? "", forKey: "title")
	}

	func sentence(_ locale: Language) -> QBESentence? {
		return nil
	}

	static func explain(_ fileExtension: String, locale: Language) -> String {
		return NSLocalizedString("XML", comment: "")
	}
	
	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		let stream = data.stream()
		
		if let writer = TCMXMLWriter(options: UInt(TCMXMLWriterOptionPrettyPrinted), fileURL: file) {
			writer.instructXML()
			writer.tag("graph", attributes: ["xmlns": "http://dialogicplatform.com/data/1.0"]) {
				writer.tag("status", attributes: [:], contentText: "ok")
				
				writer.tag("meta", attributes: [:]) {
					writer.tag("generated", attributes: [:], contentText: Date().iso8601FormattedUTCDate)
					writer.tag("system", attributes: [:], contentText: "Warp")
					writer.tag("domain", attributes: [:], contentText: "")
					writer.tag("input", attributes: [:], contentText: "")
				}
				
				writer.tag("details", attributes: [:]) {
					writer.tag("type", attributes: [:], contentText: "multidimensional")
					writer.tag("title", attributes: [:], contentText: self.title ?? "")
					writer.tag("source", attributes: [:], contentText: "")
					writer.tag("comment", attributes: [:], contentText: "")
				}
				
				writer.tag("axes", attributes: [:]) {
					writer.tag("axis", attributes: ["pos": "X1"]) { writer.text("X") }
					writer.tag("axis", attributes: ["pos": "Y1"]) { writer.text("Y") }
				}
				
				// Fetch column names
				stream.columns(job) { (columns) -> () in
					switch columns {
						case .success(let cns):
							writer.openTag("grid")
							
							// Write first row with column names
							writer.tag("row", attributes: [:]) {
								for cn in cns {
									writer.tag("cell", attributes: [:], contentText: cn.name)
								}
							}
							
							// Fetch rows in batches and write rows to XML
							var sink: Sink? = nil
							sink = { (rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) -> () in
								switch rows {
								case .success(let rs):
									// Write rows
									for row in rs {
										writer.tag("row", attributes: [:]) {
											for cell in row {
												writer.tag("cell", attributes: [:], contentText: cell.stringValue)
											}
										}
									}
									
									if streamStatus == .hasMore {
										job.async {
											stream.fetch(job, consumer: sink!)
										}
									}
									else {
										writer.closeLastTag()
										callback(.success())
									}
									
								case .failure(let e):
									callback(.failure(e))
								}
							}
							
							stream.fetch(job, consumer: sink!)
							
						case .failure(let e):
							callback(.failure(e))
					}
				}
			}
		}
	}
}
