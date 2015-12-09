import Foundation
import WarpCore

class QBESequencerStep: QBEStep {
	var pattern: String
	var column: Column
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeString(pattern, forKey: "pattern")
		coder.encodeString(column.name, forKey: "columnName")
	}
	
	required init(coder aDecoder: NSCoder) {
		pattern = aDecoder.decodeStringForKey("pattern") ?? ""
		column = Column(aDecoder.decodeStringForKey("columnName") ?? "")
		super.init(coder: aDecoder)
	}
	
	init(pattern: String, column: Column) {
		self.pattern = pattern
		self.column = column
		super.init()
	}

	required init() {
	    self.pattern = ""
		self.column = Column(NSLocalizedString("Pattern", comment: ""))
		super.init()
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		let sequencer = Sequencer(self.pattern)

		return QBESentence(format: String(format: NSLocalizedString("Generate a sequence using pattern [#] (for example: '%@') and place it in column [#]", comment: ""), locale.localStringFor(sequencer?.randomValue ?? Value.InvalidValue)),
			QBESentenceTextInput(value: self.pattern, callback: { [weak self] (pattern) -> (Bool) in
				self?.pattern = pattern
				return true
			}),
			QBESentenceTextInput(value: self.column.name, callback: { [weak self] (name) -> (Bool) in
				if !name.isEmpty {
					self?.column = Column(name)
					return true
				}
				return false
			})
		)
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let sequencer = Sequencer(self.pattern) {
			callback(.Success(StreamData(source: sequencer.stream(self.column))))
		}
	}
	
	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		self.fullData(job) { (fd) -> () in
			callback(fd.use { (fullData) in
				return fullData.limit(maxInputRows)
			})
		}
	}
}