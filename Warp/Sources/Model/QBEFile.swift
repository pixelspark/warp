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

	public func bookmark(relativeToDocument: NSURL?) -> QBEFileReference? {
		switch self {
		case .URL(let u):
			do {
				let bookmark = try u.bookmarkDataWithOptions(NSURLBookmarkCreationOptions.WithSecurityScope, includingResourceValuesForKeys: nil, relativeToURL: relativeToDocument)
				do {
					var stale: ObjCBool = false
					let resolved = try NSURL(byResolvingBookmarkData: bookmark, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: relativeToDocument, bookmarkDataIsStale: &stale)
					if stale {
						trace("Just-created URL bookmark is already stale! \(resolved)")
					}
					return QBEFileReference.ResolvedBookmark(bookmark, resolved)
				}
				catch let error as NSError {
					trace("Failed to resolve just-created bookmark: \(error)")
				}
			}
			catch let error as NSError {
				trace("Could not create bookmark for url \(u): \(error)")
			}
			return self

		case .Bookmark(_):
			return self

		case .ResolvedBookmark(_,_):
			return self
		}
	}

	public func resolve(relativeToDocument: NSURL?) -> QBEFileReference? {
		switch self {
		case .URL(_):
			return self

		case .ResolvedBookmark(let b, let oldURL):
			do {
				var stale: ObjCBool = false
				let u = try NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: relativeToDocument, bookmarkDataIsStale: &stale)
				if stale {
					trace("Resolved bookmark is stale: \(u)")
					return QBEFileReference.URL(u)
				}
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			catch let error as NSError {
				trace("Could not re-resolve bookmark \(b) to \(oldURL) relative to \(relativeToDocument): \(error)")
			}

			return self

		case .Bookmark(let b):
			do {
				var stale: ObjCBool = false
				let u = try NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: relativeToDocument, bookmarkDataIsStale: &stale)
				if stale {
					trace("Just-resolved bookmark is stale: \(u)")
					return QBEFileReference.URL(u)
				}
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			catch let error as NSError {
				trace("Could not resolve secure bookmark \(b): \(error)")
			}
			return self
		}
	}

	public var bookmark: NSData? {
		switch self {
		case .ResolvedBookmark(let d, _): return d
		case .Bookmark(let d): return d
		default: return nil
		}
	}

	public var url: NSURL? {
		switch self {
		case .URL(let u): return u
		case .ResolvedBookmark(_, let u): return u
		default: return nil
		}
	}
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

/** QBEFileCoordinator manages file presenters, which are required to obtain access to certain files (e.g. secondary files
such as SQLite's journal files). Call `present` on the shared instance, and retain the returned QBEFilePresenter object 
as long as you need to access the file. */
internal class QBEFileCoordinator {
	static let sharedInstance = QBEFileCoordinator()

	private let mutex = Mutex()
	private var presenters: [NSURL: Weak<QBEFilePresenter>] = [:]

	func present(file: NSURL, secondaryExtension: String? = nil) -> QBEFilePresenter {
		let presentedFile: NSURL
		if let se = secondaryExtension {
			presentedFile = (file.URLByDeletingPathExtension?.URLByAppendingPathExtension(se)) ?? file
		}
		else {
			presentedFile = file
		}

		return self.mutex.locked { () -> QBEFilePresenter in
			if let existing = self.presenters[presentedFile]?.value {
				trace("Present existing: \(presentedFile)")
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
	@objc let primaryPresentedItemURL: NSURL?
	@objc let presentedItemURL: NSURL?

	init(primary: NSURL, secondary: NSURL) {
		self.primaryPresentedItemURL = primary
		self.presentedItemURL = secondary
	}

	@objc var presentedItemOperationQueue: NSOperationQueue {
		return NSOperationQueue.mainQueue()
	}
}

/** This needs to be an NSObject subclass, as otherwise it appears it is not destroyed correctly. The QBEFileCoordinator
holds a weak reference to this presenter, but deinit is only called if this file presenter is an NSObject subclass (Swift
bug?). */
public class QBEFilePresenter: NSObject {
	private let delegate: QBEFilePresenterDelegate

	private init(primary: NSURL, secondary: NSURL) {
		self.delegate = QBEFilePresenterDelegate(primary: primary, secondary: secondary)
		NSFileCoordinator.addFilePresenter(delegate)

		/* FIXME this is a bad way to force the file coordinator to sync and actually finish creating the file presenters.
		See: http://thebesthacker.com/question/osx-related-file-creation.html */
		NSFileCoordinator.filePresenters()
	}

	deinit {
		trace("Removing file presenter for \(self.delegate.presentedItemURL!)")
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
		let files: [String] = (NSUserDefaults.standardUserDefaults().arrayForKey(preferenceKey) as? [String]) ?? []
		return files.flatMap { bookmarkString -> [QBEFileReference] in
			if let bookmarkData = NSData(base64EncodedString: bookmarkString, options: []) {
				let fileRef = QBEFileReference.Bookmark(bookmarkData)
				if let resolved = fileRef.resolve(nil) {
					return [resolved]
				}
			}
			return []
		}
	}

	public func remember(file: QBEFileReference) {
		if let bookmarkData = file.bookmark(nil)?.bookmark {
			var files: [String] = (NSUserDefaults.standardUserDefaults().arrayForKey(preferenceKey) as? [String]) ?? []
			files.insert(bookmarkData.base64EncodedStringWithOptions([]), atIndex: 0)
			NSUserDefaults.standardUserDefaults().setValue(Array(files.prefix(self.maxRememberedFiles)), forKey: preferenceKey)
		}
	}
}
