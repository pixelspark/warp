import Foundation
import WarpAI
import WarpCore

private typealias QBEColumnDescriptives = [Function: Value]
private typealias QBEDatasetDescriptives = [Column: QBEColumnDescriptives]

private extension Dataset {
	/** Calculate the requested set of descriptives for the given set of columns. */
	func descriptives(_ columns: Set<Column>, types: Set<Function>, job: Job, callback: (Fallible<QBEDatasetDescriptives>) -> ()) {
		var aggregators: [Column: Aggregator] = [:]
		columns.forEach { column in
			types.forEach { type in
				let aggregateColumnName = Column("\(column.name)_\(type.rawValue)")
				let agg = Aggregator(map: Sibling(column), reduce: type)
				aggregators[aggregateColumnName] = agg
			}
		}

		self.aggregate([:], values: aggregators).raster(job) { result in
			var descriptives = QBEDatasetDescriptives()

			switch result {
			case .success(let raster):
				assert(raster.rowCount == 1, "Row count in an aggregation without groups must be 1")
				let firstRow = raster.rows.first!

				columns.forEach { column in
					descriptives[column] = [:]
					types.forEach { type in
						let aggregateColumnName = Column("\(column.name)_\(type.rawValue)")
						descriptives[column]![type] = firstRow[aggregateColumnName]!
					}
				}

				return callback(.success(descriptives))

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}

/** A mapping from Value to [Float]. */
private protocol QBENeuronAllocation {
	var count: Int { get } // The number of neurons allocated (size of the [Float])

	func toFloats(_ value: Value) -> [Float]
	func toValue(_ floats: [Float]) -> Value
}

private struct QBENormalizedNeuronAllocation: QBENeuronAllocation, CustomStringConvertible {
	let count = 1
	let standardDeviation: Double
	let mean: Double

	init(mean: Double, standardDeviation: Double) {
		self.mean = mean
		self.standardDeviation = standardDeviation
	}

	func toFloats(_ value: Value) -> [Float] {
		let r = value.doubleValue ?? Double.nan
		return [Float((r - mean) / standardDeviation)]
	}

	func toValue(_ floats: [Float]) -> Value {
		assert(floats.count == self.count, "invalid neuron count")
		return Value.double((Double(floats.first!) *  standardDeviation) + mean)
	}

	var description: String { return "1*D(\(self.mean), \(self.standardDeviation))" }
}

/** Linear allocation: a single float between 0...1, which is mapped to the original double value by linearly
scaling between minimum and maximum observed value. */
private struct QBELinearNeuronAllocation: QBENeuronAllocation, CustomStringConvertible {
	let count = 1
	let min: Double
	let max: Double

	init(min: Double, max: Double) {
		assert(max >= min, "Max cannot be smaller than min")
		self.min = min
		self.max = max
	}

	func toFloats(_ value: Value) -> [Float] {
		if max == min {
			return [Float(min)]
		}

		let r = value.doubleValue ?? Double.nan
		return [Float((r - min) / (max - min))]
	}

	func toValue(_ floats: [Float]) -> Value {
		assert(floats.count == self.count, "invalid neuron count")
		return Value.double((Double(floats.first!) *  (max - min)) + min)
	}

	var description: String { return "1*L(\(self.min), \(self.max))" }
}

/** Linear allocation: a single float between 0...1, which is mapped to the original double value by linearly
scaling between minimum and maximum observed value. */
private struct QBEDummyNeuronAllocation: QBENeuronAllocation, CustomStringConvertible {
	var count: Int { return values.count }
	let values: [Value]

	init(values: [Value]) {
		self.values = values
	}

	func toFloats(_ value: Value) -> [Float] {
		return self.values.map { $0 == value ? Float(1.0) : Float(0.0) }
	}

	func toValue(_ floats: [Float]) -> Value {
		assert(floats.count == self.values.count, "invalid vector length")

		var maxValue: Float = 0.0
		var maxIndex = 0

		for (i, v) in floats.enumerated() {
			if v > maxValue {
				maxValue = v
				maxIndex = i
			}
		}

		return self.values[maxIndex]
	}

	var description: String { return "\(self.count)*[\(self.values)]" }
}

/** Provides a mapping between a row (list of Value) and a set of neurons (list of Float). The former is provided
by Warp data sources, the latter are input and output to neural networks. 

By default, the allocator will assign a single float value for each column. It will use the descriptives object to
decide how to allocate additional floats to a column based on its type. An integer column that has been shown to
only have two distinct values may for instance obtain two instead of one Float, where each value is represented as
a dummy. */
private class QBENeuronAllocator {
	let columns: OrderedSet<Column>
	let descriptives: QBEDatasetDescriptives
	let neuronCount: Int
	let allocations: [QBENeuronAllocation]

	/** Allocate neurons to values from the identified columns. Use the column descriptives to decide which 
	column receives which amount of neurons. The descriptives object should contain a dictionary for each column
	specified, within which descriptives should be listed based on the aggregated outputs of the .Min, .Max,
	.Average and .StandardDeviationPopulation, .Count and .CountDistinct functions over the values in the 
	training data set for that column.
	
	The maximum number of neurons determines the number of neurons the allocator will assign at most -note that
	each value will at least receive a single neuron, so if columns.count > maximumNumberOfNeurons,
	the number of neurons is columns.count. 
	
	If set to 'output', the allocator will allocate neurons with a type that fits the output side of the network.
	Output neurons take values between 0..1 whereas input neurons can be any value (but are usually normalized). */
	init(descriptives: QBEDatasetDescriptives, columns: OrderedSet<Column>, maximumNumberofNeurons: Int = 256, output: Bool) {
		self.descriptives = descriptives
		self.columns = columns

		var allocatedCount = 0
		var allocatedColumns = 0
		self.allocations = columns.map { column -> QBENeuronAllocation in
			let descriptive = (descriptives[column])!
			let remainingCount = (maximumNumberofNeurons - allocatedCount)
			allocatedColumns += 1

			let v: QBENeuronAllocation
			if output {
				if let min = descriptive[.Min]!.intValue, let max = descriptive[.Max]!.intValue, max > min {
					if (max - min) >= descriptive[.CountDistinct]!.intValue! &&
						descriptive[.CountDistinct]!.intValue! <= remainingCount &&
						descriptive[.CountAll]!.intValue! > 2 * descriptive[.CountDistinct]!.intValue! {
						v = QBEDummyNeuronAllocation(values: Array(min..<max).map { Value($0) })
					}
					else {
						v = QBELinearNeuronAllocation(
							min: descriptive[.Min]!.doubleValue!,
							max: descriptive[.Max]!.doubleValue!
						)
					}
				}
				else {
					// Outputs are between 0..1, so we need to use a linear mapping
					// TODO: perhaps base min and max on mu ± 2*sigma to reject outliers
					v = QBELinearNeuronAllocation(
						min: descriptive[.Min]!.doubleValue!,
						max: descriptive[.Max]!.doubleValue!
					)
				}

				allocatedCount += v.count
				return v
			}
			else {
				let v = QBENormalizedNeuronAllocation(
					mean: descriptive[.Average]!.doubleValue!,
					standardDeviation: descriptive[.StandardDeviationPopulation]!.doubleValue!
				)
				allocatedCount += v.count
				return v
			}
		}

		self.neuronCount = allocatedCount
		trace("Allocations: \(self.allocations)")
	}

	private func floatsForRow(_ row: Row) -> [Float] {
		return self.columns.enumerated().flatMap { (index, inputColumn) -> [Float] in
			let v = row[inputColumn] ?? .invalid
			let allocation = self.allocations[index]
			return allocation.toFloats(v)
		}
	}

	private func valuesForFloats(_ row: [Float]) -> [Value] {
		assert(self.neuronCount == row.count, "input vector has the wrong length (\(row.count) versus expected \(self.neuronCount))")

		var offset = 0
		return self.columns.enumerated().flatMap { (index, inputColumn) -> Value in
			let allocation = self.allocations[index]
			let v = Array(row[offset..<(offset + allocation.count)])
			offset += allocation.count
			return allocation.toValue(v)
		}
	}
}

/** A classifier model takes in a row with input values, and produces a new row with added 'output' values.
To train, the classifier is fed rows that have both the input and output columns. */
private class QBEClassifierModel {
	/** Statistics on the columns in the training data set that allow them to be normalized **/
	let inputs: OrderedSet<Column>
	let outputs: OrderedSet<Column>
	let complexity: Double
	let trainingDescriptives: QBEDatasetDescriptives

	static let requiredDescriptiveTypes: [Function] = [.Average, .StandardDeviationPopulation, .Min, .Max, .CountAll, .CountDistinct]

	private let model: FFNN
	private let mutex = Mutex()

	private let inputAllocator: QBENeuronAllocator
	private let outputAllocator: QBENeuronAllocator

	private let minValidationFraction = 0.3 // Percentage of rows that is added to validation set from each batch
	private let maxValidationSize = 512 // Maximum number of rows in the validation set
	private let errorThreshold: Float = 1.0 // Threshold for error after which training is considered done
	private let maxIterations = 100 // Maximum number of iterations for training

	private var validationReservoir :Reservoir<([Float],[Float])>

	/** Create a classifier model. The 'inputs' and 'outputs' set list the columns that should be
	used as input and output for the model, respectively. The `descriptives` object should contain
	descriptives for each column listed as either input or output. The descriptives should be the
	Avg, Stdev, Min and Max descriptives. */
	init(inputs: OrderedSet<Column>, outputs: OrderedSet<Column>, descriptives: QBEDatasetDescriptives, complexity: Double) {
		assert(complexity > 0.0, "complexity must be above 0.0")

		// Check if all descriptives are present
		outputs.union(with: inputs).forEach { column in
			assert(descriptives[column] != nil, "classifier model instantiated without descritives for column \(column.name)")
			assert(descriptives[column]![.Average] != nil, "descriptives for \(column.name) are missing average")
			assert(descriptives[column]![.StandardDeviationPopulation] != nil, "descriptives for \(column.name) are missing average")
			assert(descriptives[column]![.Min] != nil, "descriptives for \(column.name) are missing average")
			assert(descriptives[column]![.Max] != nil, "descriptives for \(column.name) are missing average")
		}

		self.trainingDescriptives = descriptives
		self.inputAllocator = QBENeuronAllocator(descriptives: descriptives, columns: inputs, output: false)
		self.outputAllocator = QBENeuronAllocator(descriptives: descriptives, columns: outputs, output: true)
		self.inputs = inputs
		self.outputs = outputs
		self.complexity = complexity

		// TODO: make configurable. This manages the 'complexity' of the network, or the 'far-fetchedness' of its results
		let hiddenNodes = max(inputAllocator.neuronCount, max(outputAllocator.neuronCount, Int(complexity * Double((inputAllocator.neuronCount * 2 / 3 ) + outputAllocator.neuronCount))))
		self.validationReservoir = Reservoir<([Float],[Float])>(sampleSize: self.maxValidationSize)

		self.model = FFNN(
			inputs: inputAllocator.neuronCount,
			hidden: hiddenNodes,
			outputs: outputAllocator.neuronCount,
			learningRate: 0.7,
			momentum: 0.4,
			weights: nil,
			activationFunction: .Default,
			errorFunction: .default(average: true)
		)
	}

	/** Classify a single row, returns the set of output values (in order of output columns). */
	func classify(_ input: Row) throws -> [Value] {
		let inputValues = self.inputAllocator.floatsForRow(input)

		let outputValues = try self.mutex.tryLocked {
			return try self.model.update(inputs: inputValues)
		}

		return self.outputAllocator.valuesForFloats(outputValues)
	}

	/** Classify multiple rows at once. If `appendOutputToInput` is set to true, the returned set of
	rows will all each start with the input columns, followed by the output columns. */
	func classify(_ inputs: [Row], appendOutputToInput: Bool, callback: (Fallible<[Tuple]>) -> ()) {
		// Clear the reservoir with validation rows, we don't need those anymore as training should have finished now
		self.validationReservoir.clear()
		do {
			let outTuples = try inputs.map { row -> Tuple in
				return (appendOutputToInput ? row.values : []) + (try self.classify(row))
			}
			callback(.success(outTuples))
		}
		catch let e as FFNNError {
			switch e {
			case .invalidAnswerError(let s):
				return callback(.failure(String(format: "Invalid answer for AI: %@".localized, s)))
			case .invalidInputsError(let s):
				return callback(.failure(String(format: "Invalid inputs for AI: %@".localized, s)))
			case .invalidWeightsError(let s):
				return callback(.failure(String(format: "Invalid weights for AI: %@".localized, s)))
			}
		}
		catch let e as NSError {
			return callback(.failure(e.localizedDescription))
		}
	}

	/** Train the model using data from the stream indicated. The `trainingColumns` list indicates */
	func train(_ job: Job, stream: WarpCore.Stream, callback: (Fallible<()>) -> ()) {
		if self.inputs.isEmpty {
			return callback(.failure("Please make sure there is data to use for classification".localized))
		}

		if self.outputs.isEmpty {
			return callback(.failure("Please make sure there is a target column for classification".localized))
		}

		stream.columns(job) { result in
			switch result {
			case .success(let trainingColumns):
				self.train(job, stream: stream, trainingColumns: trainingColumns, callback: callback)

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}

	private func train(_ job: Job, stream: WarpCore.Stream, trainingColumns: OrderedSet<Column>, callback: (Fallible<()>) -> ()) {
		stream.fetch(job) { result, streamStatus in
			switch result {
			case .success(let tuples):
				let values = tuples.map { tuple -> ([Float], [Float]) in
					let inputValues = self.inputAllocator.floatsForRow(Row(tuple, columns: trainingColumns))
					let outputValues = self.outputAllocator.floatsForRow(Row(tuple, columns: trainingColumns))
					return (inputValues, outputValues)
				}

				let allInputs = values.map { return $0.0 }
				let allOutputs = values.map { return $0.1 }
				self.validationReservoir.add(values)

				do {
					try self.mutex.tryLocked {
						for _ in 0..<self.maxIterations {
							for (index, input) in allInputs.enumerated() {
								try self.model.update(inputs: input)
								try self.model.backpropagate(answer: allOutputs[index])
							}
							// Calculate the total error of the validation set after each epoch
							let errorSum: Float = try self.model.error(self.validationReservoir.sample.map { return $0.0 }, expected: self.validationReservoir.sample.map { return $0.1 })
							if errorSum.isNaN || errorSum < self.errorThreshold {
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
					case .invalidAnswerError(let s):
						return callback(.failure(String(format: "Invalid answer for AI: %@".localized, s)))
					case .invalidInputsError(let s):
						return callback(.failure(String(format: "Invalid inputs for AI: %@".localized, s)))
					case .invalidWeightsError(let s):
						return callback(.failure(String(format: "Invalid weights for AI: %@".localized, s)))
					}
				}
				catch let e as NSError {
					return callback(.failure(e.localizedDescription))
				}

				// If we have more training data, fetch it
				if streamStatus == .hasMore {
					job.async {
						self.train(job, stream: stream, trainingColumns: trainingColumns, callback: callback)
					}
				}
				else {
					return callback(.success())
				}

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}

/** A classifier stream uses one data set to train a classifier model, then uses it to add values to another
data set. */
private class QBEClassifierStream: WarpCore.Stream {
	let data: WarpCore.Stream
	let training: WarpCore.Stream!
	let isTrained: Bool

	private let model: QBEClassifierModel
	private var trainingFuture: Future<Fallible<()>>! = nil
	private var dataColumnsFuture: Future<Fallible<OrderedSet<Column>>>! = nil

	init(data: WarpCore.Stream, trainedModel: QBEClassifierModel) {
		self.data = data
		self.isTrained = true
		self.training = nil
		self.model = trainedModel
		self.trainingFuture = Future<Fallible<()>>({ _, cb in
			return cb(.success())
		})
		
		self.dataColumnsFuture = Future<Fallible<OrderedSet<Column>>>(self.data.columns)
	}

	init(data: WarpCore.Stream, training: WarpCore.Stream, descriptives: QBEDatasetDescriptives, inputs: OrderedSet<Column>, outputs: OrderedSet<Column>, complexity: Double) {
		self.data = data
		self.isTrained = false
		self.training = training
		self.model = QBEClassifierModel(inputs: inputs, outputs: outputs, descriptives: descriptives, complexity: complexity)
		self.dataColumnsFuture = Future<Fallible<OrderedSet<Column>>>(self.data.columns)

		self.trainingFuture = Future<Fallible<()>>({ [unowned self] job, cb in
			// Build a model based on the training data
			self.model.train(job, stream: self.training) { result in
				switch result {
				case .success():
					return cb(.success())

				case .failure(let e):
					return cb(.failure(e))
				}
			}
		})
	}

	private func fetch(_ job: Job, consumer: Sink) {
		// Make sure the model is trained before starting to classify result
		self.trainingFuture.get(job) { result in
			switch result {
			case .success:
				self.dataColumnsFuture.get(job) { result in
					switch result {
					case .success(let dataCols):
						self.classify(job, columns: dataCols, consumer: consumer)

					case .failure(let e):
						return consumer(.failure(e), .finished)
					}
				}

			case .failure(let e):
				return consumer(.failure(e), .finished)
			}
		}
	}

	/** Fetch a batch of rows from the source data stream and let the model calculate outputs. */
	private func classify(_ job: Job, columns: OrderedSet<Column>, consumer: (Fallible<[Tuple]>, StreamStatus) -> ()) {
		self.data.fetch(job) { result, streamStatus in
			switch result {
			case .success(let tuples):
				self.model.classify(tuples.map { return Row($0, columns: columns) }, appendOutputToInput: true) { result in
					switch result {
					case .success(let outTuples):
						return consumer(.success(outTuples), streamStatus)

					case .failure(let e):
						return consumer(.failure(e), .finished)
					}
				}

			case .failure(let e):
				return consumer(.failure(e), .finished)
			}
		}
	}

	private func columns(_ job: Job, callback: (Fallible<OrderedSet<Column>>) -> ()) {
		return callback(.success(self.model.inputs.union(with: self.model.outputs)))
	}

	private func clone() -> WarpCore.Stream {
		if isTrained {
			return QBEClassifierStream(data: data, trainedModel: model)
		}
		else {
			return QBEClassifierStream(data: data, training: training, descriptives: self.model.trainingDescriptives, inputs: self.model.inputs, outputs: self.model.outputs, complexity: self.model.complexity)
		}
	}
}

/** Creates a neural network by training on the data from the `right` data set, then calculates results using that model
on the `left` data set. The inputs of the neural network are the columns that overlap between the two sets. The outputs 
are the columns that are present in the training data set, but not in the `left` data set. */
class QBEClassifierStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain? = nil
	var complexity: Double = 1.0

	required init() {
		super.init()
	}

	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}

	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObject(of: QBEChain.self, forKey: "right")
		self.complexity = aDecoder.decodeDouble(forKey: "complexity")
		if self.complexity <= 0.0 {
			self.complexity = 1.0
		}
		super.init(coder: aDecoder)
	}

	static var supportsSecureCoding: Bool = true

	override func encode(with coder: NSCoder) {
		coder.encode(right, forKey: "right")
		coder.encode(self.complexity, forKey: "complexity")
		super.encode(with: coder)
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

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Evaluate data using AI with complexity [#]".localized,
			QBESentenceTextInput(value: "\(self.complexity)", callback: { (nc) -> (Bool) in
				if let d = Double(nc) {
					self.complexity = d
					return true
				}
				return false
			})
		)
	}

	private func classify(_ data: Dataset, withTrainingDataset trainingDataset: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		let columnsJob = Job(parent: job)
		let dataColumnsJob = Job(parent: job)
		let descriptivesJob = Job(parent: job)

		trainingDataset.columns(columnsJob) { result in
			switch result {
			case .success(let trainingCols):
				data.columns(dataColumnsJob) { result in
					switch result {
					case .success(let dataCols):
						let inputCols = dataCols.intersection(with: Set(trainingCols))
						let outputCols = trainingCols.subtracting(Set(dataCols))
						let allCols = inputCols.union(with: outputCols)

						// Fetch descriptives of training set to be used for normalization
						trainingDataset.descriptives(Set(allCols), types: Set(QBEClassifierModel.requiredDescriptiveTypes), job: descriptivesJob) { result in
							switch result {
							case .success(let descriptives):
								// TODO save model here
								let classifierStream = QBEClassifierStream(data: data.stream(), training: trainingDataset.stream(), descriptives: descriptives, inputs: inputCols, outputs: outputCols, complexity: self.complexity)
								return callback(.success(StreamDataset(source: classifierStream)))

							case .failure(let e):
								return callback(.failure(e))
							}
						}

					case .failure(let e):
						return callback(.failure(e))
					}
				}

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}

	override func fullDataset(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		let leftJob = Job(parent: job)
		let rightJob = Job(parent: job)
		let classifyJob = Job(parent: job)

		if let p = previous {
			p.fullDataset(leftJob) { leftDataset in
				switch leftDataset {
				case .success(let ld):
					if let r = self.right, let h = r.head {
						h.fullDataset(rightJob) { rightDataset in
							switch rightDataset {
							case .success(let rd):
								return self.classify(ld, withTrainingDataset: rd, job: classifyJob, callback: callback)

							case .failure(_):
								return callback(rightDataset)
							}
						}
					}
					else {
						callback(.failure("The training data set was not found.".localized))
					}

				case .failure(let e):
					callback(.failure(e))
				}
			}
		}
		else {
			callback(.failure("The source data set was not found".localized))
		}
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Dataset>) -> ()) {
		if let p = previous {
			p.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows) { leftDataset in
				switch leftDataset {
				case .success(let ld):
					if let r = self.right, let h = r.head {
						h.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: { (rightDataset) -> () in
							switch rightDataset {
							case .success(let rd):
								return self.classify(ld, withTrainingDataset: rd, job: job, callback: callback)

							case .failure(_):
								callback(rightDataset)
							}
						})
					}
					else {
						callback(.failure("The training data set was not found.".localized))
					}
				case .failure(_):
					callback(leftDataset)
				}
			}
		}
		else {
			callback(.failure("The source data set was not found".localized))
		}
	}

	override func apply(_ data: Dataset, job: Job?, callback: (Fallible<Dataset>) -> ()) {
		fatalError("QBEClassifierStep.apply should not be used")
	}
}
