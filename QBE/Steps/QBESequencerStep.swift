import Foundation
import WarpCore

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

	override func sentence(locale: QBELocale) -> QBESentence {
		let sequencer = QBESequencer(self.pattern)

		return QBESentence(format: String(format: NSLocalizedString("Generate a sequence using pattern [#] (for example: '%@') and place it in column [#]", comment: ""), locale.localStringFor(sequencer?.randomValue ?? QBEValue.InvalidValue)),
			QBESentenceTextInput(value: self.pattern, callback: { [weak self] (pattern) -> (Bool) in
				self?.pattern = pattern
				return true
			}),
			QBESentenceTextInput(value: self.column.name, callback: { [weak self] (name) -> (Bool) in
				if !name.isEmpty {
					self?.column = QBEColumn(name)
					return true
				}
				return false
			})
		)
	}
	
	override func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let sequencer = QBESequencer(self.pattern) {
			callback(.Success(QBEStreamData(source: sequencer.stream(self.column))))
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