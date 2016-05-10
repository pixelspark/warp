import Foundation
import WarpAI
import WarpCore

/** A descriptive is a statistic about a set of values, usually a column in a table. */
private enum QBEDescriptiveType: String {
	case Average = "av"
	case Stdev = "sd"
	case Min = "mn"
	case Max = "mx"

	/** An aggregator that can be used to calculate the desired descriptive on a column. */
	var aggregator: Aggregator {
		switch self {
		case .Average: return Aggregator(map: Identity(), reduce: Function.Average)
		case .Stdev: return Aggregator(map: Identity(), reduce: Function.StandardDeviationPopulation)
		case .Max: return Aggregator(map: Identity(), reduce: Function.Max)
		case .Min: return Aggregator(map: Identity(), reduce: Function.Min)
		}
	}
}

private typealias QBEColumnDescriptives = [QBEDescriptiveType: Value]
private typealias QBEDataDescriptives = [Column: QBEColumnDescriptives]

private extension Data {
	/** Calculate the requested set of descriptives for the given set of columns. */
	func descriptives(columns: Set<Column>, types: Set<QBEDescriptiveType>, job: Job, callback: (Fallible<QBEDataDescriptives>) -> ()) {
		var aggregators: [Column: Aggregator] = [:]
		columns.forEach { column in
			types.forEach { type in
				let aggregateColumnName = Column("\(column.name)_\(type.rawValue)")
				var agg = type.aggregator
				agg.map = agg.map.expressionReplacingIdentityReferencesWith(Sibling(column))
				aggregators[aggregateColumnName] = agg
			}
		}

		self.aggregate([:], values: aggregators).raster(job) { result in
			var descriptives = QBEDataDescriptives()

			switch result {
			case .Success(let raster):
				assert(raster.rowCount == 1, "Row count in an aggregation without groups must be 1")
				let firstRow = raster.rows.first!

				columns.forEach { column in
					descriptives[column] = [:]
					types.forEach { type in
						let aggregateColumnName = Column("\(column.name)_\(type.rawValue)")
						descriptives[column]![type] = firstRow[aggregateColumnName]!
					}
				}

				return callback(.Success(descriptives))

			case .Failure(let e):
				return callback(.Failure(e))
			}
		}
	}
}

/** A classifier model takes in a row with input values, and produces a new row with added 'output' values.
To train, the classifier is fed rows that have both the input and output columns. */
private class QBEClassifierModel {
	/** Statistics on the columns in the training data set that allow them to be normalized **/
	let trainingDescriptives: QBEDataDescriptives
	let inputs: [Column]
	let outputs: [Column]

	private let model: FFNN
	private let mutex = Mutex()

	private let minValidationFraction = 0.3 // Percentage of rows that is added to validation set from each batch
	private let maxValidationSize = 512 // Maximum number of rows in the validation set
	private let errorThreshold: Float = 1.0 // Threshold for error after which training is considered done
	private let maxIterations = 100 // Maximum number of iterations for training

	private var validationReservoir :Reservoir<([Float],[Float])>

	/** Create a classifier model. The 'inputs' and 'outputs' set list the columns that should be
	used as input and output for the model, respectively. The `descriptives` object should contain
	descriptives for each column listed as either input or output. The descriptives should be the
	Avg, Stdev, Min and Max descriptives. */
	init(inputs: Set<Column>, outputs: Set<Column>, descriptives: QBEDataDescriptives) {
		// Check if all descriptives are present
		outputs.union(inputs).forEach { column in
			assert(descriptives[column] != nil, "classifier model instantiated without descritives for column \(column.name)")
			assert(descriptives[column]![.Average] != nil, "descriptives for \(column.name) are missing average")
			assert(descriptives[column]![.Stdev] != nil, "descriptives for \(column.name) are missing average")
			assert(descriptives[column]![.Min] != nil, "descriptives for \(column.name) are missing average")
			assert(descriptives[column]![.Max] != nil, "descriptives for \(column.name) are missing average")
		}

		self.trainingDescriptives = descriptives
		self.inputs = Array(inputs)
		self.outputs = Array(outputs)

		let hiddenNodes = (inputs.count * 2 / 3 ) + outputs.count
		self.validationReservoir = Reservoir<([Float],[Float])>(sampleSize: self.maxValidationSize)

		self.model = FFNN(
			inputs: inputs.count,
			hidden: hiddenNodes,
			outputs: outputs.count,
			learningRate: 0.7,
			momentum: 0.4,
			weights: nil,
			activationFunction: .Default,
			errorFunction: .Default(average: true)
		)
	}

	private func floatsForInputRow(row: Row) -> [Float] {
		return self.inputs.map { inputColumn -> Float in
			// Normalize the value
			let v = row[inputColumn] ?? .InvalidValue
			let descriptive = (self.trainingDescriptives[inputColumn])!
			return Float(((v - (descriptive[.Average])!) / (descriptive[.Stdev])!).doubleValue ?? Double.NaN)
		}
	}

	private func floatsForOutputRow(row: Row) -> [Float] {
		return self.outputs.map { outputColumn -> Float in
			// Normalize the value, make it a value between 0..<1
			let v = row[outputColumn] ?? .InvalidValue
			let descriptive = (self.trainingDescriptives[outputColumn])!
			let range = (descriptive[.Max]! - descriptive[.Min]!)
			return Float(((v - (descriptive[.Min])!) / range).doubleValue ?? Double.NaN)
		}
	}

	private func valuesForOutputRow(row: [Float]) -> [Value] {
		return self.outputs.enumerate().map { index, column in
			let v = row[index]
			let descriptive = self.trainingDescriptives[column]!
			let range = descriptive[.Max]! - descriptive[.Min]!
			return Value.DoubleValue(Double(v)) * range + descriptive[.Min]!
		}
	}

	/** Classify a single row, returns the set of output values (in order of output columns). */
	func classify(input: Row) throws -> [Value] {
		let inputValues = self.floatsForInputRow(input)

		let outputValues = try self.mutex.tryLocked {
			return try self.model.update(inputs: inputValues)
		}

		return self.valuesForOutputRow(outputValues)
	}

	/** Classify multiple rows at once. If `appendOutputToInput` is set to true, the returned set of
	rows will all each start with the input columns, followed by the output columns. */
	func classify(inputs: [Row], appendOutputToInput: Bool, callback: (Fallible<[Tuple]>) -> ()) {
		// Clear the reservoir with validation rows, we don't need those anymore as training should have finished now
		self.validationReservoir.clear()
		do {
			let outTuples = try inputs.map { row -> Tuple in
				return (appendOutputToInput ? row.values : []) + (try self.classify(row))
			}
			callback(.Success(outTuples))
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

	/** Train the model using data from the stream indicated. The `trainingColumns` list indicates */
	func train(job: Job, stream: Stream, callback: (Fallible<()>) -> ()) {
		if self.inputs.isEmpty {
			return callback(.Failure("Please make sure there is data to use for classification".localized))
		}

		if self.outputs.isEmpty {
			return callback(.Failure("Please make sure there is a target column for classification".localized))
		}

		stream.columns(job) { result in
			switch result {
			case .Success(let trainingColumns):
				self.train(job, stream: stream, trainingColumns: trainingColumns, callback: callback)

			case .Failure(let e):
				return callback(.Failure(e))
			}
		}
	}

	private func train(job: Job, stream: Stream, trainingColumns: [Column], callback: (Fallible<()>) -> ()) {
		stream.fetch(job) { result, streamStatus in
			switch result {
			case .Success(let tuples):
				let values = tuples.map { tuple -> ([Float], [Float]) in
					let inputValues = self.floatsForInputRow(Row(tuple, columns: trainingColumns))
					let outputValues = self.floatsForOutputRow(Row(tuple, columns: trainingColumns))
					job.log("TR \(inputValues) => \(outputValues)")
					return (inputValues, outputValues)
				}

				let allInputs = values.map { return $0.0 }
				let allOutputs = values.map { return $0.1 }

				let localValidationReservoir = Reservoir<([Float],[Float])>(sampleSize: Int(floor(self.minValidationFraction * Double(tuples.count))))
				localValidationReservoir.add(values)
				self.validationReservoir.add(localValidationReservoir.sample)

				do {
					try self.mutex.tryLocked {
						for _ in 0..<self.maxIterations {
							for (index, input) in allInputs.enumerate() {
								try self.model.update(inputs: input)
								try self.model.backpropagate(answer: allOutputs[index])
							}
							// Calculate the total error of the validation set after each epoch
							let errorSum: Float = try self.model.error(self.validationReservoir.sample.map { return $0.0 }, expected: self.validationReservoir.sample.map { return $0.1 })
							if isnan(errorSum) || errorSum < self.errorThreshold {
								job.log("BREAK \(errorSum) < \(self.errorThreshold)")
								break
							}
						}

						let errorSum: Float = try self.model.error(self.validationReservoir.sample.map { return $0.0 }, expected: self.validationReservoir.sample.map { return $0.1 })
						job.log("errorSum: \(errorSum)")
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

				// If we have more training data, fetch it
				if streamStatus == .HasMore {
					job.async {
						self.train(job, stream: stream, trainingColumns: trainingColumns, callback: callback)
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
}

/** A classifier stream uses one data set to train a classifier model, then uses it to add values to another
data set. */
private class QBEClassifierStream: Stream {
	let data: Stream
	let training: Stream

	private let model: QBEClassifierModel
	private var trainingFuture: Future<Fallible<()>>! = nil
	private var dataColumnsFuture: Future<Fallible<[Column]>>! = nil

	init(data: Stream, training: Stream, descriptives: QBEDataDescriptives, inputs: Set<Column>, outputs: Set<Column>) {
		self.data = data
		self.training = training
		self.model = QBEClassifierModel(inputs: inputs, outputs: outputs, descriptives: descriptives)

		self.dataColumnsFuture = Future<Fallible<[Column]>>(self.data.columns)

		self.trainingFuture = Future<Fallible<()>>({ [unowned self] job, cb in

			// Build a model based on the training data
			self.model.train(job, stream: self.training) { result in
				switch result {
				case .Success():
					return cb(.Success())

				case .Failure(let e):
					return cb(.Failure(e))
				}
			}
		})
	}

	private func fetch(job: Job, consumer: Sink) {
		// Make sure the model is trained before starting to classify result
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

	/** Fetch a batch of rows from the source data stream and let the model calculate outputs. */
	private func classify(job: Job, columns: [Column], consumer: (Fallible<[Tuple]>, StreamStatus) -> ()) {
		self.data.fetch(job) { result, streamStatus in
			switch result {
			case .Success(let tuples):
				self.model.classify(tuples.map { return Row($0, columns: columns) }, appendOutputToInput: true) { result in
					switch result {
					case .Success(let outTuples):
						return consumer(.Success(outTuples), streamStatus)

					case .Failure(let e):
						return consumer(.Failure(e), .Finished)
					}
				}

			case .Failure(let e):
				return consumer(.Failure(e), .Finished)
			}
		}
	}

	private func columns(job: Job, callback: (Fallible<[Column]>) -> ()) {
		return callback(.Success(self.model.inputs + self.model.outputs))
	}

	private func clone() -> Stream {
		return QBEClassifierStream(data: data, training: training, descriptives: self.model.trainingDescriptives, inputs: Set(self.model.inputs), outputs: Set(self.model.outputs))
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
						let allCols = inputCols.union(outputCols)

						// Fetch descriptives of training set to be used for normalization
						trainingData.descriptives(allCols, types: [.Average, .Stdev, .Min, .Max], job: job) { result in
							switch result {
							case .Success(let descriptives):
								return callback(.Success(StreamData(source: QBEClassifierStream(data: data.stream(), training: trainingData.stream(), descriptives: descriptives, inputs: inputCols, outputs: outputCols))))

							case .Failure(let e):
								return callback(.Failure(e))
							}
						}

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
						callback(.Failure("The training data set was not found.".localized))
					}
				case .Failure(_):
					callback(leftData)
				}
			}
		}
		else {
			callback(.Failure("The source data set was not found".localized))
		}
	}

	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		fatalError("QBEClassifierStep.apply should not be used")
	}
}