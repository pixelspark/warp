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
			return QBESentence([QBESentenceText(NSLocalizedString("Data table", comment: ""))])

		case .write:
			return QBESentence([QBESentenceText(NSLocalizedString("Write to data table", comment: ""))])
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

	override internal var mutableDataset: MutableDataset? {
		return RasterMutableDataset(raster: self.raster)
	}
}
