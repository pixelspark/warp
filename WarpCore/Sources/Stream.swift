/* Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
import Foundation

/** Indicates the status of a streaming data source. */
public enum StreamStatus {
	/** The source has more data that will be provided in subsequent calls back (i.e. may already be in flight), or 
	after requesting additional data. */
	case hasMore

	/** The source has no more data and subsequent calls back will not provide any. Additional requests for data may
	fail or be an error. */
	case finished
}

/** A Sink is a function used as a callback in response to Stream.fetch. It receives a set of rows from the stream
as well as a boolean indicating whether the next call of fetch() will return any rows (true) or not (false). */
public typealias Sink = (Fallible<Array<Tuple>>, StreamStatus) -> ()

/** The default number of rows that a Stream will send to a consumer upon request through Stream.fetch. */
public let StreamDefaultBatchSize = 256

/** Stream represents a data set that can be streamed (consumed in batches). This allows for efficient processing of
data sets for operations that do not require memory (e.g. a limit or filter can be performed almost statelessly). The 
stream implements a single method (fetch) that allows batch fetching of result rows. The size of the batches are defined
by the stream (for now).

Streams are drained using concurrent calls to the 'fetch' method (multiple 'wavefronts'). */
public protocol Stream {
	/** The column names associated with the rows produced by this stream. */
	func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ())
	
	/** Request the next batch of rows from the stream; when it is available, asynchronously call (on the main queue) 
	the specified callback. If the callback is to perform computations, it should queue this work to another queue. If 
	the stream is empty (e.g. hasNext was false when fetch was last called), fetch calls your callback with hasNext set 
	to false once again. Preferably, fetch does not block when called.
	
	Should the stream encounter an error, the callback is called with a failed data set and hasNext set to false. 
	Consumers should stop fetch()ing when either the data set is failed or hasNext is false.
	
	Note that fetch may be called multiple times concurrently (i.e. multiple 'wavefronts') - it is the stream's job to 
	ensure ordered and consistent delivery of data. Streams may use a serial dispatch queue to serialize requests if 
	necessary. 
	
	The consumer callee should not make any assumptions about the queue on which the callback is dispatched, or whether 
	it is asynchronous. */
	func fetch(_ job: Job, consumer: @escaping Sink)
	
	/** Create a copy of this stream. The copied stream is reset to the initial position (e.g. will return the first row
	of the data set during the first call to fetch on the copy). */
	func clone() -> Stream
}

/** This class manages the multithreaded retrieval of data from a stream. It will make concurrent calls to a stream's
fetch function ('wavefronts') and call the method onReceiveRows each time it receives rows. When all results are in, the
onDoneReceiving method is called. The subclass should implement onReceiveRows, onDoneReceiving and onError.
The class also exists to avoid issues with reference counting (the sink closure needs to reference itself). */
open class StreamPuller {
	public let job: Job
	public let stream: Stream
	public let mutex = Mutex()

	private let concurrentWavefronts: Int
	private var outstandingWavefronts = 0
	private var lastStartedWavefront = 0
	private var lastSinkedWavefront = 0
	private var earlyResults: [Int : Fallible<[Tuple]>] = [:]
	private var done = false

	public init(stream: Stream, job: Job) {
		self.stream = stream
		self.job = job
		self.concurrentWavefronts = ProcessInfo.processInfo.processorCount
	}

	private func startWavefront() {
		/* The fetch() must happen inside the mutex lock, because we do not want another fetch to come in between
		(wavefront ID must match the order in which fetch is called) */
		self.mutex.locked {
			self.lastStartedWavefront += 1
			self.outstandingWavefronts += 1
			let waveFrontId = self.lastStartedWavefront

			self.stream.fetch(self.job, consumer: { (rows, streamStatus) in
				self.mutex.locked {
					/** Some fetches may return earlier than others, but we need to reassemble them in the
					correct order. Therefore we keep track of a 'wavefront ID'. If the last wavefront that was
					'sinked' was this wavefront's id minus one, we can sink this one directly. Otherwise we need
					to put it in a queue for later sinking. */
					if self.lastSinkedWavefront == waveFrontId-1 {
						/* This result arrives just in time (all predecessors have been received already). Sink
						it directly. */
						self.lastSinkedWavefront = waveFrontId
						self.sink(rows, hasNext: streamStatus == .hasMore)

						// Maybe now we can sink other results we already received, but were too early.
						while let earlierRows = self.earlyResults[self.lastSinkedWavefront+1] {
							self.earlyResults.removeValue(forKey: self.lastSinkedWavefront+1)
							self.lastSinkedWavefront += 1
							self.sink(earlierRows, hasNext: streamStatus == .hasMore)
						}
					}
					else {
						/* This result has arrived too early; store it so we can sink it as soon as all
						predecessors have arrived */
						self.earlyResults[waveFrontId] = rows
					}
				}
			})
		}
	}

	/** Start up to self.concurrentFetches number of fetch 'wavefronts' that will deliver their data to the
	'sink' funtion. */
	public func start() {
		mutex.locked {
			while self.outstandingWavefronts < self.concurrentWavefronts {
				self.startWavefront()
			}
		}
	}

	/** Receives batches of data from streams and appends them to the buffer of rows. It will spawn new wavefronts
	through 'start' each time it is called, unless the stream indicates there are no more records. When the last
	wavefront has reported in, sink will call self.callback. */
	private final func sink(_ rows: Fallible<Array<Tuple>>, hasNext: Bool) {
		self.mutex.locked {
			if self.outstandingWavefronts == 0 {
				// We errored, any following wave fronts are ignored
				return
			}

			self.outstandingWavefronts -= 1

			switch rows {
			case .success(let r):
				self.onReceiveRows(r) { receiveResult in
					self.mutex.locked {
						switch receiveResult {
						case .failure(let e):
							self.outstandingWavefronts = 0
							self.onError(e)

						case .success(_):
							if !hasNext {
								let isLast = self.outstandingWavefronts == 0
								if isLast {
									/* This was the last wavefront that was running, and there are no more rows according 
									to the source stream. Therefore we are now done fetching all data from the stream. */
									if !self.done {
										self.done = true
										self.onDoneReceiving()
									}
								}
								else {
									/* There is no more data according to the stream, but several rows still have to come 
									in as other wavefronts are still running. The last one will turn off the lights, 
									right now we can just wait. */
								}
							}
							else {
								// If the stream indicates there are more rows, fetch them (start new wavefronts)
								self.job.async {
									self.start()
									return
								}
							}
						}
					}
				}

			case .failure(let errorMessage):
				self.outstandingWavefronts = 0
				self.onError(errorMessage)
			}
		}
	}

	open func onReceiveRows(_ rows: [Tuple], callback: @escaping (Fallible<Void>) -> ()) {
		fatalError("Meant to be overridden")
	}

	open func onDoneReceiving() {
		fatalError("Meant to be overridden")
	}

	open func onError(_ error: String) {
		fatalError("Meant to be overridden")
	}
}

internal class RasterStreamPuller: StreamPuller {
	var data: [Tuple] = []
	let callback: (Fallible<Raster>, StreamStatus) -> ()
	let columns: OrderedSet<Column>
	let delivery: Delivery

	init(stream: Stream, job: Job, columns: OrderedSet<Column>, deliver: Delivery = .onceComplete, callback: @escaping (Fallible<Raster>, StreamStatus) -> ()) {
		self.callback = callback
		self.columns = columns
		self.delivery = deliver
		super.init(stream: stream, job: job)
	}

	override func onReceiveRows(_ rows: [Tuple], callback: @escaping (Fallible<Void>) -> ()) {
		self.mutex.locked {
			// Append the rows to our buffered raster
			self.data.append(contentsOf: rows)
			callback(.success())

			if self.delivery == .incremental {
				self.deliver(status: .hasMore)
			}
		}
	}

	override func onDoneReceiving() {
		self.deliver(status: .finished)
	}

	private func deliver(status: StreamStatus) {
		job.async {
			self.mutex.locked {
				self.callback(.success(Raster(data: self.data, columns: self.columns, readOnly: true)), status)
			}
		}
	}

	override func onError(_ error: String) {
		job.async {
			self.callback(.failure(error), .finished)
		}
	}
}

public final class ErrorStream: Stream {
	private let error: String
	
	public init(_ error: String) {
		self.error = error
	}
	
	public func fetch(_ job: Job, consumer: @escaping Sink) {
		consumer(.failure(self.error), .finished)
	}
	
	public func clone() -> Stream {
		return ErrorStream(self.error)
	}
	
	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.failure(self.error))
	}
}

/** 
A stream that never produces any data (but doesn't return errors either). */
public final class EmptyStream: Stream {
	public init() {
	}

	public func fetch(_ job: Job, consumer: @escaping Sink) {
		consumer(.success([]), .finished)
	}
	
	public func clone() -> Stream {
		return EmptyStream()
	}
	
	public func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success([]))
	}
}

/** 
A stream that sources from a Swift generator of Tuple. */
open class SequenceStream: Stream {
	private let sequence: AnySequence<Fallible<Tuple>>
	private var generator: AnyIterator<Fallible<Tuple>>
	private let columns: OrderedSet<Column>
	private var position: Int = 0
	private var rowCount: Int? = nil // nil = number of rows is yet unknown
	private var queue = DispatchQueue(label: "nl.pixelspark.Warp.SequenceStream", attributes: [])
	private var error: String? = nil
	
	public init(_ sequence: AnySequence<Fallible<Tuple>>, columns: OrderedSet<Column>, rowCount: Int? = nil) {
		self.sequence = sequence
		self.generator = sequence.makeIterator()
		self.columns = columns
		self.rowCount = rowCount
	}
	
	open func fetch(_ job: Job, consumer: @escaping Sink) {
		if let e = error {
			consumer(.failure(e), .finished)
			return
		}

		queue.async {
			job.time("sequence", items: StreamDefaultBatchSize, itemType: "rows") {
				var done = false
				var rows :[Tuple] = []
				rows.reserveCapacity(StreamDefaultBatchSize)
				
				for _ in 0..<StreamDefaultBatchSize {
					if let next = self.generator.next() {
						switch next {
							case .success(let f):
								rows.append(f)

							case .failure(let e):
								self.error = e
								done = true
								break
						}
					}
					else {
						done = true
					}

					if done {
						break
					}
				}
				self.position += rows.count
				if let rc = self.rowCount, rc > 0 {
					job.reportProgress(Double(self.position) / Double(rc), forKey: Unmanaged.passUnretained(self).toOpaque().hashValue)
				}

				job.async {
					if let e = self.error {
						consumer(.failure(e), .finished)
					}
					else {
						consumer(.success(Array(rows)), done ? .finished : .hasMore)
					}
				}
			}
		}
	}
	
	open func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success(self.columns))
	}
	
	open func clone() -> Stream {
		return SequenceStream(self.sequence, columns: self.columns, rowCount: self.rowCount)
	}
}
