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
	
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}

	override func sentence(locale: QBELocale) -> QBESentence {
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
		self.type = QBEDebugType(rawValue: aDecoder.decodeStringForKey("type") ?? "") ?? QBEDebugType.None
		super.init(coder: aDecoder)
	}
	
	static func supportsSecureCoding() -> Bool {
		return true
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeString(self.type.rawValue, forKey: "type")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		switch type {
			case .None:
				callback(.Success(data))
			
			case .Rasterize:
				data.raster(job, callback: { (raster) -> () in
					callback(raster.use({QBERasterData(raster: $0)}))
				})
			
			case .Cache:
				/* Make sure the QBESQLiteCachedData object stays around until completion by capturing it in the
				completion callback. Under normal circumstances the object will not keep references to itself 
				and would be released automatically without this trick, because we don't store it. */
				var x: QBESQLiteCachedData? = nil
				x = QBESQLiteCachedData(source: data, job: job, completion: {(_) in callback(.Success(x!))})
			}
	}
}