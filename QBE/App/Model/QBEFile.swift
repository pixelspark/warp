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

	private let mutex = QBEMutex()
	private var presenters: [NSURL: QBEWeak<QBEFilePresenter>] = [:]

	func present(file: NSURL, secondaryExtension: String? = nil) -> QBEFilePresenter {
		let presentedFile: NSURL
		if let se = secondaryExtension {
			presentedFile = (file.URLByDeletingPathExtension?.URLByAppendingPathExtension(se))!
		}
		else {
			presentedFile = file
		}

		return self.mutex.locked { () -> QBEFilePresenter in
			if let existing = self.presenters[presentedFile]?.value {
				QBELog("Present existing: \(presentedFile)")
				return existing
			}
			else {
				QBELog("Present new: \(presentedFile)")
				let pres = QBEFilePresenter(primary: file, secondary: presentedFile)
				self.presenters[presentedFile] = QBEWeak(pres)
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
	}

	deinit {
		QBELog("Removing file presenter for \(self.delegate.presentedItemURL!)")
		NSFileCoordinator.removeFilePresenter(self.delegate)
	}
}
