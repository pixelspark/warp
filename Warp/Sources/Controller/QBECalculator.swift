import Foundation
import WarpCore

/** Notification that is sent around whenever a step or chain changes in such a way that it requires recalculation of
data depending on the chain's outcome. */
internal class QBEChangeNotification: NSObject {
	static let name = "nl.pixelspark.warp.ChangeNotification"

	weak var sender: NSObject?
	let chain: QBEChain

	private init(chain: QBEChain) {
		self.chain = chain
	}

	internal static func broadcastChange(_ chain: QBEChain) {
		let n = QBEChangeNotification(chain: chain)
		asyncMain {
			NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: QBEChangeNotification.name), object: n))
		}
	}
}

/** Notification that is sent around by QBECalculator whenever a result has been calculated for a particular step. Tablets
that depend on data from another step can listen for this notification to receive 'cheap' data (it has already been
calculated) and update their displays. */
public class QBEResultNotification: NSObject {
	public static let name = "nl.pixelspark.warp.ResultNotification"

	weak var calculator: QBECalculator?
	let raster: Raster
	let isFull: Bool
	let step: QBEStep

	private init(raster: Raster, isFull: Bool, step: QBEStep, calculator: QBECalculator) {
		self.raster = raster
		self.isFull = isFull
		self.step = step
		self.calculator = calculator
	}
}

/** The QBECalculator class coordinates execution of steps. In particular, it models the performance of steps and can
estimate the number of input rows required to arrive at a certain number of output rows (e.g. in example calculations). */
public class QBECalculator: NSObject {
	public var currentDataset: Future<Fallible<Dataset>>?
	public var currentRaster: Future<Fallible<Raster>>?
	private var mutex: Mutex = Mutex()
	
	/** Statistical level of certainty that is used when calculating upper limits */
	public var certainty = 0.95
	
	/** The desired number of example rows; the number of rows should with `certainty` be below this limit */
	public var desiredExampleRows = 500
	
	/** The absolute maximum number of input rows for an example calculation */
	public var maximumExampleInputRows = 25000
	
	/** The absolute minimum number of input rows for an example calculation */
	public var minimumExampleInputRows = 256
	
	/** The time that example calculation must not exceed with `certainty` */
	public var maximumExampleTime = 1.5

	/** The maximum number of attempts that should be made to obtain more rows while there is still time left within the 
	given time limit */
	public var maximumIterations = 10

	private var calculationInProgressForStep: QBEStep? = nil
	private var stepPerformance: [Int: QBEStepPerformance] = [:]

	public var calculating: Bool { get {
		return self.mutex.locked {
			return self.calculationInProgressForStep != nil
		}
	} }

	public override init() {
		super.init()
	}
	
	/** Returns the number of input rows that should be set as a limit in an example calculation in order to meet the
	constraints set for examples (e.g. desired number of rows, maximum execution time). The estimates are based on 
	information on previous executions (time per input row, amplification factor). If there is no information, a default
	is used with an exponentially increasing number of input rows. */
	private func inputRowsForExample(_ step: QBEStep, maximumTime: Double) -> Int {
		if maximumTime <= 0 {
			return 0
		}
		var inputRows = self.desiredExampleRows

		self.mutex.locked {
			let index = unsafeAddress(of: step).hashValue
			
			if let performance = self.stepPerformance[index] {
				// If we have no data on amplification, we have to guess... double on each execution
				if performance.emptyCount == performance.executionCount {
					inputRows = inputRows * Int(pow(Double(2.0), Double(performance.executionCount)))
				}
				else {
					// Calculate the lower and upper estimate for the amplification factor (result rows / input rows).
					let (_, upperAmp) = performance.inputAmplificationFactor.sample.confidenceInterval(self.certainty)
					if upperAmp > 0 {
						// If the source step amplifies input by two, request calculation with half the number of input rows
						inputRows = Int(Double(self.desiredExampleRows) / upperAmp)
					}
				}
				
				// Check to see if the newly calculated number of needed input rows would create a time-consuming calculation
				let (_, upperTime) = performance.timePerInputRow.sample.confidenceInterval(self.certainty)
				if upperTime > 0 {
					let upperEstimatedTime = Double(inputRows) * upperTime
					if upperEstimatedTime > maximumTime {
						/* With `certainty` we would exceed the maximum time set for examples. Set the number of input 
						rows to a value that would, with `certainty`, uses the full time. */
						let i = Int(maximumTime / upperTime)
						inputRows = i
					}
				}
			}

			// Make sure we never exceed the absolute limits
			inputRows = min(self.maximumExampleInputRows, max(self.minimumExampleInputRows, inputRows))
		}
		return inputRows
	}
	
	/** Start an example calculation, but repeat the calculation if there is time budget remaining and zero rows have 
	been returned. The given callback is called as soon as the last calculation round has finished. */
	public func calculateExample(_ sourceStep: QBEStep, maximumTime: Double? = nil, attempt: Int = 0, callback: () -> ()) {
		let maxTime = maximumTime ?? maximumExampleTime
		
		let startTime = Date.timeIntervalSinceReferenceDate
		let maxInputRows = inputRowsForExample(sourceStep, maximumTime: maxTime)
		self.calculate(sourceStep, fullDataset: false, maximumTime: maxTime)
		
		// Record extra information when calculating an example result
		currentRaster!.get {[unowned self] (raster) in
			switch raster {
			case .success(let r):
				let duration = Double(NSDate.timeIntervalSinceReferenceDate) - startTime

				// Record performance information for example execution
				let index = unsafeAddress(of: sourceStep).hashValue
				var startAnother = false

				self.mutex.locked {
					var perf = self.stepPerformance[index] ?? QBEStepPerformance()
					perf.timePerInputRow.add(duration / Double(maxInputRows))
					if r.rowCount > 0 {
						perf.inputAmplificationFactor.add(Double(r.rowCount) / Double(maxInputRows))
					}
					else {
						perf.emptyCount += 1
					}
					perf.executionCount += 1
					self.stepPerformance[index] = perf
				
					/* If we got zero rows, but there is stil time left, just try again. In many cases the back-end
					is much faster than we think and we have plenty of time left to fill in our time budget. */
					let maxExampleRows = self.maximumExampleInputRows
					if r.rowCount < self.desiredExampleRows && (maxTime - duration) > duration && (maxInputRows < maxExampleRows) {
						trace("Example took \(duration), we still have \(maxTime - duration) left, starting another (longer) calculation")
						startAnother = true
					}
				}

				if startAnother && attempt < self.maximumIterations {
					self.calculateExample(sourceStep, maximumTime: maxTime - duration, attempt: attempt + 1, callback: callback)
				}
				else {
					// Send notification of finished raster
					asyncMain {
						NotificationCenter.default.post(name: NSNotification.Name(rawValue: QBEResultNotification.name), object:
							QBEResultNotification(raster: r, isFull: false, step: sourceStep, calculator: self))
					}
					callback()
				}
				
			case .failure(_):
				break;
			}
		}
	}
	
	public func calculate(_ sourceStep: QBEStep, fullDataset: Bool, maximumTime: Double? = nil) {
		self.mutex.locked {
			if sourceStep != calculationInProgressForStep || currentDataset?.cancelled ?? false || currentRaster?.cancelled ?? false {
				currentDataset?.cancel()
				currentRaster?.cancel()
				calculationInProgressForStep = sourceStep
				var maxInputRows = 0
				
				// Set up calculation for the data object
				if fullDataset {
					currentDataset = Future<Fallible<Dataset>>(sourceStep.fullDataset)
				}
				else {
					maxInputRows = inputRowsForExample(sourceStep, maximumTime: maximumTime ?? maximumExampleTime)
					let maxOutputRows = desiredExampleRows
					trace("Setting up example calculation with maxout=\(maxOutputRows) maxin=\(maxInputRows)")
					currentDataset = Future<Fallible<Dataset>>({ (job, callback) in
						sourceStep.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
					})
				}

				let calculationJob = Job(QoS.userInitiated)
				
				// Set up calculation for the raster
				currentRaster = Future<Fallible<Raster>>({ [unowned self] (job: Job, callback: Future<Fallible<Raster>>.Callback) in
					if let cd = self.currentDataset {
						let dataJob = cd.get(job) { (data: Fallible<Dataset>) -> () in
							switch data {
								case .success(let d):
									d.raster(job) { result in
										result.maybe { raster in
											// Send notification of finished raster
											asyncMain {
												NotificationCenter.default.post(name: NSNotification.Name(rawValue: QBEResultNotification.name), object:
													QBEResultNotification(raster: raster, isFull: fullDataset, step: sourceStep, calculator: self))
											}
										}
										callback(result)
									}
								
								case .failure(let s):
									callback(.failure(s))
							}
						}
						dataJob.addObserver(job)
					}
					else {
						callback(.failure(NSLocalizedString("No data available.", comment: "")))
					}
				})
				
				// Wait for the raster to arrive so we can indicate the calculation has ended
				currentRaster!.get(calculationJob) { [unowned self] (r) in
					self.mutex.locked {
						self.calculationInProgressForStep = nil
					}
				}
			}
		}
	}
	
	public func cancel() {
		self.mutex.locked {
			currentDataset?.cancel()
			currentRaster?.cancel()
			currentDataset = nil
			currentRaster = nil
			calculationInProgressForStep = nil
		}
	}
}

private struct QBEStepPerformance {
	var inputAmplificationFactor: Moving = Moving(size: 10)
	var timePerInputRow: Moving = Moving(size: 10)
	var executionCount: Int = 0
	var emptyCount: Int = 0
}
