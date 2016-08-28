import Foundation
import WarpCore

private class QBEDelayTransformer: Transformer {
	let delay: TimeInterval

	init(source: WarpCore.Stream, delay: TimeInterval) {
		self.delay = delay
		super.init(source: source)
	}

	private override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: Sink) {
		job.log("Delaying \(rows.count) rows for \(self.delay)s")
		job.queue.asyncAfter(deadline: DispatchTime.now() + self.delay) {
			callback(.success(rows), streamStatus)
		}
	}

	private override func clone() -> WarpCore.Stream {
		return QBEDelayTransformer(source: self.source.clone(), delay: self.delay)
	}
}

class QBEDebugStep: QBEStep, NSSecureCoding {
	enum QBEDebugType: String {
		case none = "none"
		case rasterize = "rasterize"
		case delay = "delay"
		
		var description: String { get {
			switch self {
			case .none: return "(No action)".localized
			case .rasterize: return "Download data to memory".localized
			case .delay: return "Delay".localized
			}
		} }
	}
	
	var type: QBEDebugType = .none
	
	required init() {
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceOptionsToken(options: [
				QBEDebugType.none.rawValue: QBEDebugType.none.description,
				QBEDebugType.rasterize.rawValue: QBEDebugType.rasterize.description,
				QBEDebugType.delay.rawValue: QBEDebugType.delay.description,
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
	
	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		switch type {
		case .none:
			callback(.success(data))

		case .delay:
			callback(.success(StreamDataset(source: QBEDelayTransformer(source: data.stream(), delay: 1.0))))

		case .rasterize:
			data.raster(job, callback: { (raster) -> () in
				callback(raster.use({RasterDataset(raster: $0)}))
			})
		}
	}
}
