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

	override var mutableDataset: MutableDataset? {
		if let md = self.previous?.mutableDataset {
			return QBEMutableDatasetWithRowsShuffled(original: md)
		}
		return nil
	}
}
