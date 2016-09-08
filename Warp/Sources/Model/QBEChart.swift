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

enum QBEChartType: String {
	case Line = "line"
	case Bar = "bar"
	case Radar = "radar"
	case Pie = "pie"

	var localizedName: String {
		switch self {
		case .Line: return "line chart".localized
		case .Bar: return "bar chart".localized
		case .Radar: return "radar plot".localized
		case .Pie: return "pie chart".localized
		}
	}
}

class QBEChart: NSObject, QBEConfigurable, NSSecureCoding {
	var sourceTablet: QBEChainTablet? = nil
	var type: QBEChartType
	var xExpression: Expression
	var yExpression: Expression

	init(type: QBEChartType, xExpression: Expression, yExpression: Expression, sourceTablet: QBEChainTablet?) {
		self.type = type
		self.xExpression = xExpression
		self.yExpression = yExpression
		self.sourceTablet = sourceTablet
		super.init()
	}

	required init?(coder: NSCoder) {
		if let t = coder.decodeString(forKey:"type"), let tt = QBEChartType(rawValue: t) {
			self.type = tt
		}
		else {
			self.type = .Line
		}

		self.xExpression = coder.decodeObject(of: Expression.self, forKey: "xExpression") ?? Identity()
		self.yExpression = coder.decodeObject(of: Expression.self, forKey: "yExpression") ?? Identity()
		self.sourceTablet = coder.decodeObject(of: QBEChainTablet.self, forKey: "source")
		super.init()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encodeString(self.type.rawValue, forKey: "type")
		aCoder.encode(self.xExpression, forKey: "xExpression")
		aCoder.encode(self.yExpression, forKey: "yExpression")
		aCoder.encode(self.sourceTablet, forKey: "source")
	}

	static var supportsSecureCoding: Bool = true

	func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		let opts = [QBEChartType.Bar, QBEChartType.Line, QBEChartType.Radar, QBEChartType.Pie].mapDictionary { return ($0.rawValue, $0.localizedName) }

		let mainSentence = QBESentence(format: "Draw a [#]".localized,
			QBESentenceOptionsToken(options: opts, value: self.type.rawValue, callback: { (newValue) -> () in
				self.type = QBEChartType(rawValue: newValue)!
			})
		)

		let contextCallback = { [weak self] (job: Job, callback: @escaping QBESentenceFormulaToken.ContextCallback) -> () in
			if let sourceStep = self?.sourceTablet?.chain.head {
				sourceStep.exampleDataset(job, maxInputRows: 100, maxOutputRows: 1) { result in
					switch result {
					case .success(let data):
						data.limit(1).raster(job) { result in
							switch result {
							case .success(let raster):
								if raster.rowCount == 1 {
									let ctx = QBESentenceFormulaTokenContext(row: raster[0], columns: raster[0].columns)
									return callback(.success(ctx))
								}

							case .failure(let e):
								return callback(.failure(e))
							}
						}

					case .failure(let e):
						return callback(.failure(e))
					}
				}
			}
			else {
				return callback(.failure("No data source for chart".localized))
			}
		}

		switch self.type {
		case .Line, .Radar:
			mainSentence.append(QBESentence(format: "showing [#] horizontally and [#] vertically".localized,
				QBESentenceFormulaToken(expression: self.xExpression, locale: locale, callback: { (newXExpression) -> () in
					self.xExpression = newXExpression
				}, contextCallback: contextCallback),
				QBESentenceFormulaToken(expression: self.yExpression, locale: locale, callback: { (newYExpression) -> () in
					self.yExpression = newYExpression
				}, contextCallback: contextCallback)
			))

		case .Bar, .Pie:
			mainSentence.append(QBESentence(format: "of [#] labeled by [#]".localized,
				QBESentenceFormulaToken(expression: self.yExpression, locale: locale, callback: { (newYExpression) -> () in
					self.yExpression = newYExpression
				}, contextCallback: contextCallback),
				QBESentenceFormulaToken(expression: self.xExpression, locale: locale, callback: { (newXExpression) -> () in
					self.xExpression = newXExpression
				}, contextCallback: contextCallback)
			))
		}

		return mainSentence
	}
}

class QBEChartTablet: QBETablet {
	var chart: QBEChart

	init(source: QBEChainTablet, type: QBEChartType, xExpression: Expression, yExpression: Expression) {
		self.chart = QBEChart(type: type, xExpression: xExpression, yExpression: yExpression, sourceTablet: source)
		super.init()
	}

	override var arrows: [QBETabletArrow] {
		if let h = self.chart.sourceTablet?.chain.head {
			return [QBETabletArrow(from: self.chart.sourceTablet!, to: self, fromStep: h)]
		}
		return []
	}

	required init?(coder: NSCoder) {
		chart = coder.decodeObject(of: QBEChart.self, forKey: "chart") ?? QBEChart(type: .Line, xExpression: Identity(), yExpression: Identity(), sourceTablet: nil)
		if let sourceTablet = coder.decodeObject(of: QBEChainTablet.self, forKey: "source") {
			chart.sourceTablet = sourceTablet
		}
		super.init(coder: coder)
	}

	override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(self.chart, forKey: "chart")
	}
}
