import Foundation

/** Represents a data manipulation step. Steps usually connect to (at least) one previous step and (sometimes) a next step.
The step transforms a data manipulation on the data produced by the previous step; the results are in turn used by the 
next. Steps work on two datasets: the 'example' data set (which is used to let the user design the data manipulation) and
the 'full' data (which is the full dataset on which the final data operations are run). 

Subclasses of QBEStep implement the data manipulation in the apply function, and should implement the description method
as well as coding methods. The explanation variable contains a user-defined comment to an instance of the step. */
class QBEStep: NSObject, NSCoding {
	static let dragType = "nl.pixelspark.Warp.Step"
	
	/** Creates a data object representing the result of an 'example' calculation of the result of this QBEStep. The
	maxInputRows parameter defines the maximum number of input rows a source step should generate. The maxOutputRows
	parameter defines the maximum number of rows a step should strive to produce. */
	func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
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
	
	func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
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
	configuration of the step. */
	final func explain(locale: QBELocale) -> String {
		return sentence(locale).stringValue
	}

	func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence([])
	}
	
	func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		fatalError("Child class of QBEStep should implement apply()")
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference 
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	func willSaveToDocument(atURL: NSURL) {
	}
	
	/** This method is called right after a document has been loaded from disk. */
	func didLoadFromDocument(atURL: NSURL) {
	}

	/** Returns whether this step can be merged with the specified previous step. */
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
(which will allow regular unlimited access). */
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
	
	func resolve(relativeToDocument: NSURL) -> QBEFileReference? {
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
implementation to do the actual work. */
class QBETransposeStep: QBEStep {
	override func apply(data: QBEData, job: QBEJob? = nil, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(data.transpose()))
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence([QBESentenceText(NSLocalizedString("Switch rows/columns", comment: ""))])
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if prior is QBETransposeStep {
			return QBEStepMerge.Cancels
		}
		return QBEStepMerge.Impossible
	}
}

/** A sentence is a string of tokens that describe the action performed by a step in natural language, and allow for the
configuration of that step. For example, a step that limits the number of rows in a result set may have a sentence like 
"limit to [x] rows". In this case, the sentence consists of three tokens: a constant text ('limit to'), a configurable
number token ('x') and another constant text ('rows'). */
class QBESentence {
	private(set) var tokens: [QBESentenceToken]

	init(_ tokens: [QBESentenceToken]) {
		self.tokens = tokens
	}

	static let formatStringTokenPlaceholder = "[#]"

	/** Create a sentence based on a formatting string and a set of tokens. This allows for flexible localization of 
	sentences. The format string may contain instances of '[#]' as placeholders for tokens. This is the preferred way
	of constructing sentences, since it allows for proper localization (word order may be different between languages).*/
	init(format: String, _ tokens: QBESentenceToken...) {
		self.tokens = []

		var startIndex = format.startIndex
		for token in tokens {
			if let nextToken = format.rangeOfString(QBESentence.formatStringTokenPlaceholder, options: [], range: Range(start: startIndex, end: format.endIndex)) {
				let constantString = format.substringWithRange(Range(start: startIndex, end: nextToken.startIndex))
				self.tokens.append(QBESentenceText(constantString))
				self.tokens.append(token)
				startIndex = nextToken.endIndex
			}
			else {
				fatalError("There are more tokens than there can be placed in the format string '\(format)'")
			}
		}

		if distance(startIndex, format.endIndex)>0 {
			self.tokens.append(QBESentenceText(format.substringWithRange(Range(start: startIndex, end: format.endIndex))))
		}
	}

	var stringValue: String { get {
		return self.tokens.map({ return $0.label }).implode(" ")
	} }
}

protocol QBESentenceToken: NSObjectProtocol {
	var label: String { get }
	var isToken: Bool { get }
}

class QBESentenceList: NSObject, QBESentenceToken {
	typealias Callback = (String) -> ()
	typealias ProviderCallback = (QBEFallible<[String]>) -> ()
	typealias Provider = (ProviderCallback) -> ()
	private(set) var optionsProvider: Provider
	private(set) var value: String
	private let callback: Callback

	var label: String { get {
		return value
	} }

	init(value: String, provider: Provider, callback: Callback) {
		self.optionsProvider = provider
		self.value = value
		self.callback = callback
	}

	var isToken: Bool { get { return true } }

	func select(key: String) {
		if key != value {
			callback(key)
		}
	}
}

class QBESentenceOptions: NSObject, QBESentenceToken {
	typealias Callback = (String) -> ()
	private(set) var options: [String: String]
	private(set) var value: String
	private let callback: Callback

	var label: String { get {
		return options[value] ?? ""
	} }

	init(options: [String: String], value: String, callback: Callback) {
		self.options = options
		self.value = value
		self.callback = callback
	}

	var isToken: Bool { get { return true } }

	func select(key: String) {
		assert(options[key] != nil, "Selecting an invalid option")
		if key != value {
			callback(key)
		}
	}
}

class QBESentenceText: NSObject, QBESentenceToken {
	let label: String

	init(_ label: String) {
		self.label = label
	}

	var isToken: Bool { get { return false } }
}

class QBESentenceTextInput: NSObject, QBESentenceToken {
	typealias Callback = (String) -> (Bool)
	let label: String
	let callback: Callback

	init(value: String, callback: Callback) {
		self.label = value
		self.callback = callback
	}

	func change(newValue: String) -> Bool {
		if label != newValue {
			return callback(newValue)
		}
		return true
	}

	var isToken: Bool { get { return true } }
}

class QBESentenceFormula: NSObject, QBESentenceToken {
	typealias Callback = (QBEExpression) -> ()
	let expression: QBEExpression
	let locale: QBELocale
	let callback: Callback

	init(expression: QBEExpression, locale: QBELocale, callback: Callback) {
		self.expression = expression
		self.locale = locale
		self.callback = callback
	}

	func change(newValue: QBEExpression) {
		callback(newValue)
	}

	var label: String {
		get {
			return expression.explain(self.locale, topLevel: true)
		}
	}

	var isToken: Bool { get { return true } }
}

class QBESentenceFile: NSObject, QBESentenceToken {
	typealias Callback = (QBEFileReference) -> ()
	let file: QBEFileReference?
	let allowedFileTypes: [String]
	let callback: Callback

	init(file: QBEFileReference?, allowedFileTypes: [String], callback: Callback) {
		self.file = file
		self.callback = callback
		self.allowedFileTypes = allowedFileTypes
	}

	func change(newValue: QBEFileReference) {
		callback(newValue)
	}

	var label: String {
		get {
			return file?.url?.lastPathComponent ?? NSLocalizedString("(no file)", comment: "")
		}
	}

	var isToken: Bool { get { return true } }
}