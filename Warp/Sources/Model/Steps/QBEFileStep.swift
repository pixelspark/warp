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

class QBEFileStep: QBEStep {
	var file: QBEFileReference? = nil

	init(file: QBEFileReference) {
		self.file = file
		super.init()
	}

	override func encode(with coder: NSCoder) {
		coder.encode(QBEPersistedFileReference(file), forKey: "file")
		super.encode(with: coder)
	}

	required init(coder aDecoder: NSCoder) {
		let d = aDecoder.decodeObject(of: [QBEPersistedFileReference.self], forKey: "file") as? QBEPersistedFileReference
		self.file = d?.file
		super.init(coder: aDecoder)
	}
	
	public required init() {
		super.init()
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		return self.fullDataset(job, callback: callback)
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let u = self.file?.url {
			do {
				let data = try Data(contentsOf: u)
				if let string = String(data: data, encoding: .utf8) {
					let raster = Raster(data: [[.string(string)]], columns: [Column("Data".localized)])
					return callback(.success(RasterDataset(raster: raster)))
				}
			}
			catch _ {
				return callback(.failure("Could not open file".localized))
			}
		}
		return callback(.failure("Could not open file".localized))
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let fileTypes = [
			"public.text",
			"public.plain-text"
		]

		return QBESentence(format: NSLocalizedString("Read text file [#]", comment: ""),
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
	}
}
