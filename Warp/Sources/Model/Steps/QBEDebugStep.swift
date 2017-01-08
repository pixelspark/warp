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

private class QBEDelayTransformer: Transformer {
	let delay: TimeInterval

	init(source: WarpCore.Stream, delay: TimeInterval) {
		self.delay = delay
		super.init(source: source)
	}

	fileprivate override func transform(_ rows: Array<Tuple>, streamStatus: StreamStatus, job: Job, callback: @escaping Sink) {
		job.log("Delaying \(rows.count) rows for \(self.delay)s")
		job.queue.asyncAfter(deadline: DispatchTime.now() + self.delay) {
			callback(.success(rows), streamStatus)
		}
	}

	fileprivate override func clone() -> WarpCore.Stream {
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
