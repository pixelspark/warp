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

	override func encode(with coder: NSCoder) {
		coder.encode(self.writer, forKey: "writer")
		super.encode(with: coder)
	}

	required init(coder aDecoder: NSCoder) {
		self.writer = aDecoder.decodeObject(forKey: "writer") as? QBEFileWriter
		super.init(coder: aDecoder)
	}

	required init() {
		writer = nil
		file = nil
		super.init()
	}

	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}

	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
	}

	func write(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		super.fullDataset(job) { (fallibleDataset) -> () in
			switch fallibleDataset {
			case .success(let data):
				if let w = self.writer, let url = self.file?.url {
					job.async {
						w.writeDataset(data, toFile: url, locale: Language(), job: job, callback: { (result) -> () in
							switch result {
							case .success:
								callback(.success(data))

							case .failure(let e):
								callback(.failure(e))
							}
						})
					}
				}
				else {
					callback(.failure("Export is configured incorrectly, or not file to export to"))
				}

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.write(job, callback: callback)
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		return callback(.success(data))
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let factory = QBEFactory.sharedInstance

		var options: [String: String] = [:]
		var currentKey: String = ""
		for writer in factory.fileWriters {
			if let ext = writer.fileTypes.first {
				let allExtensions = writer.fileTypes.joined(separator: ", ")
				options[ext] = "\(writer.explain(ext, locale: locale)) (\(allExtensions.uppercased()))"
				if writer == type(of: self.writer) {
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
				if let url = newFile.url {
					let fileExtension = url.pathExtension
					if let w = self?.writer, !type(of: w).fileTypes.contains(fileExtension) {
						if let newWriter = factory.fileWriterForType(fileExtension) {
							self?.writer = newWriter.init(locale: locale, title: "")
						}
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
