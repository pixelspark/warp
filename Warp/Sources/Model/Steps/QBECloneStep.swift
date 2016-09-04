/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

class QBECloneStep: QBEStep, NSSecureCoding, QBEChainDependent {
	weak var right: QBEChain?
	
	init(chain: QBEChain?) {
		super.init()
		self.right = chain
	}
	
	required init(coder aDecoder: NSCoder) {
		right = aDecoder.decodeObject(of: QBEChain.self, forKey: "right")
		super.init(coder: aDecoder)
	}

	required init() {
		right = nil
		super.init()
	}

	static var supportsSecureCoding: Bool = true
	
	override func encode(with coder: NSCoder) {
		coder.encode(right, forKey: "right")
		super.encode(with: coder)
	}
	
	var recursiveDependencies: Set<QBEDependency> {
		if let r = right {
			return Set([QBEDependency(step: self, dependsOn: r)]).union(r.recursiveDependencies)
		}
		return []
	}

	var directDependencies: Set<QBEDependency> {
		if let r = right {
			return Set([QBEDependency(step: self, dependsOn: r)])
		}
		return []
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([
			QBESentenceLabelToken(NSLocalizedString("Cloned data", comment: ""))
		])
	}
	
	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let r = self.right, let h = r.head {
			h.fullDataset(job, callback: callback)
		}
		else {
			callback(.failure(NSLocalizedString("Clone step cannot find the original to clone from.", comment: "")))
		}
	}
	
	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let r = self.right, let h = r.head {
			h.exampleDataset(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: callback)
		}
		else {
			callback(.failure(NSLocalizedString("Clone step cannot find the original to clone from.", comment: "")))
		}
	}

	override var mutableDataset: MutableDataset? {
		return self.right?.head?.mutableDataset
	}
	
	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		fatalError("QBECloneStep.apply should not be used")
	}
}
