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

class QBERankStep: QBEStep {
	var orders: [Order] = []
	var targetColumn: Column
	var aggregator: Aggregator

	required init() {
		self.targetColumn = Column("Rank".localized)
		aggregator = Aggregator(map: Identity(), reduce: .countAll)
		super.init()
	}

	init(previous: QBEStep?, orders: [Order] = [], target: Column, aggregator: Aggregator) {
		self.orders = orders
		self.targetColumn = target
		self.aggregator = aggregator
		super.init(previous: previous)
	}

	required init(coder aDecoder: NSCoder) {
		self.orders = (aDecoder.decodeObject(forKey: "orders") as? [Order]) ?? []
		self.targetColumn = Column(aDecoder.decodeString(forKey: "target") ?? "Rank".localized)
		if let s = aDecoder.decodeObject(of: [Coded<Aggregator>.self], forKey: "aggregator") as? Coded<Aggregator> {
			self.aggregator = s.subject
		}
		else {
			self.aggregator = Aggregator(map: Identity(), reduce: .countAll)
		}
		super.init(coder: aDecoder)
	}

	override func encode(with coder: NSCoder) {
		coder.encode(self.orders, forKey: "orders")
		coder.encode(self.targetColumn.name, forKey: "target")
		coder.encode(Coded(self.aggregator), forKey: "aggregator")
		super.encode(with: coder)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		// Order settings
		let orderSentence: QBESentence
		if orders.isEmpty {
			orderSentence = QBESentence(format: NSLocalizedString("[#]", comment: ""),
				QBESentenceFormulaToken(expression: Literal(Value.bool(false)), locale: locale, callback: { [weak self] (newExpression) -> () in
					self?.orders.append(Order(expression: newExpression, ascending: true, numeric: true))
				})
			)
		}
		else if orders.count == 1 {
			let order = orders[0]
			orderSentence = QBESentence(format: NSLocalizedString("[#][#][#]", comment: ""),
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
			orderSentence = QBESentence([
				QBESentenceLabelToken(String(format: NSLocalizedString("%d criteria", comment: ""), orders.count))
				])
		}

		// Order by token
		let isOrdered = !self.orders.isEmpty
		let orderModeToken = QBESentenceOptionsToken(options: ["ordered": "ordered by".localized, "unordered": "in current order".localized], value: isOrdered ? "ordered": "unordered") { (newMode) in
			if newMode == "ordered" {
				self.orders = [Order(expression: Sibling(Column("Column".localized)), ascending: true, numeric: true)]
			}
			else {
				self.orders = []
			}
		}

		let orderedBySentence: QBESentence
		if isOrdered {
			orderedBySentence = QBESentence(format: "[#] [#]", orderModeToken, orderSentence)
		}
		else {
			orderedBySentence = QBESentence(format: "[#]", orderModeToken)
		}

		let isSimpleRank = self.aggregator.map == Identity() && self.aggregator.reduce == .countAll
		let modeToken = QBESentenceOptionsToken(options: ["rank": "rank".localized, "running": "running".localized], value: isSimpleRank ? "rank": "running") { (newMode) in
			if newMode == "rank" {
				self.aggregator.map = Identity()
				self.aggregator.reduce = .countAll
			}
			else {
				if let expr = self.orders.first?.expression {
					self.aggregator.map = expr
				}
				else {
					self.aggregator.map = Literal(.int(1))
				}
				self.aggregator.reduce = .sum
			}
		}

		let targetField = QBESentenceTextToken(value: self.targetColumn.name) { (newName) -> (Bool) in
			if newName.isEmpty {
				return false
			}
			self.targetColumn = Column(newName)
			return true
		}

		if isSimpleRank {
			return QBESentence(format: "Place [#] of rows ([#]) in [#]".localized, modeToken, orderedBySentence, targetField)
		}
		else {
			let mapToken = QBESentenceFormulaToken(expression: self.aggregator.map, locale: locale, callback: { (newMap) in
				self.aggregator.map = newMap
			})

			let reducerTypes = Function.allReducingFunctions.mapDictionary { fn in
				return (fn.rawValue, fn.localizedName)
			}

			let reducerToken = QBESentenceOptionsToken(options: reducerTypes, value: self.aggregator.reduce.rawValue, callback: { (newReduce) in
				self.aggregator.reduce = Function(rawValue: newReduce) ?? self.aggregator.reduce
			})

			return QBESentence(format: "Place [#] [#] of [#] (with rows [#]) in [#]".localized, modeToken, reducerToken, mapToken, orderedBySentence, targetField)
		}
	}

	override func mergeWith(_ prior: QBEStep) -> QBEStepMerge {
		// TODO: implement merging with other rank and sort steps.
		return .impossible
	}

	override func apply(_ data: Dataset, job: Job?, callback: @escaping (Fallible<Dataset>) -> ()) {
		callback(.success(data.rank([self.targetColumn: self.aggregator], by: self.orders)))
	}

	override func mutableDataset(_ job: Job, callback: @escaping (Fallible<MutableDataset>) -> ()) {
		self.previous?.mutableDataset(job) { result in
			switch result {
			case .success(let pmd):
				return callback(.success(MaskedMutableDataset(original: pmd, deny: Set<Column>([self.targetColumn]))))

			case .failure(let e):
				return callback(.failure(e))
			}
		}
	}
}
