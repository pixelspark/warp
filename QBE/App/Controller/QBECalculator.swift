import Foundation
import WarpCore

/** The QBECalculator class coordinates execution of steps. In particular, it models the performance of steps and can
estimate the number of input rows required to arrive at a certain number of output rows (e.g. in example calculations). */
public class QBECalculator {
	public var currentData: QBEFuture<QBEFallible<QBEData>>?
	public var currentRaster: QBEFuture<QBEFallible<QBERaster>>?
	
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
	
	private var calculationInProgressForStep: QBEStep? = nil
	private var stepPerformance: [Int: QBEStepPerformance] = [:]
	
	public var calculating: Bool { get {
		return self.calculationInProgressForStep != nil
	} }

	public init() {
	}
	
	/** Returns the number of input rows that should be set as a limit in an example calculation in order to meet the
	constraints set for examples (e.g. desired number of rows, maximum execution time). The estimates are based on 
	information on previous executions (time per input row, amplification factor). If there is no information, a default
	is used with an exponentially increasing number of input rows. */
	private func inputRowsForExample(step: QBEStep, maximumTime: Double) -> Int {
		if maximumTime <= 0 {
			return 0
		}
		
		let index = unsafeAddressOf(step).hashValue
		var inputRows = desiredExampleRows
		
		if let performance = stepPerformance[index] {
			// If we have no data on amplification, we have to guess... double on each execution
			if performance.emptyCount == performance.executionCount {
				inputRows = inputRows * Int(pow(Double(2.0), Double(performance.executionCount)))
			}
			else {
				// Calculate the lower and upper estimate for the amplification factor (result rows / input rows).
				let (_, upperAmp) = performance.inputAmplificationFactor.sample.confidenceInterval(certainty)
				if upperAmp > 0 {
					// If the source step amplifies input by two, request calculation with half the number of input rows
					inputRows = Int(Double(desiredExampleRows) / upperAmp)
				}
			}
			
			// Check to see if the newly calculated number of needed input rows would create a time-consuming calculation
			let (_, upperTime) = performance.timePerInputRow.sample.confidenceInterval(certainty)
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
		inputRows = min(maximumExampleInputRows, max(minimumExampleInputRows, inputRows))
		return inputRows
	}
	
	/** Start an example calculation, but repeat the calculation if there is time budget remaining and zero rows have 
	been returned. The given callback is called as soon as the last calculation round has finished. */
	public func calculateExample(sourceStep: QBEStep, maximumTime: Double? = nil,  columnFilters: [QBEColumn:QBEFilterSet]? = nil, callback: () -> ()) {
		let maxTime = maximumTime ?? maximumExampleTime
		
		let startTime = NSDate.timeIntervalSinceReferenceDate()
		let maxInputRows = inputRowsForExample(sourceStep, maximumTime: maxTime)
		self.calculate(sourceStep, fullData: false, maximumTime: maxTime, columnFilters: columnFilters)
		
		// Record extra information when calculating an example result
		currentRaster!.get {[unowned self] (raster) in
			switch raster {
			case .Success(let r):
				let duration = Double(NSDate.timeIntervalSinceReferenceDate()) - startTime

				// Record performance information for example execution
				let index = unsafeAddressOf(sourceStep).hashValue

				QBEAsyncMain {
					var perf = self.stepPerformance[index] ?? QBEStepPerformance()
					perf.timePerInputRow.add(duration / Double(maxInputRows))
					if r.rowCount > 0 {
						perf.inputAmplificationFactor.add(Double(r.rowCount) / Double(maxInputRows))
					}
					else {
						perf.emptyCount++
					}
					perf.executionCount++
					self.stepPerformance[index] = perf
				
					/* If we got zero rows, but there is stil time left, just try again. In many cases the back-end
					is much faster than we think and we have plenty of time left to fill in our time budget. */
					let maxExampleRows = self.maximumExampleInputRows
					if r.rowCount < self.desiredExampleRows && (maxTime - duration) > duration && (maxInputRows < maxExampleRows) {
						QBELog("Example took \(duration), we still have \(maxTime - duration) left, starting another (longer) calculation")
						self.calculateExample(sourceStep, maximumTime: maxTime - duration, columnFilters: columnFilters, callback: callback)
					}
					else {
						callback()
					}
				}
				
			case .Failure(_):
				break;
			}
		}
	}
	
	public func calculate(sourceStep: QBEStep, fullData: Bool, maximumTime: Double? = nil, columnFilters: [QBEColumn:QBEFilterSet]? = nil) {
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
				maxInputRows = inputRowsForExample(sourceStep, maximumTime: maximumTime ?? maximumExampleTime)
				let maxOutputRows = desiredExampleRows
				QBELog("Setting up example calculation with maxout=\(maxOutputRows) maxin=\(maxInputRows)")
				currentData = QBEFuture<QBEFallible<QBEData>>({ (job, callback) in
					sourceStep.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
				})
			}
			
			// Set up calculation for the raster
			currentRaster = QBEFuture<QBEFallible<QBERaster>>({ [unowned self] (job: QBEJob, callback: QBEFuture<QBEFallible<QBERaster>>.Callback) in
				if let cd = self.currentData {
					let dataJob = cd.get { (data: QBEFallible<QBEData>) -> () in
						switch data {
							case .Success(let d):
								// At this point, we know which columns will be available. We should now add the view filters (if any)
								if let filters = columnFilters where filters.count > 0 {
									d.columnNames(job, callback: { (fallibleColumns) -> () in
										switch fallibleColumns {
										case .Success(let columnNames):
											var filteredData = d
											for column in columnNames {
												if let columnFilter = filters[column] {
													let filterExpression = columnFilter.expression.expressionReplacingIdentityReferencesWith(QBESiblingExpression(columnName: column))
													filteredData = filteredData.filter(filterExpression)
												}
											}
											
											filteredData.raster(job, callback: callback)
											
										case .Failure(let e):
											callback(.Failure(e))
										}
									})
									
								}
								else {
									d.raster(job, callback: callback)
								}
							
							case .Failure(let s):
								callback(.Failure(s))
						}
					}
					dataJob.addObserver(job)
				}
				else {
					callback(.Failure(NSLocalizedString("No data available.", comment: "")))
				}
			})
			
			// Wait for the raster to arrive so we can indicate the calculation has ended
			currentRaster!.get { [unowned self] (r) in
				self.calculationInProgressForStep = nil
			}
		}
	}
	
	public func cancel() {
		currentData?.cancel()
		currentRaster?.cancel()
		currentData = nil
		currentRaster = nil
		calculationInProgressForStep = nil
	}
}

private struct QBEStepPerformance {
	var inputAmplificationFactor: QBEMoving = QBEMoving(size: 10)
	var timePerInputRow: QBEMoving = QBEMoving(size: 10)
	var executionCount: Int = 0
	var emptyCount: Int = 0
}