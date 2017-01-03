/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit
import MobileCoreServices
import WarpCore

fileprivate enum QBEDocumentTemplate {
	case empty(name: String?)
	case file(URL)
	case document(QBEDocument)
}

fileprivate class QBEDocumentBrowserModel: NSObject {
	let item: NSMetadataItem

	init(item: NSMetadataItem) {
		self.item = item
	}

	var displayName: String {
		return self.item.value(forAttribute: NSMetadataItemDisplayNameKey) as! String
	}

	var downloaded: Bool {
		let status = (self.item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as! String)
		return status == NSMetadataUbiquitousItemDownloadingStatusDownloaded || status == NSMetadataUbiquitousItemDownloadingStatusCurrent
	}

	var downloading: Bool {
		return (self.item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as! Bool)
	}

	var subtitle: String? {
		/* External documents are not located in the app's ubiquitous container. They could either be in another app's 
		ubiquitous container or in the user's iCloud Drive folder, outside of the app's sandbox, but the user has granted 
		the app access to the document by picking the document in the document picker or opening the document in the app
		on OS X. Throughout the system, the name of the document is decorated with the source container's name. */
		if let isExternal = item.value(forAttribute: NSMetadataUbiquitousItemIsExternalDocumentKey) as? Bool,
			let containerName = item.value(forAttribute: NSMetadataUbiquitousItemContainerDisplayNameKey) as? String, isExternal {
			return "in \(containerName)"
		}
		return nil
	}

	var URL: URL {
		return self.item.value(forAttribute: NSMetadataItemURLKey) as! Foundation.URL
	}

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? QBEDocumentBrowserModel else {
			return false
		}

		return other.item.isEqual(self.item)
	}

	/// Hash method implemented to match `isEqual(_:)`'s constraints.
	override var hash: Int {
		return self.item.hash
	}
}

fileprivate enum QBEDocumentBrowserAnimation {
	case reload
	case delete(index: Int)
	case add(index: Int)
	case update(index: Int)
	case move(fromIndex: Int, toIndex: Int)
}

extension QBEDocumentBrowserAnimation: Equatable { }

fileprivate func ==(lhs: QBEDocumentBrowserAnimation, rhs: QBEDocumentBrowserAnimation) -> Bool {
	switch (lhs, rhs) {
	case (.reload, .reload):
		return true

	case let (.delete(left), .delete(right)) where left == right:
		return true

	case let (.add(left), .add(right)) where left == right:
		return true

	case let (.update(left), .update(right)) where left == right:
		return true

	case let (.move(leftFrom, leftTo), .move(rightFrom, rightTo)) where leftFrom == rightFrom && leftTo == rightTo:
		return true

	default:
		return false
	}
}

fileprivate protocol QBEDocumentManagerDelegate: NSObjectProtocol {
	func manager(_ manager: QBEDocumentManager, updateAvailableDocuments: [QBEDocumentBrowserModel], animations: [QBEDocumentBrowserAnimation])
}

fileprivate class QBEDocumentManager: NSObject {
	weak var delegate: QBEDocumentManagerDelegate?
	let query: NSMetadataQuery = NSMetadataQuery()
	fileprivate var previousQueryObjects: NSOrderedSet?

	fileprivate let workerQueue: OperationQueue = {
		let workerQueue = OperationQueue()
		workerQueue.name = "nl.pixelspark.Warp.QBEDocumentsViewControllerQueue"
		workerQueue.maxConcurrentOperationCount = 1
		return workerQueue
	}()

	init(fileExtension: String, inverse: Bool = false) {
		// Filter only our document type.
		let filePattern = String(format: "*.%@", fileExtension)
		query.predicate = NSPredicate(format: inverse ? "NOT(%K LIKE %@)" : "(%K LIKE %@)", NSMetadataItemFSNameKey, filePattern)

		query.searchScopes = [
			NSMetadataQueryUbiquitousDocumentsScope,
			NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope
		]

		query.operationQueue = workerQueue
	}

	func start() {
		if(!query.isStarted) {
			NotificationCenter.default.addObserver(self, selector: #selector(QBEDocumentManager.finishGathering(_:)), name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
			NotificationCenter.default.addObserver(self, selector: #selector(QBEDocumentManager.queryUpdated(_:)), name: NSNotification.Name.NSMetadataQueryDidUpdate, object: query)
			query.start()
		}
	}

	func stop() {
		if(query.isStarted) {
			query.stop()
			NotificationCenter.default.removeObserver(self)
		}
	}

	fileprivate func buildModelObjectSet(_ objects: [NSMetadataItem]) -> NSOrderedSet {
		// Create an ordered set of model objects.
		var array = objects.map { QBEDocumentBrowserModel(item: $0) }

		// Sort the array by filename.
		array.sort { $0.displayName < $1.displayName }

		let results = NSMutableOrderedSet(array: array)

		return results
	}

	@objc func queryUpdated(_ notification: Notification) {
		let changedMetadataItems = notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]
		let removedMetadataItems = notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem]
		let addedMetadataItems = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]

		let changedResults = buildModelObjectSet(changedMetadataItems ?? [])
		let removedResults = buildModelObjectSet(removedMetadataItems ?? [])
		let addedResults = buildModelObjectSet(addedMetadataItems ?? [])
		let newResults = buildQueryResultSet()

		updateWithResults(newResults, removedResults: removedResults, addedResults: addedResults, changedResults: changedResults)
	}

	fileprivate func buildQueryResultSet() -> NSOrderedSet {
		/*
		Create an ordered set of model objects from the query's current
		result set.
		*/
		query.disableUpdates()
		let metadataQueryResults = query.results as! [NSMetadataItem]
		let results = buildModelObjectSet(metadataQueryResults)
		query.enableUpdates()
		return results
	}

	@objc func finishGathering(_ notification: Notification) {
		query.disableUpdates()
		let metadataQueryResults = query.results as! [NSMetadataItem]
		let results = buildModelObjectSet(metadataQueryResults)
		query.enableUpdates()

		updateWithResults(results, removedResults: NSOrderedSet(), addedResults: NSOrderedSet(), changedResults: NSOrderedSet())
	}

	fileprivate func updateWithResults(_ results: NSOrderedSet, removedResults: NSOrderedSet, addedResults: NSOrderedSet, changedResults: NSOrderedSet) {
		let queryResults = results.array as! [QBEDocumentBrowserModel]
		let queryAnimations: [QBEDocumentBrowserAnimation]

		if let oldResults = previousQueryObjects {
			queryAnimations = computeAnimationsForNewResults(results, oldResults: oldResults, removedResults: removedResults, addedResults: addedResults, changedResults: changedResults)
		}
		else {
			queryAnimations = [.reload]
		}

		// After computing updates, we hang on to the current results for the next round.
		previousQueryObjects = results

		OperationQueue.main.addOperation {
			self.delegate?.manager(self, updateAvailableDocuments: queryResults, animations: queryAnimations)
		}
	}

	fileprivate func computeAnimationsForNewResults(_ newResults: NSOrderedSet, oldResults: NSOrderedSet, removedResults: NSOrderedSet, addedResults: NSOrderedSet, changedResults: NSOrderedSet) -> [QBEDocumentBrowserAnimation] {
		/*
		From two sets of result objects, create an array of animations that
		should be run to morph old into new results.
		*/

		let oldResultAnimations: [QBEDocumentBrowserAnimation] = removedResults.array.flatMap { removedResult in
			let oldIndex = oldResults.index(of: removedResult)
			guard oldIndex != NSNotFound else { return nil }
			return .delete(index: oldIndex)
		}

		let newResultAnimations: [QBEDocumentBrowserAnimation] = addedResults.array.flatMap { addedResult in
			let newIndex = newResults.index(of: addedResult)
			guard newIndex != NSNotFound else { return nil }
			return .add(index: newIndex)
		}

		let movedResultAnimations: [QBEDocumentBrowserAnimation] = changedResults.array.flatMap { movedResult in
			let newIndex = newResults.index(of: movedResult)
			let oldIndex = oldResults.index(of: movedResult)

			guard newIndex != NSNotFound else { return nil }
			guard oldIndex != NSNotFound else { return nil }
			guard oldIndex != newIndex   else { return nil }

			return .move(fromIndex: oldIndex, toIndex: newIndex)
		}

		// Find all the changed result animations.
		let changedResultAnimations: [QBEDocumentBrowserAnimation] = changedResults.array.flatMap { changedResult in
			let index = newResults.index(of: changedResult)
			guard index != NSNotFound else { return nil }
			return .update(index: index)
		}

		return oldResultAnimations + changedResultAnimations + newResultAnimations + movedResultAnimations
	}
}

class QBEDocumentBrowserHeaderView: UICollectionReusableView {
	@IBOutlet var label: UILabel! = nil
}

/** The `DocumentCell` class reflects the content of one document in our collection view. It manages an image view to 
display the thumbnail as well as two labels for the display name and container name (for external documents) of the 
document respectively. */
class QBEDocumentBrowserCell: UICollectionViewCell {
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var label: UILabel!
	@IBOutlet var loadingIndicator: UIActivityIndicatorView!
	@IBOutlet var subtitleLabel: UILabel!

	override func awakeFromNib() {
		super.awakeFromNib()
		let gr = UILongPressGestureRecognizer(target: self, action: #selector(self.longPress(_:)))
		self.addGestureRecognizer(gr)
	}

	var documentURL: URL? = nil

	var thumbnail: UIImage? {
		didSet {
			imageView.image = thumbnail
			contentView.backgroundColor = thumbnail != nil ? UIColor.white : UIColor.lightGray
		}
	}

	var title = "" {
		didSet {
			label.text = title
		}
	}

	var downloaded: Bool = true {
		didSet {
			imageView.alpha = (downloaded ? 1.0 : 0.2)
		}
	}

	var downloading: Bool = true {
		didSet {
			loadingIndicator.isHidden = !downloading
		}
	}

	var subtitle = "" {
		didSet {
			subtitleLabel.text = subtitle
		}
	}

	override func prepareForReuse() {
		title = ""
		subtitle = ""
		thumbnail = nil
		loadingIndicator.isHidden = true
	}

	@IBAction func longPress(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if self.becomeFirstResponder() {
				self.showMenu()
			}
		}
	}

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		if action == #selector(self.delete(_:))  || action == #selector(self.rename(_:)) {
			return true
		}
		return false
	}

	private func showMenu() {
		let mc = UIMenuController.shared

		mc.menuItems = [
			UIMenuItem(title: "Rename".localized, action: #selector(self.rename(_:)))
		]

		mc.setTargetRect(self.bounds, in: self)
		mc.setMenuVisible(true, animated: true)
	}

	override func delete(_ sender: Any?) {
		if let du = self.documentURL {
			DispatchQueue.global(qos: .userInitiated).async {
				NSFileCoordinator().coordinate(writingItemAt: du, options: .forDeleting, error: nil) { (writingUrl) in
					do {
						try FileManager.default.removeItem(at: writingUrl)
					}
					catch {
						Swift.print("Failure deleting: \(error)")
					}
				}
			}
		}
	}

	@IBAction func rename(_ sender: Any?) {
		var newNameField: UITextField? = nil
		let uac = UIAlertController(title: "Rename document".localized, message: nil, preferredStyle: .alert)
		uac.addTextField { (tf) in
			tf.autocapitalizationType = .none
			tf.text = self.title
			newNameField = tf
		}

		uac.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { (act) in
		}))

		uac.addAction(UIAlertAction(title: "Rename".localized, style: .default, handler: { (act) in
			if var du = self.documentURL, let nn = newNameField!.text {
				DispatchQueue.global(qos: .userInitiated).async {
					NSFileCoordinator().coordinate(writingItemAt: du, options: .contentIndependentMetadataOnly, error: nil) { (writingUrl) in
						do {
							let ext = du.pathExtension
							var uv = URLResourceValues()
							uv.name = "\(nn).\(ext)"
							try du.setResourceValues(uv)
						}
						catch {
							Swift.print("Failure deleting: \(error)")
						}
					}
				}
			}
		}))

		self.window?.rootViewController?.present(uac, animated: true, completion: {
		})
	}

	override var canBecomeFirstResponder: Bool { return true }
}

class QBEDocumentBrowserViewController: UICollectionViewController, QBEDocumentManagerDelegate, QBEDocumentThumbnailCacheDelegate, UIDocumentPickerDelegate {
	fileprivate let manager = QBEDocumentManager(fileExtension: QBEDocument.fileExtension)
	fileprivate let dataFileManager = QBEDocumentManager(fileExtension: QBEDocument.fileExtension, inverse: true)
	fileprivate var documents = [QBEDocumentBrowserModel]()
	fileprivate var dataFileDocuments = [QBEDocumentBrowserModel]()
	fileprivate let thumbnailCache = QBEDocumentThumbnailCache(thumbnailSize: CGSize(width: 220, height: 270))

	fileprivate let supportedDocumentTypes = [
		"public.comma-separated-values-text",
		QBEDocument.typeIdentifier,
		"nl.pixelspark.warp.csv",
		"nl.pixelspark.warp.sqlite",
	]

	static let documentsSection = 0
	static let dataFilesSection = 1

	override func viewDidLoad() {
		self.manager.delegate = self
		self.dataFileManager.delegate = self
		self.thumbnailCache.delegate = self
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		//manager.stop()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		manager.start()
		dataFileManager.start()
	}

	override func viewDidAppear(_ animated: Bool) {
		/*
		Our app only supports iCloud Drive so display an error message when
		it is disabled.
		*/
		if FileManager().ubiquityIdentityToken == nil {
			self.presentCloudDisabledAlert()
		}
	}

	private func presentCloudDisabledAlert() {
		let alertController = UIAlertController(title: "iCloud is disabled".localized, message: "Please enable iCloud Drive in Settings to use this app".localized, preferredStyle: .alert)
		let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
		alertController.addAction(alertAction)
		present(alertController, animated: true, completion: nil)
	}

	fileprivate func manager(_ manager: QBEDocumentManager, updateAvailableDocuments results: [QBEDocumentBrowserModel], animations: [QBEDocumentBrowserAnimation]) {
		if animations == [QBEDocumentBrowserAnimation.reload] {
			/*
			Reload means we're reloading all items, so mark all thumbnails
			dirty and reload the collection view.
			*/
			switch manager {
			case self.manager:
				self.documents = results

			case self.dataFileManager:
				self.dataFileDocuments = results

			default:
				fatalError("Unreachable")
			}
			collectionView?.reloadData()
		}
		else {
			var indexPathsNeedingReload = [IndexPath]()
			let collectionView = self.collectionView!

			collectionView.performBatchUpdates({
				/*
				Perform all animations, and invalidate the thumbnail cache
				where necessary.
				*/
				let section: Int
				switch manager {
				case self.manager:
					section = QBEDocumentBrowserViewController.documentsSection

				case self.dataFileManager:
					section = QBEDocumentBrowserViewController.dataFilesSection

				default:
					fatalError("Unreachable")
				}

				indexPathsNeedingReload = self.processAnimations(animations, oldResults: self.documents, newResults: results, section: section)

				switch manager {
				case self.manager:
					self.documents = results

				case self.dataFileManager:
					self.dataFileDocuments = results

				default:
					fatalError("Unreachable")
				}
			},
			completion: { success in
				if success {
					collectionView.reloadItems(at: indexPathsNeedingReload)
				}
			})
		}
	}

	private func document(at indexPath: IndexPath) -> QBEDocumentBrowserModel? {
		switch indexPath.section {
		case QBEDocumentBrowserViewController.documentsSection:
			guard indexPath.row < self.documents.count else { return nil }
			return self.documents[indexPath.row]

		case QBEDocumentBrowserViewController.dataFilesSection:
			guard indexPath.row < self.dataFileDocuments.count else { return nil }
			return self.dataFileDocuments[indexPath.row]

		default:
			return nil
		}
	}

	override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		if let document = self.document(at: indexPath) {
			let visibleURLs: [URL?] = collectionView.indexPathsForVisibleItems.map { indexPath in
				if let document = self.document(at: indexPath) {
					return document.URL as URL
				}
				return nil
			}

			if !visibleURLs.contains(document.URL as URL) {
				thumbnailCache.cancelThumbnailLoadForURL(document.URL)
			}
		}
	}

	fileprivate func processAnimations(_ animations: [QBEDocumentBrowserAnimation], oldResults: [QBEDocumentBrowserModel], newResults: [QBEDocumentBrowserModel], section: Int) -> [IndexPath] {
		let collectionView = self.collectionView!

		var indexPathsNeedingReload = [IndexPath]()

		for animation in animations {
			switch animation {
			case .add(let row):
				collectionView.insertItems(at: [
					IndexPath(row: row, section: section)
				])

			case .delete(let row):
				collectionView.deleteItems(at: [
					IndexPath(row: row, section: section)
				])

				let URL = oldResults[row].URL
				self.thumbnailCache.removeThumbnailForURL(URL)

			case .move(let from, let to):
				let fromIndexPath = IndexPath(row: from, section: section)
				let toIndexPath = IndexPath(row: to, section: section)
				collectionView.moveItem(at: fromIndexPath, to: toIndexPath)

			case .update(let row):
				indexPathsNeedingReload += [
					IndexPath(row: row, section: section)
				]

				let URL = newResults[row].URL
				self.thumbnailCache.markThumbnailDirtyForURL(URL)

			case .reload:
				fatalError("Unreachable")
			}
		}
		return indexPathsNeedingReload
	}

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 2
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		switch section {
		case QBEDocumentBrowserViewController.documentsSection:
			return self.documents.count

		case  QBEDocumentBrowserViewController.dataFilesSection:
			return self.dataFileDocuments.count

		default:
			return 0
		}
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! QBEDocumentBrowserCell

		if let document = self.document(at: indexPath) {
			cell.title = document.displayName
			cell.downloaded = document.downloaded
			cell.downloading = document.downloading
			cell.documentURL = document.URL
			cell.subtitle = document.subtitle ?? ""
			cell.thumbnail = thumbnailCache.loadThumbnailForURL(document.URL)
		}
		return cell
	}

	override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
		let hdr = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! QBEDocumentBrowserHeaderView
		switch indexPath.section {
		case QBEDocumentBrowserViewController.documentsSection:
			hdr.label.text = "Documents".localized

		case QBEDocumentBrowserViewController.dataFilesSection:
			hdr.label.text = "Data files".localized

		default:
			hdr.label.text = ""
			break
		}
		return hdr
	}

	func thumbnailCache(_ thumbnailCache: QBEDocumentThumbnailCache, didLoadThumbnailsForURLs URLs: Set<URL>) {
		let documentPaths: [IndexPath] = URLs.flatMap { URL in
			guard let matchingDocumentIndex = documents.index(where: { $0.URL as URL == URL }) else { return nil }
			return IndexPath(item: matchingDocumentIndex, section: QBEDocumentBrowserViewController.documentsSection)
		}

		let fileDocumentPaths: [IndexPath] = URLs.flatMap { URL in
			guard let matchingDocumentIndex = dataFileDocuments.index(where: { $0.URL as URL == URL }) else { return nil }
			return IndexPath(item: matchingDocumentIndex, section: QBEDocumentBrowserViewController.dataFilesSection)
		}

		self.collectionView!.reloadItems(at: documentPaths + fileDocumentPaths)
	}

	@IBAction func newDocument(sender: NSObject) {
		self.createNewDocumentWithTemplate { result in
			assertMainThread()
			switch result {
			case .failure(let e):
				let alertController = UIAlertController(title: "Could not create new document".localized, message: e, preferredStyle: .alert)
				let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
				alertController.addAction(alertAction)
				self.present(alertController, animated: true, completion: nil)

			case .success(let document):
				self.openDocumentAtURL(document.fileURL)
			}
		}
	}

	fileprivate func createNewDocumentWithTemplate(_ template: QBEDocumentTemplate = .empty(name: nil), completion: @escaping ((Fallible<QBEDocument>) -> ())) {
		let fileName: String
		switch template {
		case .empty(let name):
			fileName = name ?? "Untitled".localized

		case .document(let doc):
			do {
				fileName = try doc.fileURL.resourceValues(forKeys: [.nameKey]).name ?? ("Untitled".localized)
			}
			catch {
				fileName = "Untitled".localized
			}

		case .file(let f):
			fileName = f.deletingPathExtension().lastPathComponent
		}

		/*
		We don't create a new document on the main queue because the call to
		fileManager.URLForUbiquityContainerIdentifier could potentially block
		*/
		self.manager.workerQueue.addOperation {
			let fileManager = FileManager()
			guard let baseURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").appendingPathComponent(fileName) else {
				OperationQueue.main.addOperation {
					completion(.failure("Please enable iCloud Drive in Settings to use this app".localized))
				}
				return
			}

			// Determine file extension
			let ext: String
			switch template {
			case .file(let url):
				ext = url.pathExtension 

			default:
				ext = QBEDocument.fileExtension
			}

			var target = baseURL.appendingPathExtension(ext)

			/*
			We will append this value to our name until we find a path that
			doesn't exist.
			*/
			var nameSuffix = 2

			/*
			Find a suitable filename that doesn't already exist on disk.
			Do not use `fileManager.fileExistsAtPath(target.path!)` because
			the document might not have downloaded yet.
			*/
			while (target as NSURL).checkPromisedItemIsReachableAndReturnError(nil) {
				target = URL(fileURLWithPath: baseURL.path + "-\(nameSuffix).\(ext)")
				nameSuffix += 1
			}

			let writeIntent = NSFileAccessIntent.writingIntent(with: target, options: .forReplacing)
			var readIntent: NSFileAccessIntent? = nil
			var intents = [writeIntent]

			// Coordinate reading on the source path and writing on the destination path to copy.
			if case .file(let templateURL) = template {
				readIntent = NSFileAccessIntent.readingIntent(with: templateURL, options: [])
				intents.append(readIntent!)
			}

			NSFileCoordinator().coordinate(with: intents, queue: self.manager.workerQueue) { error in
				if error != nil {
					OperationQueue.main.addOperation {
						completion(.failure(error?.localizedDescription ?? "An unknown error occurred.".localized))
					}
					return
				}

				do {
					if let readIntent = readIntent {
						try fileManager.copyItem(at: readIntent.url, to: writeIntent.url)
						try (writeIntent.url as NSURL).setResourceValue(true, forKey: URLResourceKey.hasHiddenExtensionKey)

						OperationQueue.main.addOperation {
							let document = QBEDocument(fileURL: writeIntent.url)
							completion(.success(document))
						}
					}
					else {
						let document = QBEDocument(fileURL: writeIntent.url)

						document.save(to: writeIntent.url, for: .forCreating, completionHandler: { (success) in
							if success {
								do {
									try (writeIntent.url as NSURL).setResourceValue(true, forKey: URLResourceKey.hasHiddenExtensionKey)
								}
								catch {
									OperationQueue.main.addOperation {
										completion(.failure(error.localizedDescription))
									}
									return
								}

								OperationQueue.main.addOperation {
									completion(.success(document))
								}
							}
						})
					}
				}
				catch {
					fatalError("Unexpected error during trivial file operations: \(error)")
				}
			}
		}
	}

	func openDocumentAtURL(_ url: URL) {
		do {
			// Is this a data file or a Warp document?
			let info = try url.resourceValues(forKeys: [.typeIdentifierKey, .nameKey, .localizedNameKey])

			switch info.typeIdentifier ?? "" {
			case QBEDocument.typeIdentifier:
				let controller = storyboard!.instantiateViewController(withIdentifier: "Document") as! QBEDocumentViewController
				controller.documentURL = url
				show(controller, sender: self)

			case "public.comma-separated-values-text":
				fallthrough

			default:
				let fn = info.localizedName ?? "Untitled".localized
				self.createNewDocumentWithTemplate(.empty(name: fn), completion: { result in
					assertMainThread()
					switch result {
					case .failure(let e):
						let alertController = UIAlertController(title: "Could not open document".localized, message: e, preferredStyle: .alert)
						let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
						alertController.addAction(alertAction)
						self.present(alertController, animated: true, completion: nil)

					case .success(let document):
						document.open { success in
							if success {
								let s: QBEStep?
								if url.pathExtension.lowercased() == "sqlite" {
									s = QBESQLiteSourceStep(url: url)
								}
								else {
									s = QBECSVSourceStep(url: url)
								}

								if let s = s {
									let tablet = QBEChainTablet(chain: QBEChain(head: s))
									document.addTablet(tablet)
									document.updateChangeCount(.done)
									document.save(to: document.fileURL, for: UIDocumentSaveOperation.forOverwriting, completionHandler: { (success) in
										if success {
											let controller = self.storyboard!.instantiateViewController(withIdentifier: "Document") as! QBEDocumentViewController
											controller.documentURL = document.fileURL
											self.show(controller, sender: self)
										}
										else {
											let alertController = UIAlertController(title: "Could not open document".localized, message: nil, preferredStyle: .alert)
											let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
											alertController.addAction(alertAction)
											self.present(alertController, animated: true, completion: nil)
										}
									})
								}
							}
							else {
								let alertController = UIAlertController(title: "Could not open document".localized, message: nil, preferredStyle: .alert)
								let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
								alertController.addAction(alertAction)
								self.present(alertController, animated: true, completion: nil)
							}
						}
					}
				})
				break;
			}
		}
		catch {
			let alertController = UIAlertController(title: "Could not open document".localized, message: error.localizedDescription, preferredStyle: .alert)
			let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
			alertController.addAction(alertAction)
			self.present(alertController, animated: true, completion: nil)
		}
	}

	func openDocumentAtURL(_ url: URL, copyBeforeOpening: Bool) {
		if copyBeforeOpening  {
			// Duplicate the document and open it.
			createNewDocumentWithTemplate(.file(url)) { result in
				switch result {
				case .failure(let e):
					asyncMain {
						let alertController = UIAlertController(title: "Could not open document".localized, message: e, preferredStyle: .alert)
						let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
						alertController.addAction(alertAction)
						self.present(alertController, animated: true, completion: nil)
					}

				case .success(let doc):
					asyncMain {
						self.openDocumentAtURL(doc.fileURL)
					}
				}
			}
		}
		else {
			openDocumentAtURL(url)
		}
	}

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if let document = self.document(at: indexPath) {
			// is the document downloaded?
			do {
				let info = try document.URL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
				if let s = info.ubiquitousItemDownloadingStatus, s == .notDownloaded {
					let j = Job(.userInitiated)
					j.async {
						do {
							try FileManager.default.startDownloadingUbiquitousItem(at: document.URL)
						}
						catch {
							Swift.print("Error downloading: \(error.localizedDescription)")
						}
					}
				}
				else {
					// Downloaded or yolo
					self.openDocumentAtURL(document.URL, copyBeforeOpening: false)
				}
			}
			catch {
				let alertController = UIAlertController(title: "Could not open document".localized, message: error.localizedDescription, preferredStyle: .alert)
				let alertAction = UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil)
				alertController.addAction(alertAction)
				self.present(alertController, animated: true, completion: nil)
			}
		}
	}

	@IBAction func importUsingPicker(_ sender: AnyObject) {
		let picker = UIDocumentPickerViewController(documentTypes: self.supportedDocumentTypes, in: .open)
		picker.delegate = self

		self.present(picker, animated:true, completion: nil)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
		// Do nothing, document will be added to the list
	}
}
