import Foundation
import WarpCore

@objc internal protocol QBEJobsManagerDelegate: NSObjectProtocol {
	func jobManager(manager: QBEJobsManager, jobDidStart: AnyObject)
	func jobManagerJobsProgressed(manager: QBEJobsManager)
}

internal class QBEJobsManager: NSObject, QBEJobDelegate {
	class QBEJobInfo: QBEJobDelegate {
		weak var job: QBEJob?
		weak var delegate: QBEJobDelegate?
		let description: String
		var progress: Double
		private let mutex = QBEMutex()

		init(job: QBEJob, description: String) {
			self.description = description
			self.job = job
			self.progress = 0.0
			job.addObserver(self)
		}

		@objc func job(job: AnyObject, didProgress progress: Double) {
			mutex.locked {
				self.progress = progress
			}
			// Forward the progress notification
			self.delegate?.job(job, didProgress: progress)
		}

		var running: Bool {
			return mutex.locked {
				return self.job != nil
			}
		}
	}

	private var observers: [QBEWeak<QBEJobsManagerDelegate>] = []
	private var jobs: [QBEJobInfo] = []
	private let mutex = QBEMutex()

	override init() {
	}

	func addObserver(delegate: QBEJobsManagerDelegate) {
		mutex.locked {
			self.observers.append(QBEWeak(delegate))
		}
	}

	func removeObserver(delegate: QBEJobsManagerDelegate) {
		mutex.locked {
			self.observers = self.observers.filter { w in
				if let observer = w.value {
					return observer !== delegate
				}
				return false
			}
		}
	}

	func addJob(job: QBEJob, description: String) {
		let info = QBEJobInfo(job: job, description: description)
		info.delegate = self
		mutex.locked {
			self.jobs.append(info)
		}
		self.observers.forEach { d in d.value?.jobManager(self, jobDidStart: job) }
	}

	private let progressUpdateInterval = 1.0
	private var lastProgressUpdate: NSDate? = nil
	private var progressUpdateScheduled = false

	@objc func job(job: AnyObject, didProgress progress: Double) {
		mutex.locked {
			if !progressUpdateScheduled {
				let now = NSDate()
				if let lp = lastProgressUpdate where now.timeIntervalSinceDate(lp) < progressUpdateInterval {
					// Throttle
					progressUpdateScheduled = true
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(progressUpdateInterval * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
						self.mutex.locked {
							self.progressUpdateScheduled = false
							self.lastProgressUpdate = NSDate()
						}
						self.observers.forEach { d in d.value?.jobManagerJobsProgressed(self) }
					}
				}
				else {
					self.lastProgressUpdate = now
					QBEAsyncMain {
						self.observers.forEach { d in d.value?.jobManagerJobsProgressed(self) }
					}
				}
			}
		}
	}

	private func clean() {
		mutex.locked {
			self.jobs = self.jobs.filter { $0.running }
			self.observers = self.observers.filter { $0.value != nil }
		}
	}

	var runningJobs: [QBEJobInfo] {
		self.clean()
		return self.jobs.filter { $0.running }
	}
}
