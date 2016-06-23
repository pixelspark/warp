import Foundation
import WarpCore

/** A sentence is a string of tokens that describe the action performed by a step in natural language, and allow for the
configuration of that step. For example, a step that limits the number of rows in a result set may have a sentence like
"limit to [x] rows". In this case, the sentence consists of three tokens: a constant text ('limit to'), a configurable
number token ('x') and another constant text ('rows'). */
public class QBESentence {
	public private(set) var tokens: [QBESentenceToken]

	public init(_ tokens: [QBESentenceToken]) {
		self.tokens = tokens
	}

	public static let formatStringTokenPlaceholder = "[#]"

	/** Create a sentence based on a formatting string and a set of tokens. This allows for flexible localization of
	sentences. The format string may contain instances of '[#]' as placeholders for tokens. This is the preferred way
	of constructing sentences, since it allows for proper localization (word order may be different between languages).*/
	public init(format: String, _ tokens: QBESentenceToken...) {
		self.tokens = []

		var startIndex = format.startIndex
		for token in tokens {
			if let nextToken = format.range(of: QBESentence.formatStringTokenPlaceholder, options: [], range: startIndex..<format.endIndex) {
				let constantString = format.substring(with: startIndex..<nextToken.lowerBound)
				self.tokens.append(QBESentenceText(constantString))
				self.tokens.append(token)
				startIndex = nextToken.upperBound
			}
			else {
				fatalError("There are more tokens than there can be placed in the format string '\(format)'")
			}
		}

		if format.distance(from: startIndex, to: format.endIndex) > 0 {
			self.tokens.append(QBESentenceText(format.substring(with: startIndex..<format.endIndex)))
		}
	}

	public func append(_ sentence: QBESentence) {
		self.tokens.append(contentsOf: sentence.tokens)
	}

	public func append(_ token: QBESentenceToken) {
		self.tokens.append(token)
	}

	public var stringValue: String { get {
		return self.tokens.map({ return $0.label }).joined(separator: "")
		} }
}

public protocol QBESentenceToken: NSObjectProtocol {
	var label: String { get }
	var isToken: Bool { get }
}

/** A sentence item that presents a list of (string) options. */
public class QBESentenceList: NSObject, QBESentenceToken {
	public typealias Callback = (String) -> ()
	public typealias ProviderCallback = (Fallible<[String]>) -> ()
	public typealias Provider = (ProviderCallback) -> ()
	public private(set) var optionsProvider: Provider
	private(set) var value: String
	public let callback: Callback

	public var label: String { get {
		return value
		} }

	public init(value: String, provider: Provider, callback: Callback) {
		self.optionsProvider = provider
		self.value = value
		self.callback = callback
	}

	public var isToken: Bool { get { return true } }

	public func select(_ key: String) {
		if key != value {
			callback(key)
		}
	}
}

/** A sentence item that shows a list of string options, which have associated string keys. */
public class QBESentenceOptions: NSObject, QBESentenceToken {
	public typealias Callback = (String) -> ()
	public private(set) var options: [String: String]
	public private(set) var value: String
	public let callback: Callback

	public var label: String { get {
		return options[value] ?? ""
		} }

	public init(options: [String: String], value: String, callback: Callback) {
		self.options = options
		self.value = value
		self.callback = callback
	}

	public var isToken: Bool { get { return true } }

	public func select(_ key: String) {
		assert(options[key] != nil, "Selecting an invalid option")
		if key != value {
			callback(key)
		}
	}
}

/** A sentence item that shows a list of string options, which have associated string keys. Either option can be selected
or deselected.*/
public class QBESentenceSet: NSObject, QBESentenceToken {
	public typealias Provider = (callback: (Fallible<Set<String>>) -> ()) -> ()
	public typealias Callback = (Set<String>) -> ()
	public private(set) var provider: Provider
	public private(set) var value: Set<String>
	public let callback: Callback

	public var label: String {
		if self.value.count > 4 {
			let first = self.value.sorted().prefix(4)
			return String(format: "%@ and %d more".localized, first.joined(separator: ", "), self.value.count - first.count)
		}

		return self.value.joined(separator: ", ")
	}

	public init(value: Set<String>, provider: Provider, callback: Callback) {
		self.provider = provider
		self.value = value
		self.callback = callback
	}

	public var isToken: Bool { get { return true } }

	public func select(_ set: Set<String>) {
		callback(set)
	}
}

/** Sentence item that shows static, read-only text. */
public class QBESentenceText: NSObject, QBESentenceToken {
	public let label: String

	public init(_ label: String) {
		self.label = label
	}

	public var isToken: Bool { get { return false } }
}

/** Sentence item that shows editable text. */
public class QBESentenceTextInput: NSObject, QBESentenceToken {
	public typealias Callback = (String) -> (Bool)
	public let label: String
	public let callback: Callback

	public init(value: String, callback: Callback) {
		self.label = value
		self.callback = callback
	}

	public func change(_ newValue: String) -> Bool {
		if label != newValue {
			return callback(newValue)
		}
		return true
	}

	public var isToken: Bool { get { return true } }
}

public struct QBESentenceFormulaContext {
	var row: Row
	var columns: [Column]
}

/** Sentence item that shows a friendly representation of a formula, and shows a formula editor on editing. */
public class QBESentenceFormula: NSObject, QBESentenceToken {
	public typealias ContextCallback = (Fallible<QBESentenceFormulaContext>) -> ()
	public typealias Callback = (Expression) -> ()
	public let expression: Expression
	public let locale: Language
	public let callback: Callback // Called when a new formula is set
	public let contextCallback: ((Job, ContextCallback) -> ())? // Called to obtain context information (columns, example row, etc.)

	public init(expression: Expression, locale: Language, callback: Callback, contextCallback: ((Job, ContextCallback) -> ())? = nil) {
		self.expression = expression
		self.locale = locale
		self.callback = callback
		self.contextCallback = contextCallback
	}

	public func change(_ newValue: Expression) {
		callback(newValue)
	}

	public var label: String {
		get {
			return expression.explain(self.locale, topLevel: true)
		}
	}

	public var isToken: Bool { get { return true } }
}

public enum QBESentenceFileMode {
	case writing()
	case reading(canCreate: Bool)
}

/** Sentence item that refers to an (existing or yet to be created) file or directory. */
public class QBESentenceFile: NSObject, QBESentenceToken {
	public typealias Callback = (QBEFileReference) -> ()
	public let file: QBEFileReference?
	public let allowedFileTypes: [String]
	public let callback: Callback
	public let isDirectory: Bool
	public let mode: QBESentenceFileMode

	public init(directory: QBEFileReference?, callback: Callback) {
		self.allowedFileTypes = []
		self.file = directory
		self.callback = callback
		self.isDirectory = true
		self.mode = .reading(canCreate: true)
	}

	public init(saveFile file: QBEFileReference?, allowedFileTypes: [String], callback: Callback) {
		self.file = file
		self.callback = callback
		self.allowedFileTypes = allowedFileTypes
		self.isDirectory = false
		self.mode = .writing()
	}

	public init(file: QBEFileReference?, allowedFileTypes: [String], canCreate: Bool = false, callback: Callback) {
		self.file = file
		self.callback = callback
		self.allowedFileTypes = allowedFileTypes
		self.isDirectory = false
		self.mode = .reading(canCreate: canCreate)
	}

	public func change(_ newValue: QBEFileReference) {
		callback(newValue)
	}

	public var label: String {
		get {
			return file?.url?.lastPathComponent ?? NSLocalizedString("(no file)", comment: "")
		}
	}

	public var isToken: Bool { get { return true } }
}

extension QBEStep {
	func contextCallbackForFormulaSentence(_ job: Job, callback: QBESentenceFormula.ContextCallback) {
		if let sourceStep = self.previous {
			sourceStep.exampleDataset(job, maxInputRows: 100, maxOutputRows: 1) { result in
				switch result {
				case .success(let data):
					data.limit(1).raster(job) { result in
						switch result {
						case .success(let raster):
							if raster.rowCount == 1 {
								let ctx = QBESentenceFormulaContext(row: raster[0], columns: raster.columns)
								return callback(.success(ctx))
							}

						case .failure(let e):
							return callback(.failure(e))
						}
					}

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		}
		else {
			return callback(.failure("No data source for chart".localized))
		}
	}
}
