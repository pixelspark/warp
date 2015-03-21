import Foundation

/** Records the time taken to execute the given block and writes it to the console. In release builds, the block is simply
called and no timing information is gathered. **/
internal func QBETime(description: String, items: Int, itemType: String, _ job: QBEJob? = nil, @noescape block: () -> ()) {
	#if DEBUG
		let t = CFAbsoluteTimeGetCurrent()
		block()
		let d = CFAbsoluteTimeGetCurrent() - t
		println("QBETime\t\(description)\t\(items) \(itemType):\t\(round(10*Double(items)/d)/10) \(itemType)/s")
		
		if let j = job {
			j.reportTime(description, time: d)
		}
	#else
		block()
	#endif
}

/** Runs the given block of code asynchronously on the main queue. **/
internal func QBEAsyncMain(block: () -> ()) {
	dispatch_async(dispatch_get_main_queue(), block)
}

/** Runs the given block of code asynchronously on a concurrent background queue with QoS class 'user initiated'. **/
internal func QBEAsyncBackground(block: () -> ()) {
	let gq = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
	dispatch_async(gq, block)
}

protocol QBEJobDelegate {
	func job(job: QBEJob, didProgress: Double)
}

/** The QBEJob interface provides access to an object that can be used to track the progress of, and cancel, a single 
'job'. A job is a single attempt at the calculation of a future. The 'producer' callback of a QBEFuture receives the
Job object and should use it to check whether calculation of the future is still necessary (or the job has been cancelled)
and report progress information. 

The QBEJob object should never be stored by the producer. It should be passed on by the producer to any other 
asynchronous operations that belong to the same job.

QBEJob can be used to track the progress of a job's execution. Components in the job can report their progress using the
reportProgress call. As key, callers should use a unique value (e.g. their own hashValue). The progress reported by QBEJob
is the average progress of all components. **/
class QBEJob {
	private(set) var cancelled: Bool = false
	private var progressComponents: [Int: Double] = [:]
	/* FIXME: delegate needs to be weak (but then QBEJobDelegate needs to be @objc, which in turn requires QBEJob to be 
	NSObject subclass, which crashes the compiler... */
	var delegate: QBEJobDelegate?
	
	func reportProgress(progress: Double, forKey: Int) {
		if progress < 0.0 || progress > 1.0 {
			// Ignore spurious progress reports
			println("Ignoring spurious progress report \(progress) for key \(forKey)")
		}
		
		QBEAsyncMain {
			self.progressComponents[forKey] = progress
			self.delegate?.job(self, didProgress: self.progress)
			return
		}
	}
	
	var progress: Double { get {
		var sumProgress = 0.0;
		var items = 0;
		for (k, p) in self.progressComponents {
			sumProgress += p
			items++
		}
		
		return items > 0 ? (sumProgress / Double(items)) : 0.0;
	} }
	
	func cancel() {
		self.cancelled = true
	}
	
	#if DEBUG
	private var timeComponents: [String: Double] = [:]
	
	func reportTime(component: String, time: Double) {
		if let t = timeComponents[component] {
			timeComponents[component] = t + time
		}
		else {
			timeComponents[component] = time
		}
	
		let tcs = timeComponents
		QBEAsyncMain {
			println("Job done: \(tcs)")
		}
	}
	#endif
}

/** QBEFuture represents a result of a (potentially expensive) calculation. Code that needs the result of the
operation express their interest by enqueuing a callback with the get() function. The callback gets called immediately
if the result of the calculation was available in cache, or as soon as the result has been calculated. 

The calculation itself is done by the 'producer' block. When the producer block is changed, the cached result is 
invalidated (pre-registered callbacks may still receive the stale result when it has been calculated). **/
class QBEFuture<T> {
	typealias Callback = QBEBatch<T>.Callback
	typealias SimpleProducer = (Callback) -> ()
	typealias Producer = (QBEJob?, Callback) -> ()
	private var batch: QBEBatch<T>?
	
	var calculating: Bool { get {
		return batch != nil
	} }
	
	let producer: Producer
	
	init(_ producer: Producer)  {
		self.producer = producer
	}
	
	init(_ producer: SimpleProducer) {
		self.producer = {(job, callback) in producer(callback)}
	}
	
	private func calculate() {
		assert(batch != nil, "calculate() called without a current batch")
		
		if let batch = self.batch {
			producer(batch, batch.satisfy)
		}
	}
	
	func cancel() {
		batch?.cancel()
	}
	
	func get(callback: Callback) -> QBEJob {
		if batch == nil {
			batch = QBEBatch<T>()
			batch!.enqueue(callback)
			calculate()
		}
		else {
			batch!.enqueue(callback)
		}
		return batch!
	}
}

private class QBEBatch<T>: QBEJob {
	typealias Callback = (T) -> ()
	
	private var cached: T? = nil
	private var waitingList: [Callback] = []
	
	var satisfied: Bool { get {
		return cached != nil
	} }
	
	private func satisfy(value: T) {
		assert(cached == nil, "QBEBatch.satisfy called with cached!=nil")
		assert(!satisfied, "QBEBatch already satisfied")
		
		cached = value
		for waiting in waitingList {
			QBEAsyncMain {
				waiting(value)
			}
		}
		waitingList = []
	}
	
	override func cancel() {
		if !satisfied {
			waitingList.removeAll(keepCapacity: false)
			cancelled = true
		}
	}
	
	func enqueue(callback: Callback) {
		assert(!cancelled, "Cannot enqueue on a QBEFuture that is cancelled")
		if satisfied {
			QBEAsyncMain {
				callback(self.cached!)
			}
		}
		else {
			waitingList.append(callback)
		}
	}
}