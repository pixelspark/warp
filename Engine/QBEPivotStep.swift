import Foundation

private func toDictionary<E, K, V>(array: [E], transformer: (element: E) -> (key: K, value: V)?) -> Dictionary<K, V> {
	return array.reduce([:]) { (var dict, e) in
		if let (key, value) = transformer(element: e) {
			dict[key] = value
		}
		return dict
	}
}

class QBEPivotStep: QBEStep {
	var rows: [QBEColumn] = []
	var columns: [QBEColumn] = []
	var aggregates: [QBEColumn] = []
	
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		
		if let a = aDecoder.decodeObjectForKey("aggregates") as? [String] {
			aggregates = a.map({QBEColumn($0)})
		}
		
		if let r = aDecoder.decodeObjectForKey("rows") as? [String] {
			aggregates = r.map({QBEColumn($0)})
		}
		
		if let c = aDecoder.decodeObjectForKey("columns") as? [String] {
			aggregates = c.map({QBEColumn($0)})
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		
		// NSCoder can't store QBEColumn, so we store the raw names
		let a = aggregates.map({$0.name})
		let c = columns.map({$0.name})
		let r = rows.map({$0.name})
		
		coder.encodeObject(r, forKey: "rows")
		coder.encodeObject(c, forKey: "columns")
		coder.encodeObject(a, forKey: "aggregates")
	}
	
	override func description(locale: QBELocale) -> String {
		return NSLocalizedString("Pivot data", comment: "")
	}
	
	override func apply(data: QBEData?) -> QBEData? {
		let groups = toDictionary(rows, { ($0, QBESiblingExpression(columnName: $0) as QBEExpression) })
		let values = toDictionary(aggregates, { ($0, QBEAggregation(map: QBESiblingExpression(columnName: $0), reduce: QBEFunction.Count)) })
		
		return data?.aggregate(groups, values: values)
	}
}