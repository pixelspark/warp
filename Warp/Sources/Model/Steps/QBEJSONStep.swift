/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore
import WarpConduit

class QBEJSONSourceStep: QBEStep {
	var file: QBEFileReference? = nil

	required init() {
		super.init()
	}

	init(url: URL) {
		self.file = QBEFileReference.absolute(url)
		super.init()
	}

	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObject(forKey: "fileBookmark") as? Data
		let u = aDecoder.decodeObject(forKey: "fileURL") as? URL
		self.file = QBEFileReference.create(u, d)

		super.init(coder: aDecoder)
	}

	deinit {
		self.file?.url?.stopAccessingSecurityScopedResource()
	}

	private func sourceDataset() -> Fallible<Dataset> {
		if let url = file?.url {
			let s = JSONStream(url: url as URL)
			return .success(StreamDataset(source: s))
		}
		else {
			return .failure(NSLocalizedString("The location of the JSON source file is invalid.", comment: ""))
		}
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(sourceDataset())
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(sourceDataset().use{ $0.limit(maxInputRows) })
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)

		coder.encode(self.file?.url, forKey: "fileURL")
		coder.encode(self.file?.bookmark, forKey: "fileBookmark")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let fileTypes = [
			"json",
			"public.json",
		]

		return QBESentence(format: NSLocalizedString("Read JSON file [#]", comment: ""),
		   QBESentenceFileToken(file: self.file, allowedFileTypes: fileTypes, callback: { [weak self] (newFile) -> () in
				self?.file = newFile
			})
		)
	}

	override func willSaveToDocument(_ atURL: URL) {
		self.file = self.file?.persist(atURL)
	}

	override func didLoadFromDocument(_ atURL: URL) {
		self.file = self.file?.resolve(atURL)
		if let b = self.file?.url?.startAccessingSecurityScopedResource(), !b {
			trace("startAccessingSecurityScopedResource for \(atURL) failed")
		}
	}
}
