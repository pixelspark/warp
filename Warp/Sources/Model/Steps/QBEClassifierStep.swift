import Foundation
import WarpAI
import WarpCore

private extension Value {
	private var floatTag: Float {
		switch self {
		case .InvalidValue: return -1.0
		case .EmptyValue: return 0.0
		case .BoolValue(_): return 1.0
		case .IntValue(_): return 2.0
		case .DoubleValue(_): return 3.0
		case .DateValue(_): return 4.0
		case .StringValue(_): return 5.0
		}
	}

	private func valueToFloats(number: Int) -> [Float] {
		assert(number >= 2)

		switch self {
		case .BoolValue(let b):
			return [self.floatTag] + Array<Float>(count: number-1, repeatedValue: Float(b ? 1.0 : 0.0))

		case .DoubleValue(let d):
			return [self.floatTag] + Array<Float>(count: number-1, repeatedValue: Float(d))

		case .DateValue(let d):
			return [self.floatTag] + Array<Float>(count: number-1, repeatedValue: Float(d))

		case .IntValue(let i):
			return [self.floatTag] + Array<Float>(count: number-1, repeatedValue: Float(i))

		case .EmptyValue, .InvalidValue:
			return [self.floatTag] + Array<Float>(count: number-1, repeatedValue: Float(0.0))

		case .StringValue(let s):
			let p = s.utf16.prefix(number-1).map { a in return Float(a) }
			if p.count < number-1 {
				return [self.floatTag] + p + Array<Float>(count: number - 1 - p.count, repeatedValue: Float(0.0))
			}
			else {
				return [self.floatTag] + p
			}
		}
	}

	private init(floats: [Float]) {
		let typeTag = round(floats.first!)
		switch typeTag {
		case floor(Value.InvalidValue.floatTag):
			self = .InvalidValue

		case floor(Value.EmptyValue.floatTag):
			self = .EmptyValue

		case floor(Value.BoolValue(true).floatTag):
			self = .BoolValue(floats[1] >= 0.5)

		case floor(Value.IntValue(0).floatTag):
			self = .IntValue(lroundf(floats[1]))

		case floor(Value.DateValue(0.0).floatTag):
			self = .DateValue(Double(floats[1]))

		case floor(Value.DoubleValue(0.0).floatTag):
			self = .DoubleValue(Double(floats[1]))

		case floor(Value.StringValue("").floatTag):
			let utf16 = floats.dropFirst().map { return UTF16Char(UInt16($0)) }
			self = .StringValue(String(utf16))

		default:
			self = .InvalidValue
		}

		Swift.print("Value \(floats) => \(self)")
	}
}

private class QBEClassifierStream: Stream {
	let data: Stream
	let training: Stream
	let inputs: [Column]
	let outputs: [Column]

	private let valuesPerColumn = 2
	private let model: FFNN
	private let mutex = Mutex()
	private var trainingFuture: Future<Fallible<()>>! = nil
	private var dataColumnsFuture: Future<Fallible<[Column]>>! = nil

	init(data: Stream, training: Stream, inputs: Set<Column>, outputs: Set<Column>) {
		self.data = data
		self.training = training
		self.inputs = Array(inputs)
		self.outputs = Array(outputs)

		let hiddenNodes = (valuesPerColumn * inputs.count * 2 / 3 ) + outputs.count * valuesPerColumn
		self.model = FFNN(inputs: valuesPerColumn * inputs.count, hidden: hiddenNodes, outputs: outputs.count * valuesPerColumn)

		self.dataColumnsFuture = Future<Fallible<[Column]>>(self.data.columns)

		self.trainingFuture = Future<Fallible<()>>({ [unowned self] job, cb in
			if self.inputs.isEmpty {
				return cb(.Failure("Please make sure there is data to use for classification".localized))
			}

			if self.outputs.isEmpty {
				return cb(.Failure("Please make sure there is a target column for classification".localized))
			}

			// Build a model based on the training data

			training.columns(job) { result in
				switch result {
				case .Success(let trainingCols):
					self.train(job, trainingColumns: trainingCols) { result in
						switch result {
						case .Success():
							return cb(.Success())

						case .Failure(let e):
							return cb(.Failure(e))
						}
					}

				case .Failure(let e):
					return cb(.Failure(e))
				}
			}
		})
	}

	private func valuesForInputRow(row: Row) -> [Float] {
		return self.inputs.flatMap { inputColumn -> [Float] in
			return (row[inputColumn] ?? .InvalidValue).valueToFloats(self.valuesPerColumn)
		}
	}

	private func valuesForOutputRow(row: Row) -> [Float] {
		return self.outputs.flatMap { outputColumn -> [Float] in
			return (row[outputColumn] ?? .InvalidValue).valueToFloats(self.valuesPerColumn)
		}
	}

	private func fetch(job: Job, consumer: Sink) {
		self.trainingFuture.get(job) { result in
			switch result {
			case .Success:
				self.dataColumnsFuture.get(job) { result in
					switch result {
					case .Success(let dataCols):
						self.classify(job, columns: dataCols, consumer: consumer)

					case .Failure(let e):
						return consumer(.Failure(e), .Finished)
					}
				}

			case .Failure(let e):
				return consumer(.Failure(e), .Finished)
			}
		}
	}

	private func classify(job: Job, columns: [Column], consumer: (Fallible<[Tuple]>, StreamStatus) -> ()) {
		self.data.fetch(job) { result, streamStatus in
			switch result {
			case .Success(let tuples):
				do {
					let outTuples = try tuples.map { tuple -> Tuple in
						var outTuple = tuple
						let row = Row(tuple, columns: columns)
						let inputValues = self.valuesForInputRow(row)

						let outputValues = try self.mutex.tryLocked {
							 return try self.model.update(inputs: inputValues)
						}

						for (idx, _) in self.outputs.enumerate() {
							let floatSlice = outputValues[(idx * self.valuesPerColumn)..<((idx+1) * self.valuesPerColumn)]
							outTuple.append(Value(floats: Array(floatSlice)))
						}
						return outTuple
					}
					consumer(.Success(outTuples), streamStatus)
				}
				catch let e as FFNNError {
					switch e {
					case .InvalidAnswerError(let s):
						return consumer(.Failure(String(format: "Invalid answer for AI: %@".localized, s)), .Finished)
					case .InvalidInputsError(let s):
						return consumer(.Failure(String(format: "Invalid inputs for AI: %@".localized, s)), .Finished)
					case .InvalidWeightsError(let s):
						return consumer(.Failure(String(format: "Invalid weights for AI: %@".localized, s)), .Finished)
					}
				}
				catch let e as NSError {
					return consumer(.Failure(e.localizedDescription), .Finished)
				}

			case .Failure(let e):
				return consumer(.Failure(e), .Finished)
			}
		}
	}

	private func train(job: Job, trainingColumns: [Column], callback: (Fallible<()>) -> ()) {
		self.training.fetch(job) { result, streamStatus in
			switch result {
			case .Success(let tuples):
				tuples.forEach { tuple in
					let inputValues = self.valuesForInputRow(Row(tuple, columns: trainingColumns))
					let outputValues = self.valuesForOutputRow(Row(tuple, columns: trainingColumns))

					do {
						try self.mutex.tryLocked {
							try self.model.update(inputs: inputValues)
							try self.model.backpropagate(answer: outputValues)
						}
					}
					catch let e as FFNNError {
						switch e {
						case .InvalidAnswerError(let s):
							return callback(.Failure(String(format: "Invalid answer for AI: %@".localized, s)))
						case .InvalidInputsError(let s):
							return callback(.Failure(String(format: "Invalid inputs for AI: %@".localized, s)))
						case .InvalidWeightsError(let s):
							return callback(.Failure(String(format: "Invalid weights for AI: %@".localized, s)))
						}
					}
					catch let e as NSError {
						return callback(.Failure(e.localizedDescription))
					}
				}

				// If we have more training data, fetch it
				if streamStatus == .HasMore {
					job.async {
						self.train(job, trainingColumns: trainingColumns, callback: callback)
					}
				}
				else {
					return callback(.Success())
				}

			case .Failure(let e):
				return callback(.Failure(e))
			}
		}
	}

	private func columns(job: Job, callback: (Fallible<[Column]>) -> ()) {
		return callback(.Success(inputs + outputs))
	}

	private func clone() -> Stream {
		return QBEClassifierStream(data: data, training: training, inputs: Set(inputs), outputs: Set(outputs))
	}
}

class QBEClassifierStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain? = nil

	required init() {
		super.init()
	}

	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}

	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObjectOfClass(QBEChain.self, forKey: "right")
		super.init(coder: aDecoder)
	}

	static func supportsSecureCoding() -> Bool {
		return true
	}

	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(right, forKey: "right")
		super.encodeWithCoder(coder)
	}

	var recursiveDependencies: Set<QBEDependency> {
		if let r = right {
			return Set([QBEDependency(step: self, dependsOn: r)]).union(r.recursiveDependencies)
		}
		return []
	}

	var directDependencies: Set<QBEDependency> {
		if let r = right {
			return Set([QBEDependency(step: self, dependsOn: r)])
		}
		return []
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Classify using AI".localized)
	}

	private func classify(data: Data, withTrainingData trainingData: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		trainingData.columns(job) { result in
			switch result {
			case .Success(let trainingCols):
				data.columns(job) { result in
					switch result {
					case .Success(let dataCols):
						let inputCols = Set(dataCols).intersect(trainingCols)
						let outputCols = Set(trainingCols).subtract(dataCols)

						// Do work
						return callback(.Success(StreamData(source: QBEClassifierStream(data: data.stream(), training: trainingData.stream(), inputs: inputCols, outputs: outputCols))))

					case .Failure(let e):
						return callback(.Failure(e))
					}
				}

			case .Failure(let e):
				return callback(.Failure(e))
			}
		}
	}

	override func fullData(job: Job, callback: (Fallible<Data>) -> ()) {
		if let p = previous {
			p.fullData(job) { leftData in
				switch leftData {
				case .Success(let ld):
					if let r = self.right, let h = r.head {
						h.fullData(job) { rightData in
							switch rightData {
							case .Success(let rd):
								return self.classify(ld, withTrainingData: rd, job: job, callback: callback)

							case .Failure(_):
								return callback(rightData)
							}
						}
					}
					else {
						callback(.Failure("The training data set was not found.".localized))
					}

				case .Failure(let e):
					callback(.Failure(e))
				}
			}
		}
		else {
			callback(.Failure("The source data set was not found".localized))
		}
	}

	override func exampleData(job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		if let p = previous {
			p.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) { leftData in
				switch leftData {
				case .Success(let ld):
					if let r = self.right, let h = r.head {
						h.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightData) -> () in
							switch rightData {
							case .Success(let rd):
								return self.classify(ld, withTrainingData: rd, job: job, callback: callback)

							case .Failure(_):
								callback(rightData)
							}
						})
					}
					else {
						callback(.Failure(NSLocalizedString("The data to join with was not found.", comment: "")))
					}
				case .Failure(_):
					callback(leftData)
				}
			}
		}
		else {
			callback(.Failure(NSLocalizedString("A join step was not placed after another step.", comment: "")))
		}
	}

	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		fatalError("QBEClassifierStep.apply should not be used")
	}
}