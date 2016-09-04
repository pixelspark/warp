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

private func toDictionary<E, K, V>(_ array: [E], transformer: (_ element: E) -> (key: K, value: V)?) -> Dictionary<K, V> {
	return array.reduce([:]) { dict, e in
		var dict = dict

		if let (key, value) = transformer(e) {
			dict[key] = value
		}
		return dict
	}
}

class QBEPivotStep: QBEStep {
	var rows: OrderedSet<Column> = []
	var columns: OrderedSet<Column> = []
	var aggregates: [Aggregation] = []

	required init() {
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		
		aggregates = (aDecoder.decodeObject(forKey: "aggregates") as? [Aggregation]) ?? []
		
		if let r = aDecoder.decodeObject(forKey: "rows") as? [String] {
			rows = OrderedSet(r.map({Column($0)}))
		}
		
		if let c = aDecoder.decodeObject(forKey: "columns") as? [String] {
			columns = OrderedSet(c.map({Column($0)}))
		}
	}
	
	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		fixupColumnNames()
		
		// NSCoder can't store Column, so we store the raw names
		let c = columns.map({$0.name})
		let r = rows.map({$0.name})
		
		coder.encode(r, forKey: "rows")
		coder.encode(c, forKey: "columns")
		coder.encode(aggregates, forKey: "aggregates")
	}
	
	private func explanation(_ locale: Language) -> String {
		if aggregates.count == 1 {
			let aggregation = aggregates[0]
			if rows.count != 1 || !columns.isEmpty {
				return String(format: NSLocalizedString("Pivot: %@ of %@", comment: "Pivot with 1 aggregate"),
					aggregation.aggregator.reduce.explain(locale),
					aggregation.aggregator.map.explain(locale))
			}
			else {
				let row = rows[0]
				return String(format: NSLocalizedString("Pivot: %@ of %@ grouped by %@", comment: "Pivot with 1 aggregate"),
					aggregation.aggregator.reduce.explain(locale),
					aggregation.aggregator.map.explain(locale),
					row.name)
			}
		}
		
		return NSLocalizedString("Pivot data", comment: "")
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence([QBESentenceLabelToken(self.explanation(locale))])
	}
	
	private func fixupColumnNames() {
		var columns = Set(rows)
		
		// Make sure we don't create duplicate columns
		for idx in 0..<self.columns.count {
			let column = self.columns[idx]
			if columns.contains(column) {
				self.columns[idx] = column.newName({return !columns.contains($0)})
			}
		}
		
		columns.formUnion(Set(columns))
		
		for idx in 0..<aggregates.count {
			let aggregation = aggregates[idx]
			
			if columns.contains(aggregation.targetColumn) {
				aggregation.targetColumn = aggregation.targetColumn.newName({return !columns.contains($0)})
			}
		}
	}
	
	override func apply(_ data: Dataset, job: Job?, callback: @escaping (Fallible<Dataset>) -> ()) {
		if self.rows.isEmpty && self.columns.isEmpty && self.aggregates.isEmpty {
			callback(.failure(NSLocalizedString("Click the settings button to configure the pivot table.", comment: "")))
			return
		}

		fixupColumnNames()
		var rowGroups = toDictionary(Array(rows), transformer: { ($0, Sibling($0) as Expression) })
		let colGroups = toDictionary(Array(columns), transformer: { ($0, Sibling($0) as Expression) })
		for (k, v) in colGroups {
			rowGroups[k] = v
		}
		
		let values = toDictionary(aggregates, transformer: { ($0.targetColumn, $0.aggregator) })
		let resultDataset = data.aggregate(rowGroups, values: values)
		if columns.isEmpty {
			callback(.success(resultDataset))
		}
		else {
			let pivotedDataset = resultDataset.pivot(columns, vertical: rows, values: OrderedSet(aggregates.map({$0.targetColumn})))
			callback(.success(pivotedDataset))
		}
	}
	
	class func suggest(_ aggregateRows: IndexSet, columns aggregateColumns: Set<Column>, inRaster raster: Raster, fromStep: QBEStep?) -> [QBEStep] {
		if aggregateColumns.isEmpty {
			return []
		}
		
		// Check to see if the selected rows have similar values for other than the relevant columns
		let groupColumnCandidates = Set<Column>(raster.columns).subtracting(aggregateColumns)
		let sameValues = aggregateRows.count > 1 ? raster.commonalitiesOf(aggregateRows, inColumns: groupColumnCandidates) : [:]
		
		// What are our aggregate functions? Select the most likely ones (user can always change)
		let aggregateFunctions = [Function.Sum, Function.Count, Function.Average]
		
		// Generate a suggestion for each type of aggregation we have
		var suggestions: [QBEStep] = []
		for fun in aggregateFunctions {
			let step = QBEPivotStep()
			
			for column in aggregateColumns {
				step.aggregates.append(Aggregation(map: Sibling(column), reduce: fun, targetColumn: column))
			}
			
			for (sameColumn, _) in sameValues {
				step.rows.append(sameColumn)
			}
			
			suggestions.append(step)
		}
		
		return suggestions
	}

	override func related(job: Job, callback: @escaping (Fallible<[QBERelatedStep]>) -> ()) {
		return callback(.success([]))
	}
}
