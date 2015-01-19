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
	var aggregates: [QBEAggregation] = []
	
	override init(previous: QBEStep?) {
		super.init(previous: previous)
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		
		aggregates = aDecoder.decodeObjectForKey("aggregates") as? [QBEAggregation] ?? []
		
		if let r = aDecoder.decodeObjectForKey("rows") as? [String] {
			rows = r.map({QBEColumn($0)})
		}
		
		if let c = aDecoder.decodeObjectForKey("columns") as? [String] {
			columns = c.map({QBEColumn($0)})
		}
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		
		// NSCoder can't store QBEColumn, so we store the raw names
		let c = columns.map({$0.name})
		let r = rows.map({$0.name})
		
		coder.encodeObject(r, forKey: "rows")
		coder.encodeObject(c, forKey: "columns")
		coder.encodeObject(aggregates, forKey: "aggregates")
	}
	
	override func description(locale: QBELocale) -> String {
		return NSLocalizedString("Pivot data", comment: "")
	}
	
	override func apply(data: QBEData?) -> QBEData? {
		let groups = toDictionary(rows, { ($0, QBESiblingExpression(columnName: $0) as QBEExpression) })
		
		/* FIXME: the explanation is locale-depended. We need to keep column names constant. Suggest to use 
		toLocale(QBEDefaultLocale) or to let the user choose a title and then store it permanently in QBEAggregation. */
		let values = toDictionary(aggregates, { ($0.targetColumnName, $0) })
		return data?.aggregate(groups, values: values)
	}
}