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
		self.orders = (aDecoder.decodeObjectForKey("orders") as? [Order]) ?? []
		super.init(coder: aDecoder)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		if orders.isEmpty {
			return QBESentence(format: NSLocalizedString("Sort rows on [#]", comment: ""),
				QBESentenceFormula(expression: Literal(Value.BoolValue(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
					self?.orders.append(Order(expression: newExpression, ascending: true, numeric: true))
				})
			)
		}
		if orders.count == 1 {
			let order = orders[0]
			return QBESentence(format: NSLocalizedString("Sort rows on [#][#][#]", comment: ""),
				QBESentenceFormula(expression: order.expression ?? Literal(.BoolValue(false)), locale: locale, callback: { (newExpression) -> () in
					order.expression = newExpression
				}),
				QBESentenceOptions(options: [
					"numeric": NSLocalizedString("numerically", comment: ""),
					"alphabetic": NSLocalizedString("alphabetically", comment: "")
					], value: order.numeric ? "numeric" : "alphabetic", callback: { (newOrder) -> () in
						order.numeric = (newOrder == "numeric")
				}),
				QBESentenceOptions(options: [
					"ascending": NSLocalizedString("ascending", comment: ""),
					"descending": NSLocalizedString("descending", comment: "")
				], value: order.ascending ? "ascending" : "descending", callback: { (newOrder) -> () in
					order.ascending = (newOrder == "ascending")
				})
			)
		}
		else {
			return QBESentence([
				QBESentenceText(String(format: NSLocalizedString("Sort rows using %d criteria", comment: ""), orders.count))
			])
		}
	}

	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBESortStep {
			if p.orders == self.orders {
				return .Advised(p)
			}
			else if p.orders.count == 1 && self.orders.count == 1 && p.orders.first!.expression == self.orders.first!.expression {
				// Same field, different settings, last one counts
				return .Advised(self)
			}
		}
		return .Impossible
	}

	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.orders, forKey: "orders")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: Data, job: Job?, callback: (Fallible<Data>) -> ()) {
		callback(.Success(data.sort(orders)))
	}
}