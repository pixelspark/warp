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

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Dataset>) -> ()) {
		self.mutex.locked { () -> () in
			if let r = self.cachedDataset?.result, case .failure(_) = r {
				self.evictCache()
			}

			self.cachedDataset!.get(job) { r in
				switch r {
				case .success(let fullData):
					callback(.success(QBESQLiteExampleDataset(data: fullData, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows)))

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		}
	}

	override func fullDataset(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		if let r = self.cachedDataset?.result, case .failure(_) = r {
			self.evictCache()
		}

		self.mutex.locked {
			self.cachedDataset!.get(job, callback)
		}
	}

	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data))
	}
}
