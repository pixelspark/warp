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

class QBERasterStep: QBEStep {
	let raster: Raster
	
	init(raster: Raster) {
		self.raster = raster.clone(false)
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.raster = (aDecoder.decodeObject(forKey: "raster") as? Raster) ?? Raster()
		super.init(coder: aDecoder)
	}

	required init() {
		raster = Raster(data: [], columns: [])
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		switch variant {
		case .neutral, .read:
			return QBESentence([QBESentenceLabelToken(NSLocalizedString("Data table", comment: ""))])

		case .write:
			return QBESentence([QBESentenceLabelToken(NSLocalizedString("Write to data table", comment: ""))])
		}
	}
	
	override func encode(with coder: NSCoder) {
		coder.encode(raster, forKey: "raster")
		super.encode(with: coder)
	}
	
	override func fullDataset(_ job: Job?, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(RasterDataset(raster: self.raster)))
	}
	
	override func exampleDataset(_ job: Job?, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(RasterDataset(raster: self.raster).limit(min(maxInputRows, maxOutputRows))))
	}

	override func mutableDataset(_ job: Job, callback: @escaping (Fallible<MutableDataset>) -> ()) {
		return callback(.success(RasterMutableDataset(raster: self.raster)))
	}
}
