import Foundation

/** Records the time taken to execute the given block and writes it to the console. In release builds, the block is simply
called and no timing information is gathered. **/
internal func QBETime(description: String, items: Int, itemType: String, block: () -> ()) {
	#if DEBUG
		let t = CFAbsoluteTimeGetCurrent()
		block()
		let d = CFAbsoluteTimeGetCurrent() - t
		println("QBETime\t\(description)\t\(items) \(itemType):\t\(d);\t\(Double(items)/d) \(itemType)/s")
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

/** QBEFuture represents a result of a (potentially expensive) calculation. Code that needs the result of the
operation express their interest by enqueuing a callback with the get() function. The callback gets called immediately
if the result of the calculation was available in cache, or as soon as the result has been calculated. 

The calculation itself is done by the 'producer' block. When the producer block is changed, the cached result is 
invalidated (pre-registered callbacks may still receive the stale result when it has been calculated). **/
class QBEFuture<T> {
	typealias Callback = QBEBatch<T>.Callback
	typealias Producer = (Callback) -> ()
	private var batch: QBEBatch<T>?
	
	var calculating: Bool { get {
		return batch != nil
	} }
	
	let producer: Producer?
	
	init(_ producer: Producer?)  {
		self.producer = producer
	}
	
	deinit {
		batch?.cancel()
	}
	
	private func calculate() {
		assert(batch != nil, "calculate() called without a current batch")
		
		if let batch = self.batch {
			if let p = producer {
				p(batch.satisfy)
			}
			else {
				batch.satisfy(nil)
			}
		}
	}
	
	func get(callback: Callback) {
		if batch == nil {
			batch = QBEBatch<T>()
			batch!.enqueue(callback)
			calculate()
		}
		else {
			batch!.enqueue(callback)
		}
	}
}

private class QBEBatch<T> {
	typealias Callback = (T?) -> ()
	
	private var cached: T? = nil
	private var satisfied: Bool = false
	var waitingList: [Callback] = []
	
	private func satisfy(value: T?) {
		assert(cached == nil, "QBEBatch.satisfy called with cached!=nil")
		assert(!satisfied, "QBEBatch already satisfied")
		
		cached = value
		satisfied = true
		for waiting in waitingList {
			QBEAsyncMain {
				waiting(value)
			}
		}
		waitingList = []
	}
	
	func cancel() {
		if !satisfied {
			waitingList = []
		}
	}
	
	func enqueue(callback: Callback) {
		if satisfied {
			QBEAsyncMain {
				callback(self.cached)
			}
		}
		else {
			waitingList.append(callback)
		}
	}
}