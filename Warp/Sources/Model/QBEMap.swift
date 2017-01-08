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

class QBEMap: NSObject, QBEConfigurable, NSSecureCoding {
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
		self.latitudeExpression = coder.decodeObject(of: Expression.self, forKey: "latitudeExpression") ?? Identity()
		self.longitudeExpression = coder.decodeObject(of: Expression.self, forKey: "longitudeExpression") ?? Identity()
		self.titleExpression = coder.decodeObject(of: Expression.self, forKey: "titleExpression") ?? Identity()
		super.init()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(self.latitudeExpression, forKey: "latitudeExpression")
		aCoder.encode(self.longitudeExpression, forKey: "longitudeExpression")
		aCoder.encode(self.titleExpression, forKey: "titleExpression")
	}

	static var supportsSecureCoding: Bool = true

	func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Show locations at latitude [#] and longitude [#] with label [#]".localized,
			QBESentenceFormulaToken(expression: self.latitudeExpression, locale: locale, callback: { (newLatitudeExpression) -> () in
				self.latitudeExpression = newLatitudeExpression
			}),
			QBESentenceFormulaToken(expression: self.longitudeExpression, locale: locale, callback: { (newLongitudeExpression) -> () in
				self.longitudeExpression = newLongitudeExpression
			}),
			QBESentenceFormulaToken(expression: self.titleExpression, locale: locale, callback: { (newTitleExpression) -> () in
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
		("hoogtegraad", "breedtegraad"),
		("lat", "long"),
		("lat", "lon"),
		("lat", "lng"),
		("lt", "lng"),
		("lt", "ln"),
		("la", "lo"),
		("φ", "λ")
	]

	init(source: QBEChainTablet, latitudeExpression: Expression, longitudeExpression: Expression, titleExpression: Expression) {
		self.sourceTablet = source
		self.map = QBEMap(latitudeExpression: latitudeExpression, longitudeExpression: longitudeExpression, titleExpression: titleExpression)
		super.init()
	}

	init(source: QBEChainTablet, columns: OrderedSet<Column>) {
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
		map = coder.decodeObject(of: QBEMap.self, forKey: "map") ?? QBEMap(latitudeExpression: Identity(), longitudeExpression: Identity(), titleExpression: Identity())
		sourceTablet = coder.decodeObject(of: QBEChainTablet.self, forKey: "source")
		super.init(coder: coder)
	}

	override func encode(with aCoder: NSCoder) {
		super.encode(with: aCoder)
		aCoder.encode(self.map, forKey: "map")
		aCoder.encode(self.sourceTablet, forKey: "source")
	}
}
