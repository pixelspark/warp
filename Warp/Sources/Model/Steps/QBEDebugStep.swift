import Foundation
import WarpCore

class QBEDebugStep: QBEStep, NSSecureCoding {
	enum QBEDebugType: String {
		case None = "none"
		case Rasterize = "rasterize"
		case Cache = "cache"
		
		var description: String { get {
			switch self {
				case .None:
					return NSLocalizedString("(No action)", comment: "")
				
				case .Rasterize:
					return NSLocalizedString("Download data to memory", comment: "")
				
				case .Cache:
					return NSLocalizedString("Download data to SQLite", comment: "")
			}
		} }
	}
	
	var type: QBEDebugType = .None
	
	required init() {
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceOptions(options: [
				QBEDebugType.None.rawValue: QBEDebugType.None.description,
				QBEDebugType.Rasterize.rawValue: QBEDebugType.Rasterize.description,
				QBEDebugType.Cache.rawValue: QBEDebugType.Cache.description
			], value: self.type.rawValue, callback: { [weak self] (newType) -> () in
				if let x = QBEDebugType(rawValue: newType) {
					self?.type = x
				}
			})
		])
	}
	
	required init(coder aDecoder: NSCoder) {
		self.type = QBEDebugType(rawValue: aDecoder.decodeString(forKey:"type") ?? "") ?? QBEDebugType.None
		super.init(coder: aDecoder)
	}
	
	static var supportsSecureCoding: Bool = true
	
	override func encode(with coder: NSCoder) {
		coder.encodeString(self.type.rawValue, forKey: "type")
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job, callback: (Fallible<Dataset>) -> ()) {
		switch type {
			case .None:
				callback(.success(data))
			
			case .Rasterize:
				data.raster(job, callback: { (raster) -> () in
					callback(raster.use({RasterDataset(raster: $0)}))
				})
			
			case .Cache:
				/* Make sure the QBESQLiteCachedDataset object stays around until completion by capturing it in the
				completion callback. Under normal circumstances the object will not keep references to itself 
				and would be released automatically without this trick, because we don't store it. */
				var x: QBESQLiteCachedDataset? = nil
				x = QBESQLiteCachedDataset(source: data, job: job, completion: {(_) in callback(.success(x!))})
			}
	}
}
