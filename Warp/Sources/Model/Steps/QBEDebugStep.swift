import Foundation
import WarpCore

class QBEDebugStep: QBEStep, NSSecureCoding {
	enum QBEDebugType: String {
		case none = "none"
		case rasterize = "rasterize"
		
		var description: String { get {
			switch self {
				case .none:
					return NSLocalizedString("(No action)", comment: "")
				
				case .rasterize:
					return NSLocalizedString("Download data to memory", comment: "")
			}
		} }
	}
	
	var type: QBEDebugType = .none
	
	required init() {
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceOptions(options: [
				QBEDebugType.none.rawValue: QBEDebugType.none.description,
				QBEDebugType.rasterize.rawValue: QBEDebugType.rasterize.description,
			], value: self.type.rawValue, callback: { [weak self] (newType) -> () in
				if let x = QBEDebugType(rawValue: newType) {
					self?.type = x
				}
			})
		])
	}
	
	required init(coder aDecoder: NSCoder) {
		self.type = QBEDebugType(rawValue: aDecoder.decodeString(forKey:"type") ?? "") ?? QBEDebugType.none
		super.init(coder: aDecoder)
	}
	
	static var supportsSecureCoding: Bool = true
	
	override func encode(with coder: NSCoder) {
		coder.encodeString(self.type.rawValue, forKey: "type")
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		switch type {
		case .none:
			callback(.success(data))

		case .rasterize:
			data.raster(job, callback: { (raster) -> () in
				callback(raster.use({RasterDataset(raster: $0)}))
			})
		}
	}
}
