/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit

protocol QBEDocumentThumbnailCacheDelegate: class {
	func thumbnailCache(_ thumbnailCache: QBEDocumentThumbnailCache, didLoadThumbnailsForURLs: Set<URL>)
}

class QBEDocumentThumbnailCache {
	// MARK: - Properties

	fileprivate let cache: NSCache = { () -> NSCache<AnyObject, AnyObject> in
		let cache = NSCache<AnyObject, AnyObject>()

		cache.name = "nl.pixelspark.Warp.QBEDocumentThumbnailCache"
		cache.countLimit = 64

		return cache
	}()

	fileprivate let workerQueue: OperationQueue = {
		let workerQueue = OperationQueue()
		workerQueue.name = "nl.pixelspark.Warp.QBEDocumentThumbnailCache.workerQueue"
		workerQueue.maxConcurrentOperationCount = QBEDocumentThumbnailCache.concurrentThumbnailOperations

		return workerQueue
	}()

	let thumbnailSize: CGSize
	fileprivate var URLsNeedingReload = Set<URL>()
	fileprivate var pendingThumbnails = [Int: Set<URL>]()
	fileprivate var cleanThumbnailDocumentIDs = Set<Int>()
	fileprivate var unscheduledDocumentIDs = [Int]()
	fileprivate var runningDocumentIDCount = 0
	fileprivate var scheduleSource: DispatchSourceUserDataOr
	fileprivate var flushSource: DispatchSourceUserDataOr
	weak var delegate: QBEDocumentThumbnailCacheDelegate?

	static let concurrentThumbnailOperations = 4

	init (thumbnailSize:CGSize) {
		self.thumbnailSize = thumbnailSize

		scheduleSource = DispatchSource.makeUserDataOrSource(queue: DispatchQueue.main)
		flushSource = DispatchSource.makeUserDataOrSource(queue: DispatchQueue.main)

		// Set up our scheduler which will manage an array of pending thumbnails
		scheduleSource.setEventHandler { [weak self] in
			guard let strongSelf = self else { return }

			strongSelf.scheduleThumbnailLoading()
		}

		scheduleSource.resume()

		// Set up our source which will push a batch of thumbnail updates at once.
		flushSource.setEventHandler { [weak self] in
			guard let strongSelf = self else { return }

			strongSelf.delegate?.thumbnailCache(strongSelf, didLoadThumbnailsForURLs: strongSelf.URLsNeedingReload)
			strongSelf.URLsNeedingReload.removeAll()
		}

		flushSource.resume()
	}

	func markThumbnailCacheDirty() {
		// We've been asked to reload the UI and need to reload all items in the cache.
		cleanThumbnailDocumentIDs.removeAll()
	}

	func markThumbnailDirtyForURL(_ URL: Foundation.URL) {
		/*
		Mark the item dirty so that we know the next time we are asked for the
		thumbnail that we need to reload it.
		*/
		if let documentIdentifier = documentIdentifierForURL(URL) {
			cleanThumbnailDocumentIDs.remove(documentIdentifier)
		}
	}

	func removeThumbnailForURL(_ URL: Foundation.URL) {
		/*
		Remove the item entirely from the cache because the item existing in the cache no
		longer makes sense for that URL.
		*/
		if let documentIdentifier = documentIdentifierForURL(URL) {
			cache.removeObject(forKey: documentIdentifier as AnyObject)

			cleanThumbnailDocumentIDs.remove(documentIdentifier)
		}
	}

	func cancelThumbnailLoadForURL(_ URL: Foundation.URL) {
		if let documentIdentifier = documentIdentifierForURL(URL) {
			if let index = unscheduledDocumentIDs.index(of: documentIdentifier) {
				unscheduledDocumentIDs.remove(at: index)

				pendingThumbnails[documentIdentifier] = nil
			}
		}
	}


	// MARK: - Thumbnail Loading

	fileprivate func documentIdentifierForURL(_ URL: Foundation.URL) -> Int? {
		// Look up the document identifier on the URL which uniquely identifies a document.
		do {
			var documentIdentifier: AnyObject?
			try (URL as NSURL).getPromisedItemResourceValue(&documentIdentifier, forKey: URLResourceKey.documentIdentifierKey)

			return documentIdentifier as? Int
		}
		catch {
			return nil
		}
	}

	fileprivate func scheduleThumbnailLoading() {
		// While we have work left to schedule, schedule a thumbnail fetch in the background
		while self.runningDocumentIDCount < QBEDocumentThumbnailCache.concurrentThumbnailOperations {
			guard let nextDocumentID = self.unscheduledDocumentIDs.first else { break }

			let index = self.unscheduledDocumentIDs.index(of: nextDocumentID)!
			self.unscheduledDocumentIDs.remove(at: index)
			self.runningDocumentIDCount += 1

			let thumbnailURL = self.pendingThumbnails[nextDocumentID]!.first!
			let alreadyCached = self.cache.object(forKey: nextDocumentID as AnyObject) != nil ? true : false
			self.loadThumbnailInBackgroundForURL(thumbnailURL, documentIdentifier: nextDocumentID, alreadyCached: alreadyCached)
		}
	}

	fileprivate func loadThumbnailInBackgroundForURL(_ URL: Foundation.URL, documentIdentifier: Int, alreadyCached: Bool) {
		self.workerQueue.addOperation {
			if let thumbnail = self.loadThumbnailFromDiskForURL(URL) {
				// Scale the image to correct size.
				UIGraphicsBeginImageContextWithOptions(self.thumbnailSize, false, UIScreen.main.scale)
				let thumbnailRect = CGRect(x: 0, y: 0, width: self.thumbnailSize.width, height: self.thumbnailSize.height)
				thumbnail.draw(in: thumbnailRect)
				let scaledThumbnail = UIGraphicsGetImageFromCurrentImageContext()
				UIGraphicsEndImageContext()

				/*
				Thumbnail loading succeeded. Save the thumbnail and call the
				reload blocks to reload the UI.
				*/
				self.cache.setObject(scaledThumbnail!, forKey: documentIdentifier as AnyObject)

				OperationQueue.main.addOperation {
					self.cleanThumbnailDocumentIDs.insert(documentIdentifier)

					// Fetch all URLs for this `documentIdentifier`, not just the provided `URL` parameter.
					let URLsForDocumentIdentifier = self.pendingThumbnails[documentIdentifier]!

					// Join the URLs for this identifier to any other URLs due for updating.
					self.URLsNeedingReload.formUnion(URLsForDocumentIdentifier)

					self.pendingThumbnails[documentIdentifier] = nil

					// Trigger the event handler for the `flushSource` updating a batch of thumbnails.
					self.flushSource.or(data: 1)

					self.runningDocumentIDCount -= 1

					// Trigger the event handler for the `scheduleSource` scheduling thumbnail loading.
					self.scheduleSource.or(data: 1)
				}
			}
			else {
				// Thumbnail loading failed. Just use the most recent cached thumbail.
				if !alreadyCached {
					let image = UIImage(named: "MissingThumbnail.png")!
					self.cache.setObject(image, forKey: documentIdentifier as AnyObject)
				}

				OperationQueue.main.addOperation {
					self.cleanThumbnailDocumentIDs.insert(documentIdentifier)
					self.pendingThumbnails[documentIdentifier] = nil
					self.runningDocumentIDCount -= 1

					// Trigger the event handler for the `scheduleSource` scheduling thumbnail loading.
					self.scheduleSource.or(data: 1)
				}
			}
		}
	}

	func loadThumbnailForURL(_ URL: Foundation.URL) -> UIImage {
		/*
		We load the existing thumbnail (or a placeholder image if none has been
		loaded yet) and check if it is clean or not. If it isn't clean, we
		load the thumbnail on a background queue to avoid blocking the main
		thread which could hamper scroll performance. Regardless of whether or
		not the thumbnail is clean, return the most up-to-date version of the
		thumbnail so we are sure to display something relatively up-to-date in
		the UI.
		*/

		/*
		We cache everything in our thumbnail cache by document identifier which
		is tracked properly accross renames.
		*/
		guard let documentIdentifier = documentIdentifierForURL(URL) else {
			print("Failed to load docID and will display placeholder image for \(URL)")

			return UIImage(named: "MissingThumbnail.png")!
		}

		let existingImage = cache.object(forKey: documentIdentifier as AnyObject) as? UIImage

		if let existingImage = existingImage, cleanThumbnailDocumentIDs.contains(documentIdentifier) {
			// Everything fully up-to-date - return the cached image.
			return existingImage
		}

		// Use a placeholder image if one hasn't been loaded yet.
		let loadedThumbnail = existingImage ?? UIImage(named: "MissingThumbnail")!

		// If we are already loading that thumbnail, add our url to the reload list.
		if let URLs = pendingThumbnails[documentIdentifier] {
			pendingThumbnails[documentIdentifier] = URLs.union([URL])
			return loadedThumbnail
		}

		// Schedule the thumbnail to be loaded on a background queue.
		pendingThumbnails[documentIdentifier] = [URL]

		unscheduledDocumentIDs += [documentIdentifier]

		// Trigger the event handler for the `scheduleSource` scheduling thumbnail loading.
		scheduleSource.or(data: 1)

		// Return the most up-to-date image we have currently.
		return loadedThumbnail
	}

	fileprivate func loadThumbnailFromDiskForURL(_ URL: Foundation.URL) -> UIImage? {
		do {
			/*
			Load the thumbnail from disk.  Use getPromisedItemResourceValue because
			the document might not have been downloaded yet.
			*/
			var thumbnailDictionary: AnyObject?
			try (URL as NSURL).getPromisedItemResourceValue(&thumbnailDictionary, forKey: URLResourceKey.thumbnailDictionaryKey)

			/*
			We don't want to hang onto this in the URL cache because the URL
			is long running and we maintain a separate cache for the thumbnails.
			*/
			(URL as NSURL).removeCachedResourceValue(forKey: URLResourceKey.thumbnailDictionaryKey)

			/*guard let dictionary = thumbnailDictionary as? [String: UIImage],
			let image = dictionary[URLThumbnailDictionaryItem.NSThumbnail1024x1024SizeKey] else {
			throw ShapeEditError.thumbnailLoadFailed
			}*/
			return nil

			//return image
		}
		catch {
			return nil
		}
	}
}
