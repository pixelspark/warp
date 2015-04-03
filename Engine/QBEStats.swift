import Foundation

protocol QBEDistribution {
	func inverse(p: Double) -> Double
}

struct QBENormalDistribution: QBEDistribution {
	func inverse(p: Double) -> Double {
		return ltqnorm(p)
	}
}

/** Represents a set of values samples from a stochastic variable. **/
class QBESample {
	typealias ValueType = Double
	let mean: ValueType
	let stdev: ValueType
	let sum: ValueType
	let n: Int
	
	convenience init(_ values: [ValueType]) {
		self.init(values: values)
	}
	
	init(values: [ValueType]) {
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
	sample. **/
	func confidenceInterval(confidenceLevel: ValueType, distribution: QBEDistribution = QBENormalDistribution()) -> (ValueType, ValueType) {
		let margin = (1.0 - confidenceLevel) / 2.0
		let deviates = distribution.inverse(1.0 - margin) - distribution.inverse(margin)
		return (self.mean - deviates * self.stdev, self.mean + deviates * self.stdev)
	}
}

/** Represents a moving sample of a variable. **/
class QBEMoving: NSObject, NSCoding {
	typealias ValueType = Double
	private(set) var values: [ValueType?]
	let size: Int
	
	init(size: Int, items: [ValueType] = []) {
		values = items.optionals
		self.size = size
		super.init()
		trim()
	}
	
	required init(coder: NSCoder) {
		self.values = (coder.decodeObjectForKey("values") as? [ValueType] ?? []).optionals
		self.size = coder.decodeIntegerForKey("size")
		super.init()
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(Array.filterNils(values), forKey: "values")
		aCoder.encodeInteger(size, forKey: "size")
	}
	
	func add(value: ValueType) {
		values.append(value)
		trim()
	}
	
	private func trim() {
		while values.count > size {
			values.removeAtIndex(0)
		}
	}
	
	var sample: QBESample {
		get {
			return QBESample(Array.filterNils(values))
		}
	}
}