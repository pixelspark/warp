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

class QBESortStep: QBEStep {
	var orders: [Order] = []

	required init() {
		super.init()
	}

	init(previous: QBEStep?, orders: [Order] = []) {
		self.orders = orders
		super.init(previous: previous)
	}

	required init(coder aDecoder: NSCoder) {
		self.orders = (aDecoder.decodeObject(forKey: "orders") as? [Order]) ?? []
		super.init(coder: aDecoder)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		if orders.isEmpty {
			return QBESentence(format: NSLocalizedString("Sort rows on [#]", comment: ""),
				QBESentenceFormulaToken(expression: Literal(Value.bool(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
					self?.orders.append(Order(expression: newExpression, ascending: true, numeric: true))
				})
			)
		}
		if orders.count == 1 {
			let order = orders[0]
			return QBESentence(format: NSLocalizedString("Sort rows on [#][#][#]", comment: ""),
				QBESentenceFormulaToken(expression: order.expression ?? Literal(.bool(false)), locale: locale, callback: { (newExpression) -> () in
					order.expression = newExpression
				}, contextCallback: self.contextCallbackForFormulaSentence),
				QBESentenceOptionsToken(options: [
					"numeric": NSLocalizedString("numerically", comment: ""),
					"alphabetic": NSLocalizedString("alphabetically", comment: "")
					], value: order.numeric ? "numeric" : "alphabetic", callback: { (newOrder) -> () in
						order.numeric = (newOrder == "numeric")
				}),
				QBESentenceOptionsToken(options: [
					"ascending": NSLocalizedString("ascending", comment: ""),
					"descending": NSLocalizedString("descending", comment: "")
				], value: order.ascending ? "ascending" : "descending", callback: { (newOrder) -> () in
					order.ascending = (newOrder == "ascending")
				})
			)
		}
		else {
			return QBESentence([
				QBESentenceLabelToken(String(format: NSLocalizedString("Sort rows using %d criteria", comment: ""), orders.count))
			])
		}
	}

	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBESortStep {
			if p.orders == self.orders {
				return .advised(p)
			}
			else if p.orders.count == 1 && self.orders.count == 1 && p.orders.first!.expression == self.orders.first!.expression {
				// Same field, different settings, last one counts
				return .advised(self)
			}
		}
		return .impossible
	}

	override func encode(with coder: NSCoder) {
		coder.encode(self.orders, forKey: "orders")
		super.encode(with: coder)
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(data.sort(orders)))
	}

	override func mutableDataset(_ job: Job, callback: @escaping (Fallible<MutableDataset>) -> ()) {
		if let p = self.previous {
			return p.mutableDataset(job, callback: callback)
		}
		return callback(.failure("This data set cannot be changed.".localized))
	}
}
