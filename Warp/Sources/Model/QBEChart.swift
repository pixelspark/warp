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
	var type: QBEChartType
	var xExpression: Expression
	var yExpression: Expression

	init(type: QBEChartType, xExpression: Expression, yExpression: Expression) {
		self.type = type
		self.xExpression = xExpression
		self.yExpression = yExpression
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
		super.init()
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeString(self.type.rawValue, forKey: "type")
		aCoder.encodeObject(self.xExpression, forKey: "xExpression")
		aCoder.encodeObject(self.yExpression, forKey: "yExpression")
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

		switch self.type {
		case .Line, .Radar:
			mainSentence.append(QBESentence(format: "showing [#] horizontally and [#] vertically".localized,
				QBESentenceFormula(expression: self.xExpression, locale: locale, callback: { (newXExpression) -> () in
					self.xExpression = newXExpression
				}),
				QBESentenceFormula(expression: self.yExpression, locale: locale, callback: { (newYExpression) -> () in
					self.yExpression = newYExpression
				})
			))

		case .Bar, .Pie:
			mainSentence.append(QBESentence(format: "of [#] labeled by [#]".localized,
				QBESentenceFormula(expression: self.yExpression, locale: locale, callback: { (newYExpression) -> () in
					self.yExpression = newYExpression
				}),
				QBESentenceFormula(expression: self.xExpression, locale: locale, callback: { (newXExpression) -> () in
					self.xExpression = newXExpression
				})
			))
		}

		return mainSentence
	}
}

class QBEChartTablet: QBETablet {
	var sourceTablet: QBEChainTablet? = nil
	var chart: QBEChart

	init(source: QBEChainTablet, type: QBEChartType, xExpression: Expression, yExpression: Expression) {
		self.sourceTablet = source
		self.chart = QBEChart(type: type, xExpression: xExpression, yExpression: yExpression)
		super.init()
	}

	override var arrows: [QBETabletArrow] {
		if let h = self.sourceTablet?.chain.head {
			return [QBETabletArrow(from: self, to: self.sourceTablet!, fromStep: h)]
		}
		return []
	}

	required init?(coder: NSCoder) {
		chart = coder.decodeObjectOfClass(QBEChart.self, forKey: "chart") ?? QBEChart(type: .Line, xExpression: Identity(), yExpression: Identity())
		sourceTablet = coder.decodeObjectOfClass(QBEChainTablet.self, forKey: "source")
		super.init(coder: coder)
	}

	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(self.chart, forKey: "chart")
		aCoder.encodeObject(self.sourceTablet, forKey: "source")
	}
}