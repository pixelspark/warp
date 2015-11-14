import Foundation
import WarpCore

/** Indicates a type of sentence. */
public enum QBESentenceVariant {
	case Neutral // "Table x from y"
	case Read // "Read table x from y"
	case Write // "Write to table x from y"
}

/** Represents a data manipulation step. Steps usually connect to (at least) one previous step and (sometimes) a next step.
The step transforms a data manipulation on the data produced by the previous step; the results are in turn used by the 
next. Steps work on two datasets: the 'example' data set (which is used to let the user design the data manipulation) and
the 'full' data (which is the full dataset on which the final data operations are run). 

Subclasses of QBEStep implement the data manipulation in the apply function, and should implement the description method
as well as coding methods. The explanation variable contains a user-defined comment to an instance of the step. */
public class QBEStep: NSObject, NSCoding {
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
		previous = aDecoder.decodeObjectForKey("previousStep") as? QBEStep
		next = aDecoder.decodeObjectForKey("nextStep") as? QBEStep
		alternatives = aDecoder.decodeObjectForKey("alternatives") as? [QBEStep]
	}

	public func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(previous, forKey: "previousStep")
		coder.encodeObject(next, forKey: "nextStep")
		coder.encodeObject(alternatives, forKey: "alternatives")
	}

	/** Creates a data object representing the result of an 'example' calculation of the result of this QBEStep. The
	maxInputRows parameter defines the maximum number of input rows a source step should generate. The maxOutputRows
	parameter defines the maximum number of rows a step should strive to produce. */
	public func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		if let p = self.previous {
			p.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: {(data) in
				switch data {
					case .Success(let d):
						self.apply(d, job: job, callback: callback)
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			})
		}
		else {
			callback(.Failure(NSLocalizedString("This step requires a previous step, but none was found.", comment: "")))
		}
	}
	
	public func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let p = self.previous {
			p.fullData(job, callback: {(data) in
				switch data {
					case .Success(let d):
						self.apply(d, job: job, callback: callback)
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			})
		}
		else {
			callback(.Failure(NSLocalizedString("This step requires a previous step, but none was found.", comment: "")))
		}
	}

	public var mutableData: QBEMutableData? { get {
		return nil
	} }
	
	/** Description returns a locale-dependent explanation of the step. It can (should) depend on the specific
	configuration of the step. */
	public final func explain(locale: QBELocale) -> String {
		return sentence(locale, variant: .Neutral).stringValue
	}

	public func sentence(locale: QBELocale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([])
	}
	
	public func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		fatalError("Child class of QBEStep should implement apply()")
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference 
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	public func willSaveToDocument(atURL: NSURL) {
	}
	
	/** This method is called right after a document has been loaded from disk. */
	public func didLoadFromDocument(atURL: NSURL) {
	}

	/** Returns whether this step can be merged with the specified previous step. */
	public func mergeWith(prior: QBEStep) -> QBEStepMerge {
		return QBEStepMerge.Impossible
	}
}

public enum QBEStepMerge {
	case Impossible
	case Advised(QBEStep)
	case Possible(QBEStep)
	case Cancels
}

/** QBEFileReference is the class to be used by steps that need to reference auxiliary files. It employs Apple's App
Sandbox API to create 'secure bookmarks' to these files, so that they can be referenced when opening the Warp document
again later. Steps should call bookmark() on all their references from the willSavetoDocument method, and call resolve()
on all file references inside didLoadFromDocument. In addition they should store both the 'url' as well as the 'bookmark'
property when serializing a file reference (in encodeWithCoder).

On non-sandbox builds, QBEFileReference will not be able to resolve bookmarks to URLs, and it will return the original URL
(which will allow regular unlimited access). */
public enum QBEFileReference: Equatable {
	case Bookmark(NSData)
	case ResolvedBookmark(NSData, NSURL)
	case URL(NSURL)
	
	public static func create(url: NSURL?, _ bookmark: NSData?) -> QBEFileReference? {
		if bookmark == nil {
			if url != nil {
				return QBEFileReference.URL(url!)
			}
			else {
				return nil
			}
		}
		else {
			if url == nil {
				return QBEFileReference.Bookmark(bookmark!)
			}
			else {
				return QBEFileReference.ResolvedBookmark(bookmark!, url!)
			}
		}
	}
	
	public func bookmark(relativeToDocument: NSURL) -> QBEFileReference? {
		switch self {
		case .URL(let u):
			do {
				let bookmark = try u.bookmarkDataWithOptions(NSURLBookmarkCreationOptions.WithSecurityScope, includingResourceValuesForKeys: nil, relativeToURL: nil)
				do {
					let resolved = try NSURL(byResolvingBookmarkData: bookmark, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil)
					return QBEFileReference.ResolvedBookmark(bookmark, resolved)
				}
				catch let error as NSError {
					QBELog("Failed to resolve just-created bookmark: \(error)")
				}
			}
			catch let error as NSError {
				QBELog("Could not create bookmark for url \(u): \(error)")
			}
			return self
			
		case .Bookmark(_):
			return self
			
		case .ResolvedBookmark(_,_):
			return self
		}
	}
	
	public func resolve(relativeToDocument: NSURL) -> QBEFileReference? {
		switch self {
		case .URL(_):
			return self
			
		case .ResolvedBookmark(let b, let oldURL):
			do {
				let u = try NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil)
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			catch let error as NSError {
				QBELog("Could not re-resolve bookmark \(b) to \(oldURL) relative to \(relativeToDocument): \(error)")
			}
			
			return self
			
		case .Bookmark(let b):
			do {
				let u = try NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil)
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			catch let error as NSError {
				QBELog("Could not resolve secure bookmark \(b): \(error)")
			}
			return self
		}
	}
	
	public var bookmark: NSData? { get {
		switch self {
			case .ResolvedBookmark(let d, _): return d
			case .Bookmark(let d): return d
			default: return nil
		}
	} }
	
	public var url: NSURL? { get {
		switch self {
			case .URL(let u): return u
			case .ResolvedBookmark(_, let u): return u
			default: return nil
		}
	} }
}

public func == (lhs: QBEFileReference, rhs: QBEFileReference) -> Bool {
	if let lu = lhs.url, ru = rhs.url {
		return lu == ru
	}
	else if let lb = lhs.bookmark, rb = rhs.bookmark {
		return lb == rb
	}
	return false
}

/** Component that can write a data set to a file in a particular format. */
public protocol QBEFileWriter: NSObjectProtocol, NSCoding {
	/** A description of the type of file exported by instances of this file writer, e.g. "XML file". */
	static func explain(fileExtension: String, locale: QBELocale) -> String

	/** The UTIs and file extensions supported by this type of file writer. */
	static var fileTypes: Set<String> { get }

	/** Create a file writer with default settings for the given locale. */
	init(locale: QBELocale, title: String?)

	/** Write data to the given URL. The file writer calls back once after success or failure. */
	func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ())

	/** Returns a sentence for configuring this writer */
	func sentence(locale: QBELocale) -> QBESentence?
}

/** The transpose step implements a row-column switch. It has no configuration and relies on the QBEData transpose()
implementation to do the actual work. */
public class QBETransposeStep: QBEStep {
	public override func apply(data: QBEData, job: QBEJob? = nil, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(data.transpose()))
	}

	public override func sentence(locale: QBELocale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([QBESentenceText(NSLocalizedString("Switch rows/columns", comment: ""))])
	}

	public override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if prior is QBETransposeStep {
			return QBEStepMerge.Cancels
		}
		return QBEStepMerge.Impossible
	}
}