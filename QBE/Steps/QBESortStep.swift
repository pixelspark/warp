import Foundation
import WarpCore

class QBESortStep: QBEStep {
	var orders: [QBEOrder] = []
	
	init(previous: QBEStep?, orders: [QBEOrder] = []) {
		self.orders = orders
		super.init(previous: previous)
	}

	required init(coder aDecoder: NSCoder) {
		self.orders = (aDecoder.decodeObjectForKey("orders") as? [QBEOrder]) ?? []
		super.init(coder: aDecoder)
	}

	override func sentence(locale: QBELocale) -> QBESentence {
		if orders.count == 0 {
			return QBESentence(format: NSLocalizedString("Sort rows on [#]", comment: ""),
				QBESentenceFormula(expression: QBELiteralExpression(QBEValue.BoolValue(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
					self?.orders.append(QBEOrder(expression: newExpression, ascending: true, numeric: true))
				})
			)
		}
		if orders.count == 1 {
			let order = orders[0]
			return QBESentence(format: NSLocalizedString("Sort rows on [#][#][#]", comment: ""),
				QBESentenceFormula(expression: order.expression ?? QBELiteralExpression(.BoolValue(false)), locale: locale, callback: { (newExpression) -> () in
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

	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.orders, forKey: "orders")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData, job: QBEJob?, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(data.sort(orders)))
	}
}