import Foundation
import WarpCore

class QBEMap: QBEConfigurable, NSSecureCoding {
	var latitudeExpression: Expression
	var longitudeExpression: Expression
	var titleExpression: Expression

	init(latitudeExpression: Expression, longitudeExpression: Expression, titleExpression: Expression) {
		self.latitudeExpression = latitudeExpression
		self.longitudeExpression = longitudeExpression
		self.titleExpression = titleExpression
		super.init()
	}

	required init?(coder: NSCoder) {
		self.latitudeExpression = coder.decodeObjectOfClass(Expression.self, forKey: "latitudeExpression") ?? Identity()
		self.longitudeExpression = coder.decodeObjectOfClass(Expression.self, forKey: "longitudeExpression") ?? Identity()
		self.titleExpression = coder.decodeObjectOfClass(Expression.self, forKey: "titleExpression") ?? Identity()
		super.init()
	}

	func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(self.latitudeExpression, forKey: "latitudeExpression")
		aCoder.encodeObject(self.longitudeExpression, forKey: "longitudeExpression")
		aCoder.encodeObject(self.titleExpression, forKey: "titleExpression")
	}

	@objc static func supportsSecureCoding() -> Bool {
		return true
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Show locations at latitude [#] and longitude [#] with label [#]".localized,
			QBESentenceFormula(expression: self.latitudeExpression, locale: locale, callback: { (newLatitudeExpression) -> () in
				self.latitudeExpression = newLatitudeExpression
			}),
			QBESentenceFormula(expression: self.longitudeExpression, locale: locale, callback: { (newLongitudeExpression) -> () in
				self.longitudeExpression = newLongitudeExpression
			}),
			QBESentenceFormula(expression: self.titleExpression, locale: locale, callback: { (newTitleExpression) -> () in
				self.titleExpression = newTitleExpression
			})
		)
	}
}

class QBEMapTablet: QBETablet {
	var sourceTablet: QBEChainTablet? = nil
	var map: QBEMap

	private static let interestingColumnPairs = [
		("latitude", "longitude"),
		("lat", "long"),
		("lat", "lng"),
		("lt", "ln"),
		("lat", "lon"),
		("hoogtegraad", "breedtegraad")
	]

	init(source: QBEChainTablet, latitudeExpression: Expression, longitudeExpression: Expression, titleExpression: Expression) {
		self.sourceTablet = source
		self.map = QBEMap(latitudeExpression: latitudeExpression, longitudeExpression: longitudeExpression, titleExpression: titleExpression)
		super.init()
	}

	init(source: QBEChainTablet, columns: [Column]) {
		// Find interesting columns to use as coordinates
		self.sourceTablet = source

		for (latName, lonName) in QBEMapTablet.interestingColumnPairs {
			if columns.contains(Column(latName)) && columns.contains(Column(lonName)) {
				self.map = QBEMap(
					latitudeExpression: Sibling(Column(latName)),
					longitudeExpression: Sibling(Column(lonName)),
					titleExpression: Sibling(columns.first!)
				)

				super.init()
				return
			}
		}

		if columns.count >= 2 {
			self.map = QBEMap(latitudeExpression: Sibling(columns.first!), longitudeExpression: Sibling(columns.dropFirst().first!), titleExpression: Literal(Value("Item".localized)))
		}
		else {
			self.map = QBEMap(latitudeExpression: Identity(), longitudeExpression: Identity(), titleExpression: Literal(Value("Item".localized)))
		}

		super.init()
	}

	override var arrows: [QBETabletArrow] {
		if let h = self.sourceTablet?.chain.head {
			return [QBETabletArrow(from: self.sourceTablet!, to: self, fromStep: h)]
		}
		return []
	}

	required init?(coder: NSCoder) {
		map = coder.decodeObjectOfClass(QBEMap.self, forKey: "map") ?? QBEMap(latitudeExpression: Identity(), longitudeExpression: Identity(), titleExpression: Identity())
		sourceTablet = coder.decodeObjectOfClass(QBEChainTablet.self, forKey: "source")
		super.init(coder: coder)
	}

	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(self.map, forKey: "map")
		aCoder.encodeObject(self.sourceTablet, forKey: "source")
	}
}