import Foundation
import WarpCore

class QBERasterStep: QBEStep {
	let raster: Raster
	
	init(raster: Raster) {
		self.raster = raster.clone(false)
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.raster = (aDecoder.decodeObjectForKey("raster") as? Raster) ?? Raster()
		super.init(coder: aDecoder)
	}

	required init() {
		raster = Raster(data: [], columnNames: [])
		super.init()
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		switch variant {
		case .Neutral, .Read:
			return QBESentence([QBESentenceText(NSLocalizedString("Data table", comment: ""))])

		case .Write:
			return QBESentence([QBESentenceText(NSLocalizedString("Write to data table", comment: ""))])
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(raster, forKey: "raster")
		super.encodeWithCoder(coder)
	}
	
	override func fullData(job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(RasterData(raster: self.raster)))
	}
	
	override func exampleData(job: Job?, maxInputRows: Int, maxOutputRows: Int, callback: (Fallible<Data>) -> ()) {
		callback(.Success(RasterData(raster: self.raster).limit(min(maxInputRows, maxOutputRows))))
	}

	override internal var mutableData: MutableData? {
		return RasterMutableData(raster: self.raster)
	}
}