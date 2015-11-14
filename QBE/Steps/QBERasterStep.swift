import Foundation
import WarpCore

class QBERasterStep: QBEStep {
	let raster: QBERaster
	
	init(raster: QBERaster) {
		self.raster = raster
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.raster = (aDecoder.decodeObjectForKey("raster") as? QBERaster) ?? QBERaster()
		super.init(coder: aDecoder)
	}

	required init() {
		raster = QBERaster(data: [], columnNames: [])
		super.init()
	}

	override func sentence(locale: QBELocale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([QBESentenceText(NSLocalizedString("Data table", comment: ""))])
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(raster, forKey: "raster")
		super.encodeWithCoder(coder)
	}
	
	override func fullData(job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(QBERasterData(raster: self.raster)))
	}
	
	override func exampleData(job: QBEJob?, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(QBERasterData(raster: self.raster).limit(min(maxInputRows, maxOutputRows))))
	}
}