import Foundation

internal func QBELog(message: String, file: StaticString = __FILE__, line: UWord = __LINE__) {
	#if DEBUG
		dispatch_async(dispatch_get_main_queue()) {
			println(message)
		}
	#endif
}

internal func QBEAssertMainThread(file: StaticString = __FILE__, line: UWord = __LINE__) {
	assert(NSThread.isMainThread(), "Code at \(file):\(line) must run on main thread!")
}

/** Runs the given block of code asynchronously on the main queue. **/
internal func QBEAsyncMain(block: () -> ()) {
	dispatch_async(dispatch_get_main_queue(), block)
}

internal extension Array {
	func parallel<T, ResultType>(#map: ((ArraySlice<Element>) -> (T)), reduce: ((T, ResultType?) -> (ResultType))) -> QBEFuture<ResultType?> {
		let chunkSize = QBEStreamDefaultBatchSize
		
		return QBEFuture<ResultType?>({ (job, completion) -> () in
			let group = dispatch_group_create()
			var buffer: [T] = []
			
			// Chunk the contents of the array and dispatch jobs that map each chunk
			for i in stride(from: 0, to: self.count, by: chunkSize) {
				let view = self[i...min(i+chunkSize, self.count-1)]
				
				dispatch_group_async(group, job.queue) {
					// Check whether we still need to process this chunk
					if job.cancelled {
						return
					}
					
					// Generate output for this chunk
					let workerOutput = map(view)
					
					// Dispatch a block that adds our result (synchronously) to the intermediate result buffer
					dispatch_group_async(group, dispatch_get_main_queue()) {
						buffer.append(workerOutput)
					}
				}
			}
			
			// Reduce stage: loop over all intermediate results in the buffer and merge
			dispatch_group_notify(group, job.queue) {
				if job.cancelled {
					return
				}
				
				var result: ResultType? = nil
				for item in buffer {
					result = reduce(item, result)
				}
				
				completion(result)
			}
		}, timeLimit: nil)
	}
}

@objc protocol QBEJobDelegate {
	func job(job: AnyObject, didProgress: Double)
}

enum QBEQoS {
	case UserInitiated
	case Background
	
	var qosClass: dispatch_qos_class_t {
		switch self {
			case .UserInitiated:
				return QOS_CLASS_USER_INITIATED
			
			case .Background:
				return QOS_CLASS_BACKGROUND
		}
	}
}

/** 
A QBEJob represents a single asynchronous calculation. QBEJob tracks the progress and cancellation status of a single
'job'. It is generally passed along to all functions that also accept an asynchronous callback. The QBEJob object should 
never be stored by these functions. It should be passed on by the functions to any other asynchronous operations that 
belong to the same job. The QBEJob has an associated dispatch queue in which any asynchronous operations that belong to
the job should be executed (the shorthand function QBEJob.async can be used for this).

QBEJob can be used to track the progress of a job's execution. Components in the job can report their progress using the
reportProgress call. As key, callers should use a unique value (e.g. their own hashValue). The progress reported by QBEJob
is the average progress of all components.

When used with QBEFuture, a job represents a single attempt at the calculation of a future. The 'producer' callback of a 
QBEFuture receives the QBEJob object and should use it to check whether calculation of the future is still necessary (or
the job has been cancelled) and report progress information. */
class QBEJob {
	private(set) var cancelled: Bool = false
	private let queue: dispatch_queue_t
	private var progressComponents: [Int: Double] = [:]
	weak var delegate: QBEJobDelegate?
	
	init(_ qos: QBEQoS) {
		self.queue = dispatch_get_global_queue(qos.qosClass, 0)
	}
	
	private init(queue: dispatch_queue_t) {
		self.queue = queue
	}
	
	/** 
	Shorthand function to run a block asynchronously in the queue associated with this job. Because async() will often be
	called with an 'expensive' block, it also checks the jobs cancellation status. If the job is cancelled, the block 
	will not be executed, nor will any timing information be reported. */
	func async(block: () -> ()) {
		if cancelled {
			return
		}
		dispatch_async(queue, block)
	}
	
	/** 
	Records the time taken to execute the given block and writes it to the console. In release builds, the block is simply
	called and no timing information is gathered. Because time() will often be called with an 'expensive' block, it also
	checks the jobs cancellation status. If the job is cancelled, the block will not be executed, nor will any timing 
	information be reported. */
	func time(description: String, items: Int, itemType: String, @noescape block: () -> ()) {
		if cancelled {
			return
		}
		
		#if DEBUG
			let t = CFAbsoluteTimeGetCurrent()
			block()
			let d = CFAbsoluteTimeGetCurrent() - t
			
			log("\(description)\t\(items) \(itemType):\t\(round(10*Double(items)/d)/10) \(itemType)/s")
			self.reportTime(description, time: d)
		#else
			block()
		#endif
	}
	
	/** 
	Inform anyone waiting on this job that a particular sub-task has progressed. Progress needs to be between 0...1,
	where 1 means 'complete'. Callers of this function should generate a sufficiently unique key that identifies the sub-
	operation in the job of which the progress is reported (e.g. use '.hash' on an object private to the subtask). */
	func reportProgress(progress: Double, forKey: Int) {
		if progress < 0.0 || progress > 1.0 {
			// Ignore spurious progress reports
			log("Ignoring spurious progress report \(progress) for key \(forKey)")
		}
		
		QBEAsyncMain {
			self.progressComponents[forKey] = progress
			self.delegate?.job(self, didProgress: self.progress)
			return
		}
	}
	
	/** 
	Returns the estimated progress of the job by multiplying the reported progress for each component. The progress is
	represented as a double between 0...1 (where 1 means 'complete'). Progress is not guaranteed to monotonically increase
	or to ever reach 1. */
	var progress: Double { get {
		var sumProgress = 0.0;
		var items = 0;
		for (k, p) in self.progressComponents {
			sumProgress += p
			items++
		}
		
		return items > 0 ? (sumProgress / Double(items)) : 0.0;
	} }
	
	/** 
	Marks this job as 'cancelled'. Any blocking operation running in this job should periodically check the cancelled
	status, and abort if the job was cancelled. Calling cancel() does not guarantee that any operations are actually
	cancelled. */
	func cancel() {
		self.cancelled = true
	}
	
	/** 
	Print a message to the debug log. The message is sent to the console asynchronously (but ordered) and preprended
	with the 'job ID'. No messages will be logged when not compiled in debug mode. */
	func log(message: String, file: StaticString = __FILE__, line: UWord = __LINE__) {
		#if DEBUG
			let id = self.jobID
			dispatch_async(dispatch_get_main_queue()) {
				println("[\(id)] \(message)")
			}
		#endif
	}
	
	#if DEBUG
	private static var jobCounter = 0
	private let jobID = jobCounter++
	
	private var timeComponents: [String: Double] = [:]
	
	func reportTime(component: String, time: Double) {
		if let t = timeComponents[component] {
			timeComponents[component] = t + time
		}
		else {
			timeComponents[component] = time
		}
	
		let tcs = timeComponents
		let addr = unsafeAddressOf(self).debugDescription
		log("\(tcs)")
	}
	#endif
}

/** 
QBEFuture represents a result of a (potentially expensive) calculation. Code that needs the result of the
operation express their interest by enqueuing a callback with the get() function. The callback gets called immediately
if the result of the calculation was available in cache, or as soon as the result has been calculated. 

The calculation itself is done by the 'producer' block. When the producer block is changed, the cached result is 
invalidated (pre-registered callbacks may still receive the stale result when it has been calculated). */
class QBEFuture<T> {
	typealias Callback = QBEBatch<T>.Callback
	typealias Producer = (QBEJob, Callback) -> ()
	private var batch: QBEBatch<T>?
	var queue: dispatch_queue_t? = nil
	
	var calculating: Bool { get {
		return batch != nil
	} }
	
	let producer: Producer
	let timeLimit: Double?
	
	init(_ producer: Producer, timeLimit: Double? = nil)  {
		self.producer = producer
		self.timeLimit = timeLimit
	}
	
	private func calculate() {
		assert(batch != nil, "calculate() called without a current batch")
		
		if let batch = self.batch {
			if let tl = timeLimit {
				// Set a timer to cancel this job
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(tl * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
					batch.log("Timed out after \(tl) seconds")
					batch.expire()
				}
			}
			producer(batch, batch.satisfy)
		}
	}
	
	/** Abort calculating the result (if calculation is in progress). Registered callbacks will not be called (when 
	callbacks are already being called, this will be finished).**/
	func cancel() {
		batch?.cancel()
	}
	
	/** Abort calculating the result (if calculation is in progress). Registered callbacks may still be called. **/
	func expire() {
		batch?.expire()
	}
	
	var cancelled: Bool { get {
		return batch?.cancelled ?? false
	} }
	
	/** 
	Request the result of this future. There are three scenarios:
	- The future has not yet been calculated. In this case, calculation will start in the queue specified in the `queue`
	  variable. The callback will be enqueued to receive the result as soon as the calculation finishes. 
	- Calculation of the future is in progress. The callback will be enqueued on a waiting list, and will be called as 
	  soon as the calculation has finished.
	- The future has already been calculated. In this case the callback is called immediately with the result.
	
	Note that the callback may not make any assumptions about the queue or thread it is being called from. Callees should
	therefore not block. */
	func get(callback: Callback) -> QBEJob {
		if batch == nil {
			let q = queue ?? dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
			batch = QBEBatch<T>(queue: q)
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
	
	override init(queue: dispatch_queue_t) {
		super.init(queue: queue)
	}
	
	/** 
	Called by a producer to return the result of a job. This method will call all callbacks on the waiting list (on the
	main thread) and subsequently empty the waiting list. Enqueue can only be called once on a batch. */
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
	
	/**
	Expire is like cancel, only the waiting consumers are not removed from the waiting list. This allows a job to
	return a partial result (by calling the callback while job.cancelled is already true) */
	func expire() {
		if !satisfied {
			cancelled = true
		}
	}
	
	/**
	Cancel this job and remove all waiting listeners (they will never be called back). */
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