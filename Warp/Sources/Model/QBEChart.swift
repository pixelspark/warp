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

class QBEChart: QBEConfigurable, NSSecureCoding {
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
		if let t = coder.decodeStringForKey("type"), let tt = QBEChartType(rawValue: t) {
			self.type = tt
		}
		else {
			self.type = .Line
		}

		self.xExpression = coder.decodeObjectOfClass(Expression.self, forKey: "xExpression") ?? Identity()
		self.yExpression = coder.decodeObjectOfClass(Expression.self, forKey: "yExpression") ?? Identity()
		self.sourceTablet = coder.decodeObjectOfClass(QBEChainTablet.self, forKey: "source")
		super.init()
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeString(self.type.rawValue, forKey: "type")
		aCoder.encodeObject(self.xExpression, forKey: "xExpression")
		aCoder.encodeObject(self.yExpression, forKey: "yExpression")
		aCoder.encodeObject(self.sourceTablet, forKey: "source")
	}

	@objc static func supportsSecureCoding() -> Bool {
		return true
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		let opts = [QBEChartType.Bar, QBEChartType.Line, QBEChartType.Radar, QBEChartType.Pie].mapDictionary { return ($0.rawValue, $0.localizedName) }

		let mainSentence = QBESentence(format: "Draw a [#]".localized,
			QBESentenceOptions(options: opts, value: self.type.rawValue, callback: { (newValue) -> () in
				self.type = QBEChartType(rawValue: newValue)!
			})
		)

		let contextCallback = { [weak self] (job: Job, callback: QBESentenceFormula.ContextCallback) -> () in
			if let sourceStep = self?.sourceTablet?.chain.head {
				sourceStep.exampleData(job, maxInputRows: 100, maxOutputRows: 1) { result in
					switch result {
					case .Success(let data):
						data.limit(1).raster(job) { result in
							switch result {
							case .Success(let raster):
								if raster.rowCount == 1 {
									let ctx = QBESentenceFormulaContext(row: raster[0], columns: raster[0].columns)
									return callback(.Success(ctx))
								}

							case .Failure(let e):
								return callback(.Failure(e))
							}
						}

					case .Failure(let e):
						return callback(.Failure(e))
					}
				}
			}
			else {
				return callback(.Failure("No data source for chart".localized))
			}
		}

		switch self.type {
		case .Line, .Radar:
			mainSentence.append(QBESentence(format: "showing [#] horizontally and [#] vertically".localized,
				QBESentenceFormula(expression: self.xExpression, locale: locale, callback: { (newXExpression) -> () in
					self.xExpression = newXExpression
				}, contextCallback: contextCallback),
				QBESentenceFormula(expression: self.yExpression, locale: locale, callback: { (newYExpression) -> () in
					self.yExpression = newYExpression
				}, contextCallback: contextCallback)
			))

		case .Bar, .Pie:
			mainSentence.append(QBESentence(format: "of [#] labeled by [#]".localized,
				QBESentenceFormula(expression: self.yExpression, locale: locale, callback: { (newYExpression) -> () in
					self.yExpression = newYExpression
				}, contextCallback: contextCallback),
				QBESentenceFormula(expression: self.xExpression, locale: locale, callback: { (newXExpression) -> () in
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
		chart = coder.decodeObjectOfClass(QBEChart.self, forKey: "chart") ?? QBEChart(type: .Line, xExpression: Identity(), yExpression: Identity(), sourceTablet: nil)
		if let sourceTablet = coder.decodeObjectOfClass(QBEChainTablet.self, forKey: "source") {
			chart.sourceTablet = sourceTablet
		}
		super.init(coder: coder)
	}

	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(self.chart, forKey: "chart")
	}
}