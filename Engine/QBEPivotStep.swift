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
		
		aggregates = (aDecoder.decodeObjectForKey("aggregates") as? [QBEAggregation]) ?? []
		
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
	
	override func explain(locale: QBELocale) -> String {
		return NSLocalizedString("Pivot data", comment: "")
	}
	
	override func apply(data: QBEData?, callback: (QBEData?) -> ()) {
		var rowGroups = toDictionary(rows, { ($0, QBESiblingExpression(columnName: $0) as QBEExpression) })
		let colGroups = toDictionary(columns, { ($0, QBESiblingExpression(columnName: $0) as QBEExpression) })
		for (k, v) in colGroups {
			rowGroups[k] = v
		}
		
		let values = toDictionary(aggregates, { ($0.targetColumnName, $0) })
		if let resultData = data?.aggregate(rowGroups, values: values) {
			if columns.count == 0 {
				callback(resultData)
			}
			else {
				let pivotedData = resultData.pivot(columns, vertical: rows, values: aggregates.map({$0.targetColumnName}))
				callback(pivotedData)
			}
		}
		else {
			callback(nil)
		}
	}
}