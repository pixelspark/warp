import Foundation

/** QBECalculation represents a result of a (potentially expensive) calculation. Code that needs the result of the 
operation express their interest by enqueuing a callback with the get() function. The callback gets called immediately
if the result of the calculation was available in cache, or as soon as the result has been calculated. 

The calculation itself is done by the 'producer' block. When the producer block is changed, the cached result is 
invalidated (pre-registered callbacks will receive the stale result when it has been calculated). **/
class QBECalculation<T> {
	typealias Callback = QBEBatch<T>.Callback
	typealias Producer = (Callback) -> ()
	private var batch: QBEBatch<T>?
	
	var calculating: Bool { get {
		return batch != nil
	} }
	
	var producer: Producer? { didSet {
		if let b = batch {
			b.cancel()
		}
		batch = nil
	} }
	
	init()  {
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
			waiting(value)
		}
		waitingList = []
	}
	
	func cancel() {
		waitingList = []
	}
	
	func enqueue(callback: Callback) {
		if satisfied {
			callback(cached)
		}
		else {
			waitingList.append(callback)
		}
	}
}