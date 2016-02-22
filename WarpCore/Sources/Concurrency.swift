import Foundation

public func trace(message: String, file: StaticString = __FILE__, line: UInt = __LINE__) {
	#if DEBUG
		dispatch_async(dispatch_get_main_queue()) {
			print(message)
		}
	#endif
}

public func assertMainThread(file: StaticString = __FILE__, line: UInt = __LINE__) {
	assert(NSThread.isMainThread(), "Code at \(file):\(line) must run on main thread!")
}

public func once<P, R>(block: ((P) -> (R))) -> ((P) -> (R)) {
	var run = false

	#if DEBUG
	return {(p: P) -> (R) in
		assert(!run, "callback called twice!")
		run = true
		return block(p)
	}
	#else
		return block
	#endif
}

/** Runs the given block of code asynchronously on the main queue. */
public func asyncMain(block: () -> ()) {
	dispatch_async(dispatch_get_main_queue(), block)
}

public extension SequenceType {
	typealias Element = Generator.Element
	
	/** Iterate over the items in this array, and call the 'each' block for each element. At most `maxConcurrent` calls
	to `each` may be 'in flight' concurrently. After each has been called and called back for each of the items, the
	completion block is called. */
	func eachConcurrently(maxConcurrent maxConcurrent: Int, maxPerSecond: Int?, each: (Element, () -> ()) -> (), completion: () -> ()) {
		var iterator = self.generate()
		var outstanding = 0
		
		func eachTimed(element: Element) {
			let start = CFAbsoluteTimeGetCurrent()
			each(element, {
				let end = CFAbsoluteTimeGetCurrent()
				advance(end - start)
			})
		}
		
		func advance(duration: Double) {
			// There are more elements, call the each function on the next one
			if let next = iterator.next() {
				/* If we can make at most x requests per second, each request should take at least
				1/x seconds if we would be executing these requests serially. Because we have n
				concurrent requests, each request needs to take at least n/x seconds. */
				if let mrps = maxPerSecond {
					let minimumTime = Double(maxConcurrent) / Double(mrps)
					if minimumTime > duration {
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64((minimumTime - duration) * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
							eachTimed(next)
						}
						return
					}
				}
				eachTimed(next)
			}
			else {
				outstanding--
				// No elements left to call each for, but there may be some elements in flight. The last one calls completion
				if outstanding == 0 {
					completion()
				}
			}
		}
		
		// Call `each` for at most maxConcurrent items
		var atLeastOne = false
		for _ in 0..<maxConcurrent {
			if let next = iterator.next() {
				atLeastOne = true
				outstanding++
				eachTimed(next)
			}
		}
		
		if !atLeastOne {
			completion()
		}
	}
}

internal extension Array {
	func parallel<T, ResultType>(map map: ((Array<Element>) -> (T)), reduce: ((T, ResultType?) -> (ResultType))) -> Future<ResultType?> {
		let chunkSize = StreamDefaultBatchSize/8
		
		return Future<ResultType?>({ (job, completion) -> () in
			let group = dispatch_group_create()
			var buffer: [T] = []
			var finishedItems = 0
			
			// Chunk the contents of the array and dispatch jobs that map each chunk
			for i in 0.stride(to: self.count, by: chunkSize) {
				let view = Array(self[i..<min(i+chunkSize, self.count)])
				let count: Int = view.count
				
				dispatch_group_async(group, job.queue) {
					// Check whether we still need to process this chunk
					if job.cancelled {
						return
					}
					
					// Generate output for this chunk
					let workerOutput = map(view)
					
					// Dispatch a block that adds our result (synchronously) to the intermediate result buffer
					dispatch_group_async(group, dispatch_get_main_queue()) {
						finishedItems += count
						let p = Double(finishedItems) / Double(self.count)
						job.reportProgress(p, forKey: 1)
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

@objc public protocol JobDelegate {
	func job(job: AnyObject, didProgress: Double)
}

public enum QoS {
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

/** Fallible<T> represents the outcome of an operation that can either fail (with an error message) or succeed 
(returning an instance of T). */
public enum Fallible<T> {
	case Success(T)
	case Failure(String)
	
	public init<P>(_ other: Fallible<P>) {
		switch other {
			case .Success(let s):
				self = .Success(s as! T)
			
			case .Failure(let e):
				self = .Failure(e)
		}
	}
	
	/** If the result is successful, execute `block` on its return value, and return the (fallible) return value of that block
	(if any). Otherwise return a new, failed result with the error message of this result. This can be used to chain 
	operations on fallible operations, propagating the error once an operation fails. */
	@warn_unused_result(message="Deal with potential failure returned by .use, .require to force success or .maybe to ignore failure.")
	public func use<P>(@noescape block: T -> P) -> Fallible<P> {
		switch self {
			case Success(let value):
				return .Success(block(value))
			
			case Failure(let errString):
				return .Failure(errString)
		}
	}
	
	@warn_unused_result(message="Deal with potential failure returned by .use, .require to force success or .maybe to ignore failure.")
	public func use<P>(@noescape block: T -> Fallible<P>) -> Fallible<P> {
		switch self {
		case Success(let box):
			return block(box)
			
		case Failure(let errString):
			return .Failure(errString)
		}
	}
	
	/** If this result is a success, execute the block with its value. Otherwise cause a fatal error.  */
	public func require(@noescape block: T -> Void) {
		switch self {
		case Success(let value):
			block(value)
			
		case Failure(let errString):
			fatalError("Cannot continue with failure: \(errString)")
		}
	}

	/** If this result is a success, execute the block with its value. Otherwise silently ignore the failure (but log in debug mode) */
	public func maybe(@noescape block: T -> Void) {
		switch self {
		case Success(let value):
			block(value)
			
		case Failure(let errString):
			trace("Silently ignoring failure: \(errString)")
		}
	}
}

public class Weak<T: AnyObject>: NSObject {
	public private(set) weak var value: T?
	
	public init(_ value: T?) {
		self.value = value
	}
}

/** A Job represents a single asynchronous calculation. Job tracks the progress and cancellation status of a single
'job'. It is generally passed along to all functions that also accept an asynchronous callback. The Job object should 
never be stored by these functions. It should be passed on by the functions to any other asynchronous operations that 
belong to the same job. The Job has an associated dispatch queue in which any asynchronous operations that belong to
the job should be executed (the shorthand function Job.async can be used for this).

Job can be used to track the progress of a job's execution. Components in the job can report their progress using the
reportProgress call. As key, callers should use a unique value (e.g. their own hashValue). The progress reported by Job
is the average progress of all components.

When used with Future, a job represents a single attempt at the calculation of a future. The 'producer' callback of a 
Future receives the Job object and should use it to check whether calculation of the future is still necessary (or
the job has been cancelled) and report progress information. */
public class Job: JobDelegate {
	public let queue: dispatch_queue_t
	let parentJob: Job?
	public private(set) var cancelled: Bool = false
	private var progressComponents: [Int: Double] = [:]
	private var observers: [Weak<JobDelegate>] = []
	private let mutex = Mutex()

	#if DEBUG
	private static var jobCounter = 0
	private let jobID = jobCounter++
	#endif
	
	public init(_ qos: QoS) {
		let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, qos.qosClass, 0)

		#if DEBUG
			let jobNumber = Job.jobCounter + 1
			self.queue = dispatch_queue_create("Job \(jobNumber)", attr)
		#else
			self.queue = dispatch_queue_create("nl.pixelspark.Warp.Job", attr)
		#endif
		self.parentJob = nil
	}
	
	public init(parent: Job) {
		self.parentJob = parent
		self.queue = parent.queue
	}
	
	private init(queue: dispatch_queue_t) {
		self.queue = queue
		self.parentJob = nil
	}

	#if DEBUG
	deinit {
		log("Job deinit; \(timeComponents)")
	}
	#endif
	
	/** Shorthand function to run a block asynchronously in the queue associated with this job. Because async() will often
	be called with an 'expensive' block, it also checks the jobs cancellation status. If the job is cancelled, the block
	will not be executed, nor will any timing information be reported. */
	public func async(block: () -> ()) {
		if cancelled {
			return
		}
		
		if let p = parentJob where p.cancelled {
			return
		}
		
		dispatch_async(queue, block)
	}
	
	/** Records the time taken to execute the given block and writes it to the console. In release builds, the block is 
	simply called and no timing information is gathered. Because time() will often be called with an 'expensive' block, 
	it also checks the jobs cancellation status. If the job is cancelled, the block will not be executed, nor will any 
	timing information be reported. */
	public func time(description: String, items: Int, itemType: String, @noescape block: () -> ()) {
		if cancelled {
			return
		}
		
		if let p = parentJob where p.cancelled {
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
	
	public func addObserver(observer: JobDelegate) {
		mutex.locked {
			self.observers.append(Weak(observer))
		}
	}
	
	/** Inform anyone waiting on this job that a particular sub-task has progressed. Progress needs to be between 0...1,
	where 1 means 'complete'. Callers of this function should generate a sufficiently unique key that identifies the sub-
	operation in the job of which the progress is reported (e.g. use '.hash' on an object private to the subtask). */
	public func reportProgress(progress: Double, forKey: Int) {
		if progress < 0.0 || progress > 1.0 {
			// Ignore spurious progress reports
			log("Ignoring spurious progress report \(progress) for key \(forKey)")
			return
		}

		mutex.locked {
			self.progressComponents[forKey] = progress
			let currentProgress = self.progress
			for observer in self.observers {
				observer.value?.job(self, didProgress: currentProgress)
			}
			
			// Report our progress back up to our parent
			self.parentJob?.reportProgress(currentProgress, forKey: unsafeAddressOf(self).hashValue)
		}
	}
	
	/** Returns the estimated progress of the job by multiplying the reported progress for each component. The progress is
	represented as a double between 0...1 (where 1 means 'complete'). Progress is not guaranteed to monotonically increase
	or to ever reach 1. */
	public var progress: Double { get {
		return mutex.locked {
			var sumProgress = 0.0;
			var items = 0;
			for (_, p) in self.progressComponents {
				sumProgress += p
				items++
			}
			
			return items > 0 ? (sumProgress / Double(items)) : 0.0;
		}
	} }
	
	/** Marks this job as 'cancelled'. Any blocking operation running in this job should periodically check the cancelled
	status, and abort if the job was cancelled. Calling cancel() does not guarantee that any operations are actually
	cancelled. */
	public func cancel() {
		mutex.locked {
			self.cancelled = true
		}
	}
	
	@objc public func job(job: AnyObject, didProgress: Double) {
		self.reportProgress(didProgress, forKey: unsafeAddressOf(job).hashValue)
	}
	
	/** Print a message to the debug log. The message is sent to the console asynchronously (but ordered) and prepended
	with the 'job ID'. No messages will be logged when not compiled in debug mode. */
	public func log(message: String, file: StaticString = __FILE__, line: UInt = __LINE__) {
		#if DEBUG
			let id = self.jobID
			dispatch_async(dispatch_get_main_queue()) {
				print("[\(id)] \(message)")
			}
		#endif
	}

	#if DEBUG
	private var timeComponents: [String: Double] = [:]
	
	func reportTime(component: String, time: Double) {
		mutex.locked {
			if let t = self.timeComponents[component] {
				self.timeComponents[component] = t + time
			}
			else {
				self.timeComponents[component] = time
			}
		}
	}
	#endif
}

/** A pthread-based recursive mutex lock. */
public class Mutex {
	private var mutex: pthread_mutex_t = pthread_mutex_t()

	public init() {
		var attr: pthread_mutexattr_t = pthread_mutexattr_t()
		pthread_mutexattr_init(&attr)
		pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE)

		let err = pthread_mutex_init(&self.mutex, &attr)
		pthread_mutexattr_destroy(&attr)

		switch err {
		case 0:
			// Success
			break

		case EAGAIN:
			fatalError("Could not create mutex: EAGAIN (The system temporarily lacks the resources to create another mutex.)")

		case EINVAL:
				fatalError("Could not create mutex: invalid attributes")

		case ENOMEM:
			fatalError("Could not create mutex: no memory")

		default:
			fatalError("Could not create mutex, unspecified error \(err)")
		}
	}

	private final func lock() {
		let ret = pthread_mutex_lock(&self.mutex)
		switch ret {
		case 0:
			// Success
			break

		case EDEADLK:
			fatalError("Could not lock mutex: a deadlock would have occurred")

		case EINVAL:
			fatalError("Could not lock mutex: the mutex is invalid")

		default:
			fatalError("Could not lock mutex: unspecified error \(ret)")
		}
	}

	private final func unlock() {
		let ret = pthread_mutex_unlock(&self.mutex)
		switch ret {
		case 0:
			// Success
			break

		case EPERM:
			fatalError("Could not unlock mutex: thread does not hold this mutex")

		case EINVAL:
			fatalError("Could not unlock mutex: the mutex is invalid")

		default:
			fatalError("Could not unlock mutex: unspecified error \(ret)")
		}
	}

	deinit {
		pthread_mutex_destroy(&self.mutex)
	}

	/** Execute the given block while holding a lock to this mutex. */
	public final func locked<T>(file: StaticString = __FILE__, line: UInt = __LINE__, @noescape block: () -> (T)) -> T {
		#if DEBUG
			let start = CFAbsoluteTimeGetCurrent()
		#endif
		self.lock()
		let ret: T = block()
		self.unlock()
		#if DEBUG
			let duration = CFAbsoluteTimeGetCurrent() - start
			if duration > 0.05 {
				trace("Mutex held for \(duration)s by \(file):\(line)")
			}
		#endif
		return ret
	}
}

/** Future represents a result of a (potentially expensive) calculation. Code that needs the result of the
operation express their interest by enqueuing a callback with the get() function. The callback gets called immediately
if the result of the calculation was available in cache, or as soon as the result has been calculated. 

The calculation itself is done by the 'producer' block. When the producer block is changed, the cached result is 
invalidated (pre-registered callbacks may still receive the stale result when it has been calculated). */
public class Future<T> {
	public typealias Callback = Batch<T>.Callback
	public typealias Producer = (Job, Callback) -> ()
	private var batch: Batch<T>?
	private let mutex: Mutex = Mutex()
	
	let producer: Producer
	let timeLimit: Double?
	
	public init(_ producer: Producer, timeLimit: Double? = nil)  {
		self.producer = once(producer)
		self.timeLimit = timeLimit
	}
	
	private func calculate() {
		self.mutex.locked {
			assert(batch != nil, "calculate() called without a current batch")
			
			if let batch = self.batch {
				if let tl = timeLimit {
					// Set a timer to cancel this job
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(tl * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
						batch.log("Timed out after \(tl) seconds")
						batch.expire()
					}
				}
				batch.async {
					self.producer(batch, batch.satisfy)
				}
			}
		}
	}
	
	/** Abort calculating the result (if calculation is in progress). Registered callbacks will not be called (when 
	callbacks are already being called, this will be finished).*/
	public func cancel() {
		self.mutex.locked {
			batch?.cancel()
		}
	}
	
	/** Abort calculating the result (if calculation is in progress). Registered callbacks may still be called. */
	public func expire() {
		self.mutex.locked {
			batch?.expire()
		}
	}
	
	public var cancelled: Bool { get {
		return self.mutex.locked { () -> Bool in
			return batch?.cancelled ?? false
		}
	} }
	
	/** Returns the result of the current calculation run, or nil if that calculation hasn't started yet or is still
	 running. Use get() to start a calculation and await the result. */
	public var result: T? { get {
		return self.mutex.locked {
			return batch?.cached ?? nil
		}
	} }
	
	/** Request the result of this future. There are three scenarios:
	- The future has not yet been calculated. In this case, calculation will start in the queue specified in the `queue`
	  variable. The callback will be enqueued to receive the result as soon as the calculation finishes. 
	- Calculation of the future is in progress. The callback will be enqueued on a waiting list, and will be called as 
	  soon as the calculation has finished.
	- The future has already been calculated. In this case the callback is called immediately with the result.
	
	Note that the callback may not make any assumptions about the queue or thread it is being called from. Callees should
	therefore not block. 
	
	The get() function performs work in its own Job.	If a job is set as parameter, this job will be a child of the 
	given job, and will use its preferred queue. Otherwise it will perform the work in the user initiated QoS concurrent
	queue. This function always returns its own child Job. */
	public func get(job: Job? = nil, _ callback: Callback) -> Job {
		var first = false
		self.mutex.locked {
			if self.batch == nil {
				first = true
				if let j = job {
					self.batch = Batch<T>(parent: j)
				}
				else {
					self.batch = Batch<T>(queue: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
				}
			}

			batch!.enqueue(callback)
		}

		if(first) {
			calculate()
		}
		return batch!
	}
}

public class Batch<T>: Job {
	public typealias Callback = (T) -> ()
	private var cached: T? = nil
	private var waitingList: [Callback] = []
	
	private var satisfied: Bool { get {
		return cached != nil
	} }
	
	override init(queue: dispatch_queue_t) {
		super.init(queue: queue)
	}
	
	override init(parent: Job) {
		super.init(parent: parent)
	}
	
	/** Called by a producer to return the result of a job. This method will call all callbacks on the waiting list (on the
	main thread) and subsequently empty the waiting list. Enqueue can only be called once on a batch. */
	private func satisfy(value: T) {
		self.mutex.locked {
			assert(cached == nil, "Batch.satisfy called with cached!=nil: \(cached) \(value)")
			assert(!satisfied, "Batch already satisfied")

			self.cached = value
			for waiting in self.waitingList {
				self.async {
					waiting(value)
				}
			}
			self.waitingList = []
		}
	}
	
	/** Expire is like cancel, only the waiting consumers are not removed from the waiting list. This allows a job to
	return a partial result (by calling the callback while job.cancelled is already true) */
	func expire() {
		self.mutex.locked {
			if !self.satisfied {
				self.cancelled = true
			}
		}
	}
	
	/** Cancel this job and remove all waiting listeners (they will never be called back). */
	public override func cancel() {
		self.mutex.locked {
			if !self.satisfied {
				self.waitingList.removeAll(keepCapacity: false)
				self.cancelled = true
			}
			super.cancel()
		}
	}
	
	func enqueue(callback: Callback) {
		self.mutex.locked {
			if satisfied {
				dispatch_async(self.queue) { [unowned self] in
					callback(self.cached!)
				}
			}
			else {
				assert(!cancelled, "Cannot enqueue on a Future that is cancelled")
				self.waitingList.append(callback)
			}
		}
	}
}