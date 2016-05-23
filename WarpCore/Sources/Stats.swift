import Foundation

public protocol Distribution {
	func inverse(p: Double) -> Double
}

public struct NormalDistribution: Distribution {
	/*
	* Lower tail quantile for standard normal distribution function.
	*
	* This function returns an approximation of the inverse cumulative
	* standard normal distribution function.  I.e., given P, it returns
	* an approximation to the X satisfying P = Pr{Z <= X} where Z is a
	* random variable from the standard normal distribution.
	*
	* The algorithm uses a minimax approximation by rational functions
	* and the result has a relative error whose absolute value is less
	* than 1.15e-9.
	*
	* Author:      Peter John Acklam
	* Time-stamp:  2002-06-09 18:45:44 +0200
	* E-mail:      jacklam@math.uio.no
	* WWW URL:     http://www.math.uio.no/~jacklam
	*
	* C implementation adapted from Peter's Perl version
	* Swift implementatino adapted from this C implementation
	*/

	/* Coefficients in rational approximations. */
	private let a = [
		-3.969683028665376e+01,
		2.209460984245205e+02,
		-2.759285104469687e+02,
		1.383577518672690e+02,
		-3.066479806614716e+01,
		2.506628277459239e+00
	]

	private let b = [
		-5.447609879822406e+01,
		1.615858368580409e+02,
		-1.556989798598866e+02,
		6.680131188771972e+01,
		-1.328068155288572e+01
	]

	private let c = [
		-7.784894002430293e-03,
		-3.223964580411365e-01,
		-2.400758277161838e+00,
		-2.549732539343734e+00,
		4.374664141464968e+00,
		2.938163982698783e+00
	]

	private let d = [
		7.784695709041462e-03,
		3.224671290700398e-01,
		2.445134137142996e+00,
		3.754408661907416e+00
	];

	private let low = 0.02425
	private let high = 0.97575

	private func ltqnorm(p: Double) -> Double {
		assert(p >= 0 && p <= 1, "the p value for ltqnorm needs to be [0..1]")

		if p == 0.0 {
			return -Double.infinity
		}
		else if p == 1.0 {
			return Double.infinity
		}
		else if p < low {
			/* Rational approximation for lower region */
			let q = sqrt(-2 * log(p))
			return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
					((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
		}
		else if (p > high) {
			/* Rational approximation for upper region */
			let q  = sqrt(-2*log(1-p))
			let divisor = ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
			return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / divisor

		}
		else {
			/* Rational approximation for central region */
			let q = p - 0.5
			let r = q*q
			return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q /
				(((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)
		}
	}

	public func inverse(p: Double) -> Double {
		return ltqnorm(p)
	}
}

/** Represents a set of values samples from a stochastic variable. */
public struct Sample {
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
	public func confidenceInterval(confidenceLevel: ValueType, distribution: Distribution = NormalDistribution()) -> (ValueType, ValueType) {
		let margin = (1.0 - confidenceLevel) / 2.0
		let deviates = distribution.inverse(1.0 - margin) - distribution.inverse(margin)
		return (self.mean - deviates * self.stdev, self.mean + deviates * self.stdev)
	}
}

/** Represents a moving sample of a variable. */
public class Moving: NSObject, NSCoding {
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
	
	public var sample: Sample {
		get {
			return Sample(Array.filterNils(values))
		}
	}
}

/** Implements a reservoir that can hold a predefined maximum number of elements. The reservoir is filled using the fill
function. Once the reservoir is 'full', it will start randomly replacing items in the reservoir with new items. It does
this in such a way that the reservoir at any point in time contains a uniform random sample of the samples it has seen
up to that point. If the reservoir is not completely filled, the sample will contain all items that have been fed to the
reservoir up to that point. */
public class Reservoir<ValueType> {
	public private(set) var sample: [ValueType] = []
	let sampleSize: Int
	private(set) var samplesSeen: Int = 0

	public init(sampleSize: Int) {
		assert(sampleSize > 0, "reservoir sample size must be 1 or higher")
		self.sampleSize = sampleSize
	}

	public func clear() {
		self.sample = []
		self.samplesSeen = 0
	}

	/** Add items to the reservoir. The order of the items does not matter, as the reservoir will perform random sampling
	in a uniform way. Note however that if the reservoir is not filled to at least full capacity, the sample is not 
	randomized in any way (e.g. shuffled). */
	public func add(inRows: [ValueType]) {
		var rows = inRows
		
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
				let probability = (self.samplesSeen + i) > 0 ? Int.random(0, upper: self.samplesSeen+i) : 0
				if probability < self.sampleSize {
					// Place this sample in the list at the randomly chosen position
					self.sample[probability] = rows[i]
				}
			}

			self.samplesSeen += rows.count
		}
	}
}