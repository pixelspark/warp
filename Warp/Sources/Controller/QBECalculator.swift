/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
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

	fileprivate init(raster: Raster, isFull: Bool, step: QBEStep, calculator: QBECalculator) {
		self.raster = raster
		self.isFull = isFull
		self.step = step
		self.calculator = calculator
	}
}

public struct QBECalculatorParameters {
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
}

public struct QBECalculation {
	var job: Job
	var forStep: QBEStep
}

/** The QBECalculator class coordinates execution of steps. In particular, it models the performance of steps and can
estimate the number of input rows required to arrive at a certain number of output rows (e.g. in example calculations). */
public class QBECalculator: NSObject {
	private var _currentDataset: Future<Fallible<Dataset>>?
	private var _currentRaster: Future<Fallible<Raster>>?
	private var mutex: Mutex = Mutex()
	private var calculationInProgress: QBECalculation? = nil
	private var stepPerformance: [Int: QBEStepPerformance] = [:]
	private var currentParameters = QBECalculatorParameters()

	/** Whether the calculator will request incremental rasterization. If false, the calculator will request a rasterization
	and you should use currentRaster.get() to obtain the raster. If true, the calculator will request incremental
	rasterization. You use currentRaster.get() to obtain the first result */
	public let incremental: Bool

	public var currentDataset: Future<Fallible<Dataset>>? { return self.mutex.locked { return self._currentDataset } }
	public var currentRaster: Future<Fallible<Raster>>? { return self.mutex.locked { return self._currentRaster } }
	public var currentCalculation: QBECalculation? { return self.mutex.locked { return self.calculationInProgress } }

	public var parameters: QBECalculatorParameters {
		set {
			self.mutex.locked {
				self.currentParameters = newValue
			}
		}
		get {
			return self.mutex.locked {
				return self.currentParameters
			}
		}
	}

	public var calculating: Bool { get {
		return self.mutex.locked {
			return self.calculationInProgress != nil
		}
	} }

	public init(incremental: Bool) {
		self.incremental = incremental
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

		return self.mutex.locked {
			var inputRows = self.currentParameters.desiredExampleRows

			let index = Unmanaged.passUnretained(step).toOpaque().hashValue
			
			if let performance = self.stepPerformance[index] {
				// If we have no data on amplification, we have to guess... double on each execution
				if performance.emptyCount == performance.executionCount {
					inputRows = inputRows * Int(pow(Double(2.0), Double(performance.executionCount)))
				}
				else {
					// Calculate the lower and upper estimate for the amplification factor (result rows / input rows).
					let (_, upperAmp) = performance.inputAmplificationFactor.sample.confidenceInterval(self.currentParameters.certainty)
					if upperAmp > 0 {
						// If the source step amplifies input by two, request calculation with half the number of input rows
						inputRows = Int(Double(self.currentParameters.desiredExampleRows) / upperAmp)
					}
				}
				
				// Check to see if the newly calculated number of needed input rows would create a time-consuming calculation
				let (_, upperTime) = performance.timePerInputRow.sample.confidenceInterval(self.currentParameters.certainty)
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
			inputRows = min(self.currentParameters.maximumExampleInputRows, max(self.currentParameters.minimumExampleInputRows, inputRows))
			return inputRows
		}
	}
	
	/** Start an example calculation, but repeat the calculation if there is time budget remaining and zero rows have 
	been returned. The given callback is called as soon as the last calculation round has finished. */
	public func calculateExample(_ sourceStep: QBEStep, maximumTime: Double? = nil, attempt: Int = 0, job: Job, callback: @escaping () -> ()) {
		let maxTime = maximumTime ?? self.currentParameters.maximumExampleTime
		
		let startTime = Date.timeIntervalSinceReferenceDate
		let maxInputRows = inputRowsForExample(sourceStep, maximumTime: maxTime)
		self.calculate(sourceStep, fullDataset: false, maximumTime: maxTime, job: job, callback: once { streamStatus in
			// Record extra information when calculating an example result

			self.currentRaster!.get(job) {[unowned self] (raster) in
				switch raster {
				case .success(let r):
					let duration = Double(NSDate.timeIntervalSinceReferenceDate) - startTime

					// Record performance information for example execution
					let index = Unmanaged.passUnretained(sourceStep).toOpaque().hashValue
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
						let maxExampleRows = self.currentParameters.maximumExampleInputRows
						if r.rowCount < self.currentParameters.desiredExampleRows && (maxTime - duration) > duration && (maxInputRows < maxExampleRows) {
							trace("Example took \(duration), we still have \(maxTime - duration) left, starting another (longer) calculation")
							startAnother = true
						}

						if startAnother && attempt < self.currentParameters.maximumIterations {
							self.calculateExample(sourceStep, maximumTime: maxTime - duration, attempt: attempt + 1, job: job, callback: callback)
						}
						else {
							// Send notification of finished raster
							asyncMain {
								NotificationCenter.default.post(name: NSNotification.Name(rawValue: QBEResultNotification.name), object:
									QBEResultNotification(raster: r, isFull: false, step: sourceStep, calculator: self))
							}
							callback()
						}
					}
					
				case .failure(_):
					break;
				}
			}
		})
	}
	
	public func calculate(_ sourceStep: QBEStep, fullDataset: Bool, maximumTime: Double? = nil, job calculationJob: Job, callback: @escaping ((StreamStatus) -> ())) {
		return self.mutex.locked {
			currentDataset?.cancel()
			self.calculationInProgress?.job.cancel()

			self.calculationInProgress = QBECalculation(job: calculationJob, forStep: sourceStep)
			var maxInputRows = 0
			
			// Set up calculation for the data object
			if fullDataset {
				self._currentDataset = Future<Fallible<Dataset>>(sourceStep.fullDataset)
			}
			else {
				maxInputRows = inputRowsForExample(sourceStep, maximumTime: maximumTime ?? self.currentParameters.maximumExampleTime)
				let maxOutputRows = self.currentParameters.desiredExampleRows
				trace("Setting up example calculation with maxout=\(maxOutputRows) maxin=\(maxInputRows)")
				self._currentDataset = Future<Fallible<Dataset>>({ (job, callback) in
					sourceStep.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
				})
			}

			if incremental && fullDataset {
				let rasterFuture = MutableFuture<Fallible<Raster>>()
				self._currentRaster = rasterFuture

				if let cd = self.currentDataset {
					cd.get(calculationJob) { result in
						switch result {
						case .success(let dataset):
							dataset.raster(calculationJob, deliver: .incremental) { result, streamStatus in
								switch result {
								case .success(let raster):
									result.maybe { raster in
										// Send notification of finished raster
										asyncMain {
											NotificationCenter.default.post(name: NSNotification.Name(rawValue: QBEResultNotification.name), object:
												QBEResultNotification(raster: raster, isFull: fullDataset, step: sourceStep, calculator: self))
										}
									}
									rasterFuture.satisfy(.success(raster), queue: calculationJob.queue)

									self.mutex.locked {
										if streamStatus == .finished {
											self.calculationInProgress = nil
										}

										calculationJob.async {
											callback(streamStatus)
										}
									}

								case .failure(let e):
									rasterFuture.satisfy(.failure(e), queue: calculationJob.queue)

									self.mutex.locked {
										if streamStatus == .finished {
											self.calculationInProgress = nil
										}

										calculationJob.async {
											callback(.finished)
										}
									}
								}
							}

						case .failure(let e):
							self.mutex.locked {
								self.calculationInProgress = nil
							}

							rasterFuture.satisfy(.failure(e), queue: calculationJob.queue)
						}
					}
				}
				else {
					rasterFuture.satisfy(.failure("no data availble"), queue: calculationJob.queue)
				}
			}
			else {
				// Set up calculation for the raster
				self._currentRaster = Future<Fallible<Raster>>({ [unowned self] (job: Job, producerCallback: @escaping Future<Fallible<Raster>>.Callback) in
					if let cd = self.currentDataset {
						let dataJob = cd.get(job) { (data: Fallible<Dataset>) -> () in
							switch data {
								case .success(let d):
									d.raster(job) { result in
										self.mutex.locked {
											self.calculationInProgress = nil
										}

										result.maybe { raster in
											// Send notification of finished raster
											asyncMain {
												NotificationCenter.default.post(name: NSNotification.Name(rawValue: QBEResultNotification.name), object:
													QBEResultNotification(raster: raster, isFull: fullDataset, step: sourceStep, calculator: self))
											}
										}

										producerCallback(result)
									}
								
								case .failure(let s):
									self.mutex.locked {
										self.calculationInProgress = nil
									}
									producerCallback(.failure(s))
							}
						}
						dataJob.addObserver(job)
					}
					else {
						self.mutex.locked {
							self.calculationInProgress = nil
						}
						producerCallback(.failure(NSLocalizedString("No data available.", comment: "")))
					}
				})
				
				// Wait for the raster to arrive so we can indicate the calculation has ended
				currentRaster!.get(calculationJob) { [unowned self] (r) in
					self.mutex.locked {
						self.calculationInProgress = nil
						calculationJob.async {
							callback(.finished)
						}
					}
				}
			}
		}
	}
	
	public func cancel() {
		self.mutex.locked {
			currentDataset?.cancel()
			calculationInProgress?.job.cancel()
			self._currentDataset = nil
			self._currentRaster = nil
			self.calculationInProgress = nil
		}
	}
}

private struct QBEStepPerformance {
	var inputAmplificationFactor: Moving = Moving(size: 10)
	var timePerInputRow: Moving = Moving(size: 10)
	var executionCount: Int = 0
	var emptyCount: Int = 0
}
