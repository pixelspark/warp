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

class QBECacheStep: QBEStep, NSSecureCoding {
	private var cachedDataset: Future<Fallible<Dataset>>? = nil
	private let mutex = Mutex()

	required init() {
		super.init()
		self.evictCache()
	}

	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		self.evictCache()
	}

	deinit {
		self.cachedDataset?.cancel()
	}

	func evictCache() {
		self.mutex.locked {
			self.cachedDataset?.cancel()
			self.cachedDataset = Future<Fallible<Dataset>>({ [weak self] (job, callback) in
				if let prev = self?.previous {
					prev.fullDataset(job) { result in
						switch result {
						case .success(let fullData):
							var cd: QBESQLiteCachedDataset? = nil
							cd = QBESQLiteCachedDataset(source: fullData, job: job, completion: { result in
								switch result {
								case .failure(let e):
									callback(.failure(e))

								case .success( _):
									callback(.success(cd!.coalesced))
								}

							})

						case .failure(let e):
							callback(.failure(e))
						}
					}
				}
				else {
					callback(.failure("no source data"))
				}
			})
		}
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Cache data set".localized)
	}

	static var supportsSecureCoding: Bool = true

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.mutex.locked { () -> () in
			if let r = self.cachedDataset?.result, case .failure(_) = r {
				self.evictCache()
			}
			else if let cd = self.cachedDataset, cd.cancelled && cd.result == nil {
				self.evictCache()
			}

			// Make sure that cancelling job does not lead to cancellation of the caching effort by using a separate job
			let cacheJob = Job(job.queue.qos)
			let actualJob = self.cachedDataset!.get(cacheJob) { r in
				switch r {
				case .success(let fullData):
					callback(.success(QBESQLiteExampleDataset(data: fullData, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows)))

				case .failure(let e):
					return callback(.failure(e))
				}
			}

			// Forward any caching progress reports to the 'real' job
			actualJob.addObserver(job)
		}
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.mutex.locked {
			if let r = self.cachedDataset?.result, case .failure(_) = r {
				self.evictCache()
			}
			else if let cd = self.cachedDataset, cd.cancelled && cd.result == nil {
				self.evictCache()
			}

			// Make sure that cancelling job does not lead to cancellation of the caching effort by using a separate job
			let cacheJob = Job(job.queue.qos)
			let actualJob = self.cachedDataset!.get(cacheJob, callback)

			// Forward any caching progress reports to the 'real' job
			actualJob.addObserver(job)
		}
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(data))
	}
}
