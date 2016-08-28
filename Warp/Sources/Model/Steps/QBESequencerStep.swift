import Foundation
import WarpCore

enum QBESequencerType {
	case pattern(pattern: String)
	case range(from: Int, to: Int)

	var typeName: String {
		switch self {
		case .pattern(pattern: _): return "pattern"
		case .range(from: _, to: _): return "range"
		}
	}
}

class QBESequencerStep: QBEStep {
	var type: QBESequencerType
	var column: Column

	static let examplePattern = "[A-Z]{2}"
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)

		switch self.type {
		case .pattern(pattern: let pattern):
			coder.encodeString("pattern", forKey: "type")
			coder.encodeString(pattern, forKey: "pattern")

		case .range(from: let from, to: let to):
			coder.encodeString("range", forKey: "type")
			coder.encode(from, forKey: "from")
			coder.encode(to, forKey: "to")
		}

		coder.encodeString(column.name, forKey: "columnName")
	}
	
	required init(coder aDecoder: NSCoder) {
		let type = aDecoder.decodeString(forKey:"type") ?? "pattern"

		if type == "pattern" {
			self.type = .pattern(
				pattern: aDecoder.decodeString(forKey:"pattern") ?? ""
			)
		}
		else if type == "range" {
			self.type = .range(
				from: aDecoder.decodeInteger(forKey: "from"),
				to: aDecoder.decodeInteger(forKey: "to")
			)
		}
		else {
			self.type = .pattern(pattern: "")
		}

		column = Column(aDecoder.decodeString(forKey:"columnName") ?? "")
		super.init(coder: aDecoder)
	}
	
	init(pattern: String, column: Column) {
		self.type = .pattern(pattern: pattern)
		self.column = column
		super.init()
	}

	required init() {
		self.type = .range(from: 0, to: 100)
		self.column = Column(NSLocalizedString("Value", comment: ""))
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let columnItem = QBESentenceTextToken(value: self.column.name, callback: { [weak self] (name) -> (Bool) in
			if !name.isEmpty {
				self?.column = Column(name)
				return true
			}
			return false
		})

		let typeItem = QBESentenceOptionsToken(options: ["pattern": "using pattern".localized, "range": "of numbers".localized], value: self.type.typeName) { (newType) in
			if newType != self.type.typeName {
				if newType == "pattern" {
					self.type = .pattern(pattern: QBESequencerStep.examplePattern)
				}
				else if newType == "range" {
					self.type = .range(from: 0, to: 100)
				}
			}
		}

		switch self.type {
		case .pattern(pattern: let pattern):
			let sequencer = Sequencer(pattern)
			let text = String(format: NSLocalizedString("Generate a sequence [#] [#] (for example: '%@') and place it in column [#]", comment: ""), locale.localStringFor(sequencer?.randomValue ?? Value.invalid))

			return QBESentence(format: text,
			   typeItem,
			   QBESentenceTextToken(value: pattern, callback: { [weak self] (pattern) -> (Bool) in
					self?.type = .pattern(pattern: pattern)
					return true
				}),
			   columnItem
			)

		case .range(from: let from, to: let to):
			let text = "Generate a sequence [#] between [#] and [#] and place it in column [#]".localized

			return QBESentence(format: text,
				typeItem,
				QBESentenceTextToken(value: "\(from)", callback: { [weak self] (fromString) -> (Bool) in
					if let fromInt = Int(fromString) {
						var newTo = to
						if fromInt >= to {
							newTo = fromInt + abs(to - from)
						}
						self?.type = .range(from: fromInt, to: newTo)
						return true
					}
					return false
				}),
				QBESentenceTextToken(value: "\(to)", callback: { [weak self] (toString) -> (Bool) in
					if let toInt = Int(toString) {
						var newFrom = from
						if toInt <= from {
							newFrom = toInt - abs(to - from)
						}
						self?.type = .range(from: newFrom, to: toInt)
						return true
					}
					return false
				}),
				columnItem
			)
		}
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		switch self.type {
		case .pattern(let pattern):
			if let sequencer = Sequencer(pattern) {
				callback(.success(StreamDataset(source: sequencer.stream(self.column))))
			}
			else {
				callback(.failure("The pattern is invalid".localized))
			}

		case .range(from: let from, to: let to):
			if to <= from {
				return callback(.failure("The end number for the sequence must be higher than the start number".localized))
			}
			let seq = (from...to).map { return Fallible.success([Value($0)]) }
			let stream = SequenceStream(AnySequence<Fallible<Tuple>>(seq), columns: [self.column], rowCount: to - from + 1)
			return callback(.success(StreamDataset(source: stream)))
		}
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.fullDataset(job) { (fd) -> () in
			callback(fd.use { (fullDataset) in
				return fullDataset.limit(maxInputRows)
			})
		}
	}
}
