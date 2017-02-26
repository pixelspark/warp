/* Copyright (c) 2014-2017 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
import Foundation

/** Column represents a column (identifier) in a Dataset dataset. Column names in Dataset are case-insensitive when
compared, but do retain case. There cannot be two or more columns in a Dataset dataset that are equal to each other when
compared case-insensitively. */
public struct Column: ExpressibleByStringLiteral, Hashable, CustomDebugStringConvertible {
	public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
	public typealias UnicodeScalarLiteralType = StringLiteralType

	public let name: String

	public init(_ name: String) {
		self.name = name
	}

	public init(stringLiteral value: StringLiteralType) {
		self.name = value
	}

	public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
		self.name = value
	}

	public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
		self.name = value
	}

	public var hashValue: Int { get {
		return self.name.lowercased().hashValue
		} }

	public var debugDescription: String { get {
		return "Column(\(name))"
		} }

	/** Returns a new, unique name for the next column given a set of existing columns. */
	public static func defaultNameForNewColumn(_ existing: OrderedSet<Column>) -> Column {
		var index = existing.count
		while true {
			let newName = Column.defaultNameForIndex(index)
			if !existing.contains(newName) {
				return newName
			}
			index = index + 1
		}
	}

	/** Return a generated column name for a column at a given index (starting at 0). Note: do not use to generate the
	name of a column that is to be added to an existing set (column names must be unique). Use defaultNameForNewColumn
	to generate a new, unique name. */
	public static func defaultNameForIndex(_ index: Int) -> Column {
		var myIndex = index
		let x = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
		var str: String = ""

		repeat {
			let i = ((myIndex) % 26)
			str = x[i] + str
			myIndex -= i
			myIndex /= 26
		} while myIndex > 0
		return Column(str)
	}

	public func newName(_ accept: (Column) -> Bool) -> Column {
		var i = 0
		repeat {
			let newName = Column("\(self.name)_\(Column.defaultNameForIndex(i).name)")
			let accepted = accept(newName)
			if accepted {
				return newName
			}
			i += 1
		} while true
	}
}

/** Description of a dataset's format (column names primarily). */
public struct Schema: Codeable {
	public let pasteboardName = "nl.pixelspark.Warp.Schema"

	/** The columns present in this data set. To change, call `change`. */
	public private(set) var columns: OrderedSet<Column>

	/** The set of columns using which rows can uniquely be identified in this data set. This set of columns can be
	used to perform updates on specific rows. If the data set does not support or have a primary key, this may be nil.
	In this case, users must choose their own keys (e.g. by asking the user) or use row numbers (e.g. with the .edit
	data mutation if that is supported) when mutating data. */
	public private(set) var identifier: Set<Column>?

	public init(columns: OrderedSet<Column>, identifier: Set<Column>?) {
		self.columns = columns
		self.identifier = identifier
	}

	public init?(coder aDecoder: NSCoder) {
		self.columns = OrderedSet<Column>((aDecoder.decodeObject(forKey: "columns") as? [String] ?? []).map { return Column($0) })
		if aDecoder.containsValue(forKey: "identifier") {
			self.identifier = Set<Column>((aDecoder.decodeObject(forKey: "identifier") as? [String] ?? []).map { return Column($0) })
		}
		else {
			self.identifier = nil
		}
	}

	public func encode(with aCoder: NSCoder) {
		aCoder.encode(self.columns.map { return $0.name }, forKey: "columns")
		aCoder.encode(self.identifier?.map { return $0.name }, forKey: "identifier")
	}

	/** Changes the set of columns in this schema to match the given set of columns. If colunns are used as keys or in
	indexes, those keys or indexes are removed automatically. New keys or indexes are not created automatically. */
	public mutating func change(columns newColumns: OrderedSet<Column>) {
		let removed = self.columns.subtracting(Set(newColumns))
		self.columns = newColumns
		if let id = self.identifier {
			self.identifier = id.subtracting(removed)
		}
	}

	/** Change the set of columns used as identifier in this schema. All columns listed in the identifier must exist
	(e.g. they must be in the `columns` set). If this is not the case, the method will cause a fatal error. */
	public mutating func change(identifier newIdentifier: Set<Column>?) {
		if let ni = newIdentifier {
			precondition(ni.subtracting(self.columns).isEmpty, "Cannot set identifier, it contains columns that do not exist")
			self.identifier = ni
		}
		else {
			self.identifier = nil
		}
	}

	public mutating func remove(columns: Set<Column>) {
		self.change(columns: self.columns.subtracting(columns))
	}
}
