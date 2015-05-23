import Foundation

/** Represents a data manipulation step. Steps usually connect to (at least) one previous step and (sometimes) a next step.
The step transforms a data manipulation on the data produced by the previous step; the results are in turn used by the 
next. Steps work on two datasets: the 'example' data set (which is used to let the user design the data manipulation) and
the 'full' data (which is the full dataset on which the final data operations are run). 

Subclasses of QBEStep implement the data manipulation in the apply function, and should implement the description method
as well as coding methods. The explanation variable contains a user-defined comment to an instance of the step. **/
class QBEStep: NSObject {
	static let dragType = "nl.pixelspark.Warp.Step"
	
	/** Creates a data object representing the result of an 'example' calculation of the result of this QBEStep. The
	maxInputRows parameter defines the maximum number of input rows a source step should generate. The maxOutputRows
	parameter defines the maximum number of rows a step should strive to produce. **/
	func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEData) -> ()) {
		if let p = self.previous {
			self.previous?.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: {(data) in
				self.apply(data, job: job, callback: callback)
			})
		}
		else {
			// TODO set an error message
			callback(QBERasterData())
		}
	}
	
	func fullData(job: QBEJob, callback: (QBEData) -> ()) {
		if let p = self.previous {
			p.fullData(job, callback: {(data) in
				self.apply(data, job: job, callback: callback)
			})
		}
		else {
			// TODO: set an error message
			callback(QBERasterData())
		}
	}
	
	var previous: QBEStep? { didSet {
		assert(previous != self, "A step cannot be its own previous step")
		previous?.next = self
	} }
	
	var alternatives: [QBEStep]?
	weak var next: QBEStep?
	
	override private init() {
	}
	
	init(previous: QBEStep?) {
		self.previous = previous
	}
	
	required init(coder aDecoder: NSCoder) {
		previous = aDecoder.decodeObjectForKey("previousStep") as? QBEStep
		next = aDecoder.decodeObjectForKey("nextStep") as? QBEStep
		alternatives = aDecoder.decodeObjectForKey("alternatives") as? [QBEStep]
	}
	
	func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(previous, forKey: "previousStep")
		coder.encodeObject(next, forKey: "nextStep")
		coder.encodeObject(alternatives, forKey: "alternatives")
	}
	
	/** Description returns a locale-dependent explanation of the step. It can (should) depend on the specific
	configuration of the step. **/
	func explain(locale: QBELocale, short: Bool = false) -> String {
		return NSLocalizedString("Unknown step", comment: "")
	}
	
	func apply(data: QBEData, job: QBEJob, callback: (QBEData) -> ()) {
		fatalError("Child class of QBEStep should implement apply()")
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference 
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. **/
	func willSaveToDocument(atURL: NSURL) {
	}
	
	/** This method is called right after a document has been loaded from disk. **/
	func didLoadFromDocument(atURL: NSURL) {
	}

	/** Returns whether this step can be merged with the specified previous step. **/
	func mergeWith(prior: QBEStep) -> QBEStepMerge {
		return QBEStepMerge.Impossible
	}
}

enum QBEStepMerge {
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
(which will allow regular unlimited access). **/
enum QBEFileReference {
	case Bookmark(NSData)
	case ResolvedBookmark(NSData, NSURL)
	case URL(NSURL)
	
	static func create(url: NSURL?, _ bookmark: NSData?) -> QBEFileReference? {
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
	
	func bookmark(relativeToDocument: NSURL) -> QBEFileReference? {
		switch self {
		case .URL(let u):
			var error: NSError? = nil
			if let bookmark = u.bookmarkDataWithOptions(NSURLBookmarkCreationOptions.WithSecurityScope, includingResourceValuesForKeys: nil, relativeToURL: nil, error: &error) {
				if let resolved = NSURL(byResolvingBookmarkData: bookmark, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil, error: &error) {
					return QBEFileReference.ResolvedBookmark(bookmark, resolved)
				}
				else {
					QBELog("Failed to resolve just-created bookmark: \(error)")
				}
			}
			else {
				QBELog("Could not create bookmark for url \(u): \(error)")
			}
			return self
			
		case .Bookmark(let b):
			return self
			
		case .ResolvedBookmark(let b, let u):
			return self
		}
	}
	
	func resolve(relativeToDocument: NSURL) -> QBEFileReference? {
		switch self {
		case .URL(let u):
			return self
			
		case .ResolvedBookmark(let b, let oldURL):
			var error: NSError? = nil
			if let u = NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil, error: &error) {
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			QBELog("Could not re-resolve bookmark \(b) to \(oldURL) relative to \(relativeToDocument): \(error)")
			return self
			
		case .Bookmark(let b):
			var error: NSError? = nil
			if let u = NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil, error: &error) {
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			QBELog("Could not resolve secure bookmark \(b): \(error)")
			return self
		}
	}
	
	var bookmark: NSData? { get {
		switch self {
			case .ResolvedBookmark(let d, _): return d
			case .Bookmark(let d): return d
			default: return nil
		}
		} }
	
	var url: NSURL? { get {
		switch self {
			case .URL(let u): return u
			case .ResolvedBookmark(_, let u): return u
			default: return nil
		}
		} }
}

func == (lhs: QBEFileReference, rhs: QBEFileReference) -> Bool {
	if let lu = lhs.url, ru = rhs.url {
		return lu == ru
	}
	else if let lb = lhs.bookmark, rb = rhs.bookmark {
		return lb == rb
	}
	return false
}

/** The transpose step implements a row-column switch. It has no configuration and relies on the QBEData transpose()
implementation to do the actual work. **/
class QBETransposeStep: QBEStep {
	override func apply(data: QBEData, job: QBEJob? = nil, callback: (QBEData) -> ()) {
		callback(data.transpose())
	}
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		return NSLocalizedString("Switch rows/columns", comment: "")
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let t = prior as? QBETransposeStep {
			return QBEStepMerge.Cancels
		}
		return QBEStepMerge.Impossible
	}
}