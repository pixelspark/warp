import Foundation

private class QBESequencerRowGenerator: GeneratorType {
	let source: AnyGenerator<QBEValue>
	typealias Element = QBETuple
	
	init(source: AnySequence<QBEValue>) {
		self.source = source.generate()
	}
	
	func next() -> QBETuple? {
		if let n = source.next() {
			return [n]
		}
		return nil
	}
}

class QBESequencerStep: QBEStep {
	var pattern: String
	var column: QBEColumn
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeString(pattern, forKey: "pattern")
		coder.encodeString(column.name, forKey: "columnName")
	}
	
	required init(coder aDecoder: NSCoder) {
		pattern = aDecoder.decodeStringForKey("pattern") ?? ""
		column = QBEColumn(aDecoder.decodeStringForKey("columnName") ?? "")
		super.init(coder: aDecoder)
	}
	
	init(pattern: String, column: QBEColumn) {
		self.pattern = pattern
		self.column = column
		super.init(previous: nil)
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if short {
			return NSLocalizedString("Generate a sequence", comment: "")
		}
		return String(format: NSLocalizedString("Generate a sequence using pattern '%@'", comment: ""), self.pattern)
	}
	
	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let sequencer = QBESequencer(self.pattern), let root = sequencer.root {
			callback(.Success(QBEStreamData(source: QBESequenceStream(AnySequence<QBETuple>({ () -> QBESequencerRowGenerator in
				return QBESequencerRowGenerator(source: root)
			}), columnNames: [self.column]))))
		}
	}
	
	override func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		self.fullData(job) { (fd) -> () in
			callback(fd.use { (fullData) in
				return fullData.limit(maxInputRows)
			})
		}
	}
}