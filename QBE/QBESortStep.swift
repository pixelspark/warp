import Foundation

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
	
	override func explain(locale: QBELocale, short: Bool) -> String {
		if !short {
			if orders.count == 1 {
				let order = orders[0]
				if let explanation = order.expression?.explain(locale) {
					return String(format: NSLocalizedString("Sort rows on %@", comment: "QBESortStep explain one order"), explanation)
				}
			}
			else if orders.count > 1 {
				return String(format: NSLocalizedString("Sort rows using %d criteria", comment: ""), orders.count)
			}
		}
		
		return NSLocalizedString("Sort rows", comment: "QBESortStep explain")
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(self.orders, forKey: "orders")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: QBEData, job: QBEJob?, callback: (QBEData) -> ()) {
		callback(data.sort(by: orders))
	}
}