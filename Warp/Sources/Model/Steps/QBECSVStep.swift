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

class QBECSVWriter: NSObject, QBEFileWriter, StreamDelegate {
	var separatorCharacter: UInt16
	var newLineCharacter: String
	var title: String?

	class var fileTypes: Set<String> { get { return Set<String>(["csv", "tsv", "tab", "txt"]) } }

	required init(locale: Language, title: String?) {
		self.newLineCharacter = locale.csvLineSeparator
		self.separatorCharacter = locale.csvFieldSeparator.utf16[locale.csvFieldSeparator.utf16.startIndex]
		self.title = title
	}

	required init?(coder aDecoder: NSCoder) {
		self.newLineCharacter = aDecoder.decodeString(forKey:"newLine") ?? "\r\n"
		let separatorString = aDecoder.decodeString(forKey:"separator") ?? ","
		separatorCharacter = separatorString.utf16[separatorString.utf16.startIndex]
		self.title = aDecoder.decodeString(forKey:"title")
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encodeString(self.newLineCharacter, forKey: "newLine")
		aCoder.encodeString(String(Character(UnicodeScalar(separatorCharacter)!)), forKey: "separator")
	}

	func sentence(_ locale: Language) -> QBESentence? {
		return QBESentence(format: NSLocalizedString("fields separated by [#]", comment: ""),
			QBESentenceDynamicOptionsToken(value: String(Character(UnicodeScalar(separatorCharacter)!)), provider: { (pc) -> () in
				pc(.success(locale.commonFieldSeparators))
			},
			callback: { (newValue) -> () in
				self.separatorCharacter = newValue.utf16[newValue.utf16.startIndex]
			})
		)
	}

	class func explain(_ fileExtension: String, locale: Language) -> String {
		switch fileExtension {
			case "csv", "txt":
				return NSLocalizedString("Comma separated values", comment: "")

			case "tsv", "tab":
				return NSLocalizedString("Tab separated values", comment: "")

			default:
				return NSLocalizedString("Comma separated values", comment: "")
		}
	}

	internal func writeDataset(_ data: Dataset, toStream: OutputStream, locale: Language, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		let stream = data.stream()
		if let csvOut = CHCSVWriter(outputStream: toStream, encoding: String.Encoding.utf8.rawValue, delimiter: separatorCharacter) {
			csvOut.newlineCharacter = self.newLineCharacter

			// Write column headers
			stream.columns(job) { (columns) -> () in
				switch columns {
				case .success(let cns):
					for col in cns {
						csvOut.writeField(col.name)
					}
					csvOut.finishLine()

					let csvOutMutex = Mutex()

					var cb: Sink? = nil
					cb = { (rows: Fallible<Array<Tuple>>, streamStatus: StreamStatus) -> () in
						switch rows {
						case .success(let rs):
							// We want the next row, so fetch it while we start writing this one.
							if streamStatus == .hasMore {
								job.async {
									stream.fetch(job, consumer: cb!)
								}
							}

							job.time("Write CSV", items: rs.count, itemType: "rows") {
								csvOutMutex.locked {
									for row in rs {
										for cell in row {
											csvOut.writeField(locale.localStringFor(cell))
										}
										csvOut.finishLine()
									}
								}
							}

							if streamStatus == .finished {
								callback(.success())
							}

						case .failure(let e):
							callback(.failure(e))
						}
					}

					stream.fetch(job, consumer: cb!)

				case .failure(let e):
					callback(.failure(e))
				}
			}
		}
	}

	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		if let outStream = OutputStream(toFileAtPath: file.path, append: false) {
			outStream.open()
			self.writeDataset(data, toStream: outStream, locale: locale, job: job, callback: { (result) in
				outStream.close()
				callback(result)
			})
		}
		else {
			callback(.failure("Could not create output stream"))
		}
	}
}

class QBEHTMLWriter: QBECSVWriter {
	override class var fileTypes: Set<String> { get { return Set<String>(["html", "htm"]) } }

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}

	required init(locale: Language, title: String?) {
		let locale = Language()
		locale.numberFormatter.perMillSymbol = ""
		locale.numberFormatter.decimalSeparator = "."
		locale.csvFieldSeparator = ","
		super.init(locale: locale, title: title)
	}

	override class func explain(_ fileExtension: String, locale: Language) -> String {
		return NSLocalizedString("Interactive pivot table", comment: "")
	}

	override func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		if let outStream = OutputStream(toFileAtPath: file.path, append: false) {
			// Get pivot template from resources
			if let path = Bundle.main.path(forResource: "pivot", ofType: "html") {
				outStream.open()
				do {
					let template = try NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue).replacingOccurrences(of: "$$$TITLE$$$", with: title ?? "")
					let parts = template.components(separatedBy: "$$$CSV$$$")
					let header = parts[0]
					let footer = parts[1]

					if let headerData = header.data(using: String.Encoding.utf8) {
						headerData.withUnsafeBytes { (b: UnsafePointer<UInt8>) in
							outStream.write(b, maxLength: headerData.count)
							super.writeDataset(data, toStream: outStream, locale: locale, job: job, callback: { (result) -> () in
								switch result {
								case .success:
									if let footerData = footer.data(using: String.Encoding.utf8) {
										footerData.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Void in
											outStream.write(bytes, maxLength: footerData.count)
											outStream.close()
										}
										callback(.success())
										return
									}
									else {
										callback(.failure("Could not convert footer to UTF-8 data"))
									}

								case .failure(let e):
									outStream.close()
									callback(.failure(e))
								}
							})
						}
					}
					else {
						outStream.close()
						callback(.failure("Could not convert header to UTF-8 data"))
					}
				}
				catch let e as NSError {
					outStream.close()
					callback(.failure(e.localizedDescription))
				}
			}
			else {
				callback(.failure("Could not find template"))
			}
		}
		else {
			callback(.failure("Could not create output stream"))
		}
	}
}

class QBECSVSourceStep: QBEStep {
	var file: QBEFileReference? = nil
	var fieldSeparator: unichar
	var interpretLanguage: Language.LanguageIdentifier? = nil
	var hasHeaders: Bool = true

	required init() {
		let defaultSeparator = QBESettings.sharedInstance.defaultFieldSeparator
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		super.init()
	}
	
	init(url: URL) {
		let defaultSeparator = QBESettings.sharedInstance.defaultFieldSeparator
		self.file = QBEFileReference.absolute(url)
		self.fieldSeparator = defaultSeparator.utf16[defaultSeparator.utf16.startIndex]
		self.hasHeaders = true
		self.interpretLanguage = nil
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObject(forKey: "fileBookmark") as? Data
		let u = aDecoder.decodeObject(forKey: "fileURL") as? URL
		self.file = QBEFileReference.create(u, d)
		
		let separator = (aDecoder.decodeObject(forKey: "fieldSeparator") as? String) ?? ";"
		self.fieldSeparator = separator.utf16[separator.utf16.startIndex]
		self.hasHeaders = aDecoder.decodeBool(forKey: "hasHeaders")
		self.interpretLanguage = aDecoder.decodeObject(forKey: "interpretLanguage") as? Language.LanguageIdentifier
		super.init(coder: aDecoder)
	}
	
	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}
	
	private func sourceDataset() -> Fallible<Dataset> {
		if let url = file?.url {
			let locale: Language? = (interpretLanguage != nil) ? Language(language: interpretLanguage!) : nil
			let s = CSVStream(url: url as URL, fieldSeparator: fieldSeparator, hasHeaders: hasHeaders, locale: locale)
			return .success(StreamDataset(source: s))
		}
		else {
			return .failure(NSLocalizedString("The location of the CSV source file is invalid.", comment: ""))
		}
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(sourceDataset())
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(sourceDataset().use{ $0.limit(maxInputRows) })
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		
		let separator = String(Character(UnicodeScalar(fieldSeparator)!))
		coder.encode(separator, forKey: "fieldSeparator")
		coder.encode(hasHeaders, forKey: "hasHeaders")
		coder.encode(self.file?.url, forKey: "fileURL")
		coder.encode(self.file?.bookmark, forKey: "fileBookmark")
		coder.encode(self.interpretLanguage, forKey: "intepretLanguage")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let fileTypes = [
			"public.comma-separated-values-text",
			"public.delimited-values-text",
			"public.tab-separated-values-text",
			"public.text",
			"public.plain-text"
		]

		return QBESentence(format: NSLocalizedString("Read CSV file [#]", comment: ""),
			QBESentenceFileToken(file: self.file, allowedFileTypes: fileTypes, callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}
	
	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}
	
	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
		if let b = self.file?.url?.startAccessingSecurityScopedResource(), !b {
			trace("startAccessingSecurityScopedResource for \(atURL) failed")
		}
	}
}
