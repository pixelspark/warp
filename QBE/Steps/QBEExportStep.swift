import Foundation
import WarpCore

class QBEExportStep: QBEStep {
	private(set) var writer: QBEFileWriter? = nil
	private(set) var file: QBEFileReference? = nil

	init(previous: QBEStep?, writer: QBEFileWriter, file: QBEFileReference) {
		super.init(previous: previous)
		self.writer = writer
		self.file = file
	}

	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.writer, forKey: "writer")
		super.encodeWithCoder(coder)
	}

	required init(coder aDecoder: NSCoder) {
		self.writer = aDecoder.decodeObjectForKey("writer") as? QBEFileWriter
		super.init(coder: aDecoder)
	}

	override func willSaveToDocument(atURL: NSURL) {
		self.file = self.file?.bookmark(atURL)
	}

	override func didLoadFromDocument(atURL: NSURL) {
		self.file = self.file?.resolve(atURL)
	}

	func write(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		super.fullData(job) { (fallibleData) -> () in
			switch fallibleData {
			case .Success(let data):
				if let w = self.writer, let url = self.file?.url {
					job.async {
						w.writeData(data, toFile: url, locale: QBELocale(), job: job, callback: { (result) -> () in
							switch result {
							case .Success:
								callback(.Success(data))

							case .Failure(let e):
								callback(.Failure(e))
							}
						})
					}
				}
				else {
					callback(.Failure("Export is configured incorrectly, or not file to export to"))
				}

			case .Failure(let e):
				callback(.Failure(e))
			}
		}
	}

	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		self.write(job, callback: callback)
	}

	override func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		return callback(.Success(data))
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		let factory = QBEFactory.sharedInstance

		var options: [String: String] = [:]
		var currentKey: String = ""
		for writer in factory.fileWriters {
			if let ext = writer.fileTypes.first {
				let allExtensions = writer.fileTypes.joinWithSeparator(", ")
				options[ext] = "\(writer.explain(ext, locale: locale)) (\(allExtensions.uppercaseString))"
				if writer == self.writer?.dynamicType {
					currentKey = ext
				}
			}
		}

		let s = QBESentence(format: NSLocalizedString("Export data as [#] to [#]", comment: ""),
			QBESentenceOptions(options: options, value: currentKey, callback: { [weak self] (newKey) -> () in
				if let newType = factory.fileWriterForType(newKey) {
					self?.writer = newType.init(locale: locale, title: "")
				}
			}),

			QBESentenceFile(saveFile: self.file, allowedFileTypes: Array(factory.fileExtensionsForWriting), callback: { [weak self] (newFile) -> () in
				self?.file = newFile
				if let url = newFile.url, let fileExtension = url.pathExtension, let w = self?.writer where !w.dynamicType.fileTypes.contains(fileExtension) {
					if let newWriter = factory.fileWriterForType(fileExtension) {
						self?.writer = newWriter.init(locale: locale, title: "")
					}
				}
			})
		)

		if let writerSentence = self.writer?.sentence(locale) {
			s.append(writerSentence)
		}
		return s
	}
}