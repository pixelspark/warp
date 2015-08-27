import Foundation

public protocol QBEDistribution {
	func inverse(p: Double) -> Double
}

public struct QBENormalDistribution: QBEDistribution {
	public func inverse(p: Double) -> Double {
		return ltqnorm(p)
	}
}

/** Represents a set of values samples from a stochastic variable. */
public struct QBESample {
	public typealias ValueType = Double
	public let mean: ValueType
	public let stdev: ValueType
	public let sum: ValueType
	public let n: Int
	
	public init(_ values: [ValueType]) {
		self.init(values: values)
	}
	
	public init(values: [ValueType]) {
		self.sum = values.reduce(ValueType(0.0), combine: { (u, t) -> ValueType in
			return t + u
		})
		
		self.n = values.count
		let mean = self.sum / ValueType(n)
		
		let sumOfSquares = values.reduce(ValueType(0.0), combine: {(u, t) -> ValueType in
			return pow(t - mean, 2)
		})
		self.mean = mean
		self.stdev = sqrt(sumOfSquares)
	}
	
	/** Returns a confidence interval in which a value from the population falls with 90% probability, based on this
	sample. */
	public func confidenceInterval(confidenceLevel: ValueType, distribution: QBEDistribution = QBENormalDistribution()) -> (ValueType, ValueType) {
		let margin = (1.0 - confidenceLevel) / 2.0
		let deviates = distribution.inverse(1.0 - margin) - distribution.inverse(margin)
		return (self.mean - deviates * self.stdev, self.mean + deviates * self.stdev)
	}
}

/** Represents a moving sample of a variable. */
public class QBEMoving: NSObject, NSCoding {
	public typealias ValueType = Double
	private(set) var values: [ValueType?]
	let size: Int
	
	public init(size: Int, items: [ValueType] = []) {
		values = items.optionals
		self.size = size
		super.init()
		trim()
	}
	
	public required init?(coder: NSCoder) {
		self.values = (coder.decodeObjectForKey("values") as? [ValueType] ?? []).optionals
		self.size = coder.decodeIntegerForKey("size")
		super.init()
	}
	
	public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(Array.filterNils(values), forKey: "values")
		aCoder.encodeInteger(size, forKey: "size")
	}
	
	public func add(value: ValueType) {
		values.append(value)
		trim()
	}
	
	private func trim() {
		while values.count > size {
			values.removeAtIndex(0)
		}
	}
	
	public var sample: QBESample {
		get {
			return QBESample(Array.filterNils(values))
		}
	}
}

/** Implements a reservoir that can hold a predefined maximum number of elements. The reservoir is filled using the fill
function. Once the reservoir is 'full', it will start randomly replacing items in the reservoir with new items. It does
this in such a way that the reservoir at any point in time contains a uniform random sample of the samples it has seen
up to that point. If the reservoir is not completely filled, the sample will contain all items that have been fed to the
reservoir up to that point. */
internal class QBEReservoir<ValueType> {
	private(set) var sample: [ValueType] = []
	let sampleSize: Int
	private(set) var samplesSeen: Int = 0

	init(sampleSize: Int) {
		self.sampleSize = sampleSize
	}

	/** Add items to the reservoir. The order of the items does not matter, as the reservoir will perform random sampling
	in a uniform way. Note however that if the reservoir is not filled to at least full capacity, the sample is not 
	randomized in any way (e.g. shuffled). */
	func add(var rows: [ValueType]) {
		// Reservoir initial fill
		if sample.count < sampleSize {
			let length = sampleSize - sample.count

			sample.appendContentsOf(rows[0..<min(length,rows.count)])
			self.samplesSeen += min(length,rows.count)

			if length >= rows.count {
				rows = []
			}
			else {
				rows = Array(rows[min(length,rows.count)..<rows.count])
			}
		}

		/* Reservoir replace (note: if the sample size is larger than the total number of samples we'll ever recieve,
		this will never execute; the reservoir will then 'sample' all rows it has seen up to that point). */
		if sample.count == sampleSize {
			for i in 0..<rows.count {
				/* The chance of choosing an item starts out at (1/s) and ends at (1/N), where s is the sample size and N
				is the number of actual input rows. */
				let probability = Int.random(0, upper: self.samplesSeen+i)
				if probability < self.sampleSize {
					// Place this sample in the list at the randomly chosen position
					self.sample[probability] = rows[i]
				}
			}

			self.samplesSeen += rows.count
		}
	}
}