import Foundation
import WarpCore

/** QBEFileReference is the class to be used by steps that need to reference auxiliary files. It employs Apple's App
Sandbox API to create 'secure bookmarks' to these files, so that they can be referenced when opening the Warp document
again later. Steps should call bookmark() on all their references from the willSavetoDocument method, and call resolve()
on all file references inside didLoadFromDocument. In addition they should store both the 'url' as well as the 'bookmark'
property when serializing a file reference (in encodeWithCoder).

On non-sandbox builds, QBEFileReference will not be able to resolve bookmarks to URLs, and it will return the original URL
(which will allow regular unlimited access). */
public enum QBEFileReference: Equatable {
	case bookmark(Data)
	case resolvedBookmark(Data, URL)
	case absolute(URL?)

	public static func create(_ url: URL?, _ bookmark: Data?) -> QBEFileReference? {
		if bookmark == nil {
			if url != nil {
				return QBEFileReference.absolute(url!)
			}
			else {
				return nil
			}
		}
		else {
			if url == nil {
				return QBEFileReference.bookmark(bookmark!)
			}
			else {
				return QBEFileReference.resolvedBookmark(bookmark!, url!)
			}
		}
	}

	public func persist(_ relativeToDocument: URL?) -> QBEFileReference? {
		switch self {
		case .absolute(let u):
			do {
				if let url = u {
					let bookmark = try url.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: relativeToDocument)
					do {
						var stale: Bool = false
						if let resolved = try URL(resolvingBookmarkData: bookmark, options: URL.BookmarkResolutionOptions.withSecurityScope, relativeTo: relativeToDocument, bookmarkDataIsStale: &stale) {

							if stale {
								trace("Just-created URL bookmark is already stale! \(resolved)")
							}
							return QBEFileReference.resolvedBookmark(bookmark, resolved)
						}
					}
					catch let error as NSError {
						trace("Failed to resolve just-created bookmark: \(error)")
					}
				}
				return self
			}
			catch let error as NSError {
				trace("Could not create bookmark for url \(u): \(error)")
			}
			return self

		case .bookmark(_):
			return self

		case .resolvedBookmark(_,_):
			return self
		}
	}

	public func resolve(_ relativeToDocument: URL?) -> QBEFileReference? {
		switch self {
		case .absolute(_):
			return self

		case .resolvedBookmark(let b, let oldURL):
			do {
				var stale = false
				let u = try URL(resolvingBookmarkData: b, options: URL.BookmarkResolutionOptions.withSecurityScope, relativeTo: relativeToDocument, bookmarkDataIsStale: &stale)
				if stale {
					trace("Resolved bookmark is stale: \(u)")
					return QBEFileReference.absolute(u)
				}

				if let u = u {
					return QBEFileReference.resolvedBookmark(b, u)
				}

				// Resolving failed, but maybe the old URL still works
				return QBEFileReference.resolvedBookmark(b, oldURL)
			}
			catch let error as NSError {
				trace("Could not re-resolve bookmark \(b) to \(oldURL) relative to \(relativeToDocument): \(error)")
			}

			return self

		case .bookmark(let b):
			do {
				var stale = false
				let u = try URL(resolvingBookmarkData: b, options: URL.BookmarkResolutionOptions.withSecurityScope, relativeTo: relativeToDocument, bookmarkDataIsStale: &stale)
				if stale {
					trace("Just-resolved bookmark is stale: \(u)")
					return QBEFileReference.absolute(u)
				}

				if let u = u {
					return QBEFileReference.resolvedBookmark(b, u)
				}
				return QBEFileReference.bookmark(b)
			}
			catch let error as NSError {
				trace("Could not resolve secure bookmark \(b): \(error)")
			}
			return self
		}
	}

	public var bookmark: Data? {
		switch self {
		case .resolvedBookmark(let d, _): return d
		case .bookmark(let d): return d
		default: return nil
		}
	}

	public var url: URL? {
		switch self {
		case .absolute(let u): return u
		case .resolvedBookmark(_, let u): return u
		default: return nil
		}
	}
}

public func == (lhs: QBEFileReference, rhs: QBEFileReference) -> Bool {
	if let lu = lhs.url, let ru = rhs.url {
		return lu == ru
	}
	else if let lb = lhs.bookmark, let rb = rhs.bookmark {
		return lb == rb
	}
	return false
}

/** QBEFileCoordinator manages file presenters, which are required to obtain access to certain files (e.g. secondary files
such as SQLite's journal files). Call `present` on the shared instance, and retain the returned QBEFilePresenter object 
as long as you need to access the file. */
internal class QBEFileCoordinator {
	static let sharedInstance = QBEFileCoordinator()

	private let mutex = Mutex()
	private var presenters: [URL: Weak<QBEFilePresenter>] = [:]

	func present(_ file: URL, secondaryExtension: String? = nil) -> QBEFilePresenter {
		let presentedFile: URL
		if let se = secondaryExtension {
			presentedFile = (file.deletingPathExtension().appendingPathExtension(se)) 
		}
		else {
			presentedFile = file
		}

		return self.mutex.locked { () -> QBEFilePresenter in
			if let existing = self.presenters[presentedFile]?.value {
				return existing
			}
			else {
				trace("Present new: \(presentedFile)")
				let pres = QBEFilePresenter(primary: file, secondary: presentedFile)
				self.presenters[presentedFile] = Weak(pres)
				return pres
			}
		}
	}
}

private class QBEFilePresenterDelegate: NSObject, NSFilePresenter {
	@objc let primaryPresentedItemURL: URL?
	@objc let presentedItemURL: URL?

	init(primary: URL, secondary: URL) {
		self.primaryPresentedItemURL = primary
		self.presentedItemURL = secondary
	}

	@objc var presentedItemOperationQueue: OperationQueue {
		return OperationQueue.main
	}
}

/** This needs to be an NSObject subclass, as otherwise it appears it is not destroyed correctly. The QBEFileCoordinator
holds a weak reference to this presenter, but deinit is only called if this file presenter is an NSObject subclass (Swift
bug?). */
public class QBEFilePresenter: NSObject {
	private let delegate: QBEFilePresenterDelegate

	fileprivate init(primary: URL, secondary: URL) {
		self.delegate = QBEFilePresenterDelegate(primary: primary, secondary: secondary)
		NSFileCoordinator.addFilePresenter(delegate)

		/* FIXME this is a bad way to force the file coordinator to sync and actually finish creating the file presenters.
		See: http://thebesthacker.com/question/osx-related-file-creation.html */
		let _ = NSFileCoordinator.filePresenters
	}

	deinit {
		NSFileCoordinator.removeFilePresenter(self.delegate)
	}
}

public class QBEFileRecents {
	private let maxRememberedFiles = 5
	private let preferenceKey: String

	init(key: String) {
		self.preferenceKey = "recents.\(key)"
	}

	public func loadRememberedFiles() -> [QBEFileReference] {
		let files: [String] = (UserDefaults.standard.array(forKey: preferenceKey) as? [String]) ?? []
		return files.flatMap { bookmarkString -> [QBEFileReference] in
			if let bookmarkData = Data(base64Encoded: bookmarkString, options: []) {
				let fileRef = QBEFileReference.bookmark(bookmarkData)
				if let resolved = fileRef.resolve(nil) {
					return [resolved]
				}
			}
			return []
		}
	}

	public func remember(_ file: QBEFileReference) {
		if let bookmarkData = file.persist(nil)?.bookmark {
			var files: [String] = (UserDefaults.standard.array(forKey: preferenceKey) as? [String]) ?? []
			files.insert(bookmarkData.base64EncodedString(options: []), at: 0)
			UserDefaults.standard.setValue(Array(files.prefix(self.maxRememberedFiles)), forKey: preferenceKey)
		}
	}
}
