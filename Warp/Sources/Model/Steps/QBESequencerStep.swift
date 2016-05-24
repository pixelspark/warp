import Foundation
import WarpCore

enum QBESequencerType {
	case Pattern(pattern: String)
	case Range(from: Int, to: Int)

	var typeName: String {
		switch self {
		case .Pattern(pattern: _): return "pattern"
		case .Range(from: _, to: _): return "range"
		}
	}
}

class QBESequencerStep: QBEStep {
	var type: QBESequencerType
	var column: Column

	static let examplePattern = "[A-Z]{2}"
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)

		switch self.type {
		case .Pattern(pattern: let pattern):
			coder.encodeString("pattern", forKey: "type")
			coder.encodeString(pattern, forKey: "pattern")

		case .Range(from: let from, to: let to):
			coder.encodeString("range", forKey: "type")
			coder.encodeInteger(from, forKey: "from")
			coder.encodeInteger(to, forKey: "to")
		}

		coder.encodeString(column.name, forKey: "columnName")
	}
	
	required init(coder aDecoder: NSCoder) {
		let type = aDecoder.decodeStringForKey("type") ?? "pattern"

		if type == "pattern" {
			self.type = .Pattern(
				pattern: aDecoder.decodeStringForKey("pattern") ?? ""
			)
		}
		else if type == "range" {
			self.type = .Range(
				from: aDecoder.decodeIntegerForKey("from"),
				to: aDecoder.decodeIntegerForKey("to")
			)
		}
		else {
			self.type = .Pattern(pattern: "")
		}

		column = Column(aDecoder.decodeStringForKey("columnName") ?? "")
		super.init(coder: aDecoder)
	}
	
	init(pattern: String, column: Column) {
		self.type = .Pattern(pattern: pattern)
		self.column = column
		super.init()
	}

	required init() {
		self.type = .Range(from: 0, to: 100)
		self.column = Column(NSLocalizedString("Value", comment: ""))
		super.init()
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		let columnItem = QBESentenceTextInput(value: self.column.name, callback: { [weak self] (name) -> (Bool) in
			if !name.isEmpty {
				self?.column = Column(name)
				return true
			}
			return false
		})

		let typeItem = QBESentenceOptions(options: ["pattern": "using pattern".localized, "range": "of numbers".localized], value: self.type.typeName) { (newType) in
			if newType != self.type.typeName {
				if newType == "pattern" {
					self.type = .Pattern(pattern: QBESequencerStep.examplePattern)
				}
				else if newType == "range" {
					self.type = .Range(from: 0, to: 100)
				}
			}
		}

		switch self.type {
		case .Pattern(pattern: let pattern):
			let sequencer = Sequencer(pattern)
			let text = String(format: NSLocalizedString("Generate a sequence [#] [#] (for example: '%@') and place it in column [#]", comment: ""), locale.localStringFor(sequencer?.randomValue ?? Value.InvalidValue))

			return QBESentence(format: text,
			   typeItem,
			   QBESentenceTextInput(value: pattern, callback: { [weak self] (pattern) -> (Bool) in
					self?.type = .Pattern(pattern: pattern)
					return true
				}),
			   columnItem
			)

		case .Range(from: let from, to: let to):
			let text = "Generate a sequence [#] between [#] and [#] and place it in column [#]".localized

			return QBESentence(format: text,
				typeItem,
				QBESentenceTextInput(value: "\(from)", callback: { [weak self] (fromString) -> (Bool) in
					if let fromInt = Int(fromString) {
						var newTo = to
						if fromInt >= to {
							newTo = fromInt + abs(to - from)
						}
						self?.type = .Range(from: fromInt, to: newTo)
						return true
					}
					return false
				}),
				QBESentenceTextInput(value: "\(to)", callback: { [weak self] (toString) -> (Bool) in
					if let toInt = Int(toString) {
						var newFrom = from
						if toInt <= from {
							newFrom = toInt - abs(to - from)
						}
						self?.type = .Range(from: newFrom, to: toInt)
						return true
					}
					return false
				}),
				columnItem
			)
		}
	}
	
	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		switch self.type {
		case .Pattern(let pattern):
			if let sequencer = Sequencer(pattern) {
				callback(.Success(StreamData(source: sequencer.stream(self.column))))
			}
			else {
				callback(.Failure("The pattern is invalid".localized))
			}

		case .Range(from: let from, to: let to):
			if to <= from {
				return callback(.Failure("The end number for the sequence must be higher than the start number".localized))
			}
			let seq = (from...to).map { return Fallible.Success([Value($0)]) }
			let stream = SequenceStream(AnySequence<Fallible<Tuple>>(seq), columns: [self.column], rowCount: to - from + 1)
			return callback(.Success(StreamData(source: stream)))
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