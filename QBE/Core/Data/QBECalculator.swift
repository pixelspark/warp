import Foundation

private struct QBEStepPerformance {
	var inputAmplificationFactor: QBEMoving = QBEMoving(size: 10)
	var timePerInputRow: QBEMoving = QBEMoving(size: 10)
	var executionCount: Int = 0
	var emptyCount: Int = 0
}

/** The QBECalculator class coordinates execution of steps. In particular, it models the performance of steps and can
estimate the number of input rows required to arrive at a certain number of output rows (e.g. in example calculations). **/
class QBECalculator {
	internal var currentData: QBEFuture<QBEFallible<QBEData>>?
	internal var currentRaster: QBEFuture<QBEFallible<QBERaster>>?
	
	/** Statistical level of certainty that is used when calculating upper limits **/
	internal var certainty = 0.95
	
	/** The desired number of example rows; the number of rows should with `certainty` be below this limit **/
	internal var desiredExampleRows = 500
	
	/** The absolute maximum number of input rows for an example calculation **/
	internal var maximumExampleInputRows = 25000
	
	/** The absolute minimum number of input rows for an example calculation **/
	internal var minimumExampleInputRows = 256
	
	/** The time that example calculation must not exceed with `certainty` **/
	internal var maximumExampleTime = 1.5
	
	private var calculationInProgressForStep: QBEStep? = nil
	private var stepPerformance: [Int: QBEStepPerformance] = [:]
	
	var calculating: Bool { get {
		return self.calculationInProgressForStep != nil
	} }
	
	/** Returns the number of input rows that should be set as a limit in an example calculation in order to meet the
	constraints set for examples (e.g. desired number of rows, maximum execution time). The estimates are based on 
	information on previous executions (time per input row, amplification factor). If there is no information, a default
	is used with an exponentially increasing number of input rows. **/
	private func inputRowsForExample(step: QBEStep) -> Int {
		let index = unsafeAddressOf(step).distanceTo(nil)
		var inputRows = desiredExampleRows
		
		if let performance = stepPerformance[index] {
			// Check if there is sensible data on performance or not
			if performance.emptyCount == performance.executionCount {
				// We haven't ever received any rows for this step. Double the number of input rows for each execution
				inputRows = inputRows * Int(pow(Double(2.0), Double(performance.executionCount)))
			}
			else {
				// Calculate the lower and upper estimate for the amplification factor (result rows / input rows).
				let (lowerAmp, upperAmp) = performance.inputAmplificationFactor.sample.confidenceInterval(certainty)
				if upperAmp > 0 {
					// If the source step amplifies input by two, request calculation with half the number of input rows
					inputRows = Int(Double(desiredExampleRows) / upperAmp)
				}
				
				// Check to see if the newly calculated number of needed input rows would create a time-consuming calculation
				let (lowerTime, upperTime) = performance.timePerInputRow.sample.confidenceInterval(certainty)
				if upperTime > 0 {
					let upperEstimatedTime = Double(inputRows) * upperTime
					if upperEstimatedTime > maximumExampleTime {
						/* With `certainty` we would exceed the maximum time set for examples. Set the number of input 
						rows to a value that would, with `certainty`, uses the full time. */
						let i = Int(maximumExampleTime / upperTime)
						inputRows = i
					}
				}
			}
		}

		// Make sure we never exceed the absolute limits
		inputRows = min(maximumExampleInputRows, max(minimumExampleInputRows, inputRows))
		return inputRows
	}
	
	func calculate(sourceStep: QBEStep, fullData: Bool) {
		if sourceStep != calculationInProgressForStep || currentData?.cancelled ?? false || currentRaster?.cancelled ?? false {
			currentData?.cancel()
			currentRaster?.cancel()
			calculationInProgressForStep = sourceStep
			var maxInputRows = 0
			
			// Set up calculation for the data object
			if fullData {
				currentData = QBEFuture<QBEFallible<QBEData>>(sourceStep.fullData)
			}
			else {
				maxInputRows = inputRowsForExample(sourceStep)
				let maxOutputRows = desiredExampleRows
				QBELog("Setting up example calculation with maxout=\(maxOutputRows) maxin=\(maxInputRows)")
				currentData = QBEFuture<QBEFallible<QBEData>>({ [unowned self] (job, callback) in
					sourceStep.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
				})
			}
			
			// Set up calculation for the raster
			let startTime = NSDate.timeIntervalSinceReferenceDate()
			currentRaster = QBEFuture<QBEFallible<QBERaster>>({ [unowned self] (job: QBEJob, callback: QBEFuture<QBEFallible<QBERaster>>.Callback) in
				if let cd = self.currentData {
					cd.get({ (data: QBEFallible<QBEData>) -> () in
						switch data {
							case .Success(let d):
								d.value.raster(job, callback: callback)
							
							case .Failure(let s):
								callback(.Failure(s))
						}
					})
				}
				else {
					callback(.Failure(NSLocalizedString("No data available.", comment: "")))
				}
			})
			
			// Wait for the raster to arrive so we can indicate the calculation has ended
			currentRaster!.get({[unowned self] (r) in
				self.calculationInProgressForStep = nil
			})
			
			// Record extra information when calculating an example result
			if !fullData {
				currentRaster!.get {[unowned self] (raster) in
					switch raster {
						case .Success(let r):
							let duration = NSDate.timeIntervalSinceReferenceDate() - startTime
							let index = unsafeAddressOf(sourceStep).distanceTo(nil)
							
							// Record performance information for example execution
							var perf = self.stepPerformance[index] ?? QBEStepPerformance()
							if r.value.rowCount > 0 {
								perf.inputAmplificationFactor.add(Double(r.value.rowCount) / Double(maxInputRows))
								perf.timePerInputRow.add(duration / Double(maxInputRows))
							}
							else {
								perf.emptyCount++
							}
							perf.executionCount++
							self.stepPerformance[index] = perf
						
						case .Failure(let e):
							break;
					}
				}
			}
		}
	}
	
	func cancel() {
		currentData?.cancel()
		currentRaster?.cancel()
		currentData = nil
		currentRaster = nil
		calculationInProgressForStep = nil
	}
}