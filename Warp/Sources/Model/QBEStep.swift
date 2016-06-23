import Foundation
import WarpCore

/** Indicates a type of sentence. */
public enum QBESentenceVariant {
	case neutral // "Table x from y"
	case read // "Read table x from y"
	case write // "Write to table x from y"
}

/** Represents a data manipulation step. Steps usually connect to (at least) one previous step and (sometimes) a next step.
The step transforms a data manipulation on the data produced by the previous step; the results are in turn used by the 
next. Steps work on two datasets: the 'example' data set (which is used to let the user design the data manipulation) and
the 'full' data (which is the full dataset on which the final data operations are run). 

Subclasses of QBEStep implement the data manipulation in the apply function, and should implement the description method
as well as coding methods. The explanation variable contains a user-defined comment to an instance of the step. */
public class QBEStep: QBEConfigurable, NSCoding {
	public static let dragType = "nl.pixelspark.Warp.Step"

	public var previous: QBEStep? { didSet {
		assert(previous != self, "A step cannot be its own previous step")
		previous?.next = self
		} }

	public var alternatives: [QBEStep]?
	public weak var next: QBEStep?

	required override public init() {
	}

	public init(previous: QBEStep?) {
		self.previous = previous
	}

	public required init(coder aDecoder: NSCoder) {
		previous = aDecoder.decodeObject(forKey: "previousStep") as? QBEStep
		next = aDecoder.decodeObject(forKey: "nextStep") as? QBEStep
		alternatives = aDecoder.decodeObject(forKey: "alternatives") as? [QBEStep]
	}

	public func encode(with coder: NSCoder) {
		coder.encode(previous, forKey: "previousStep")
		coder.encode(next, forKey: "nextStep")
		coder.encode(alternatives, forKey: "alternatives")
	}

	/** Creates a data object representing the result of an 'example' calculation of the result of this QBEStep. The
	maxInputRows parameter defines the maximum number of input rows a source step should generate. The maxOutputRows
	parameter defines the maximum number of rows a step should strive to produce. */
	public func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Dataset>) -> ()) {
		if let p = self.previous {
			p.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: {(data) in
				switch data {
					case .success(let d):
						self.apply(d, job: job, callback: callback)
					
					case .failure(let error):
						callback(.failure(error))
				}
			})
		}
		else {
			callback(.failure(NSLocalizedString("This step requires a previous step, but none was found.", comment: "")))
		}
	}
	
	public func fullDataset(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		if let p = self.previous {
			p.fullDataset(job, callback: {(data) in
				switch data {
					case .success(let d):
						self.apply(d, job: job, callback: callback)
					
					case .failure(let error):
						callback(.failure(error))
				}
			})
		}
		else {
			callback(.failure(NSLocalizedString("This step requires a previous step, but none was found.", comment: "")))
		}
	}

	public var mutableDataset: MutableDataset? { get {
		return nil
	} }
	
	/** Description returns a locale-dependent explanation of the step. It can (should) depend on the specific
	configuration of the step. */
	public final func explain(_ locale: Language) -> String {
		return sentence(locale, variant: .neutral).stringValue
	}

	public override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([])
	}
	
	public func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		fatalError("Child class of QBEStep should implement apply()")
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference 
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	public func willSaveToDocument(_ atURL: URL) {
	}
	
	/** This method is called right after a document has been loaded from disk. */
	public func didLoadFromDocument(_ atURL: URL) {
	}

	/** Returns whether this step can be merged with the specified previous step. */
	public func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		return QBEStepMerge.impossible
	}
}

public enum QBEStepMerge {
	case impossible
	case advised(QBEStep)
	case possible(QBEStep)
	case cancels
}

/** Component that can write a data set to a file in a particular format. */
public protocol QBEFileWriter: NSObjectProtocol, NSCoding {
	/** A description of the type of file exported by instances of this file writer, e.g. "XML file". */
	static func explain(_ fileExtension: String, locale: Language) -> String

	/** The UTIs and file extensions supported by this type of file writer. */
	static var fileTypes: Set<String> { get }

	/** Create a file writer with default settings for the given locale. */
	init(locale: Language, title: String?)

	/** Write data to the given URL. The file writer calls back once after success or failure. */
	func writeDataset(_ data: Dataset, toFile file: URL, locale: Language, job: Job, callback: (Fallible<Void>) -> ())

	/** Returns a sentence for configuring this writer */
	func sentence(_ locale: Language) -> QBESentence?
}

/** The transpose step implements a row-column switch. It has no configuration and relies on the Dataset transpose()
implementation to do the actual work. */
public class QBETransposeStep: QBEStep {
	public override func apply(_ data: Dataset, job: Job? = nil, callback: (Fallible<Dataset>) -> ()) {
		callback(.success(data.transpose()))
	}

	public override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([QBESentenceText(NSLocalizedString("Switch rows/columns", comment: ""))])
	}

	public override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		if prior is QBETransposeStep {
			return QBEStepMerge.cancels
		}
		return QBEStepMerge.impossible
	}
}
