import Foundation

/** A QBEDataWarehouse corresponds to a location where data can be stored. Each QBEMutableData is located in a QBEWarehouse. */
public protocol QBEDataWarehouse {
	/** Whether tables in this database require that column names are known in advance. NoSQL databases should set this
	to false (and accept any Insert mutation on their mutable data) whereas relational databases will set this to true. */
	var hasFixedColumns: Bool { get }

	/** Whether this data source has names for tables. */
	var hasNamedTables: Bool { get }

	/** Returns whether the specified mutation can be performed on this warehouse. Note that this function does
	not guarantee that no errors occur during the actual performance of the mutation (user rights, data, et cetera may
	change between invocations of canPerformMutation and performMutation). This function should therefore only perform
	reasonable checks, such as (1) does the warehouse support a particular mutation at all, (2) are column names
	suitable for this warehouse, et cetera. */
	func canPerformMutation(mutation: QBEWarehouseMutation) -> Bool

	/** Perform the specified mutation on this data warehouse. Where applicable, the result will include a mutable data
	 object of any newly created or modified item. */
	func performMutation(mutation: QBEWarehouseMutation, job: QBEJob, callback: (QBEFallible<QBEMutableData?>) -> ())
}

/** QBEMutableData represents a mutable data set (i.e., not the result of a query, but actually stored data). It usually
corresponds with a 'table' in a regular database. A mutable data set can support several mutations on itself. */
public protocol QBEMutableData {
	/** The warehouse in which this mutable data set is stored. */
	var warehouse: QBEDataWarehouse { get }

	/** This function fetches the set of columns using which rows can uniquely be identified. This set of columns can be
	used to perform updates on specific rows */
	func identifier(job: QBEJob, callback: (QBEFallible<Set<QBEColumn>>) -> ())

	/** Returns whether the specified mutation can be performed on this mutable data set. The function indicates support
	of the mutation *at all* rather than whether it would succeed in the current state and on the current data set. The
	function is synchronous and should not make calls to servers to check whether a mutation would succeed.
	
	As a consequence, this function does not guarantee that no errors occur during the actual performance of the mutation
	(user rights, data, et cetera may change between invocations of canPerformMutation and performMutation). This function
	should therefore only perform reasonable and fast checks, such as (1) does the mutable data set support a particular
	mutation at all, (2) are column names suitable for this database, et cetera. */
	func canPerformMutation(mutation: QBEDataMutation) -> Bool

	/** Perform the specified mutation on this mutable data set. Note that performMutation will fail if a call to the
	canPerformMutation function with the same mutation would return false. */
	func performMutation(mutation: QBEDataMutation, job: QBEJob, callback: (QBEFallible<Void>) -> ())

	/** Returns a readable data object for the data contained in this mutable data set. */
	func data(job: QBEJob, callback: (QBEFallible<QBEData>) -> ())
}

/** Mapping that defines how source columns are matched to destination columns in an insert operation to a table that 
already has columns defined. The destination columns are the keys, the source column where that column is filled from is 
the value (or the empty column name, if we must attempt to insert nil) */
public typealias QBEColumnMapping = [QBEColumn: QBEColumn]

/** Description of a dataset's format (column names primarily). */
public class QBEDataDefinition: NSObject, NSCoding {
	public static let pasteboardName = "nl.pixelspark.Warp.QBEDataDefinition"

	public var columnNames: [QBEColumn]

	public init(columnNames: [QBEColumn]) {
		self.columnNames = columnNames
	}

	public required init?(coder aDecoder: NSCoder) {
		self.columnNames = (aDecoder.decodeObjectForKey("columns") as? [String] ?? []).map { return QBEColumn($0) }
	}

	public func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(self.columnNames.map { return $0.name }, forKey: "columns")
	}
}

public enum QBEDataMutation {
	/** Truncate: remove all data in the store, but keep the columns (if the store has fixed columns). */
	case Truncate

	/** Drop: remove the data in the store and also remove the store itself. */
	case Drop

	/** Insert the rows from the source data set in this table. The second argument specifies a mapping table, in which
	the keys are columns in this table, and the values are the names of the corresponding columns in the source data. 
	Columns for which a mapping is missing are filled with NULL. */
	case Insert(QBEData, QBEColumnMapping)

	/** Alter the table so that it has columns as listed. Existing columns must be re-used and stay intact. If the table
	does not exist, create the table. */
	case Alter(QBEDataDefinition)

	/** For rows that have the all values indicated in the key dictionary for each key column, change the value in the 
	indicated column to the `new` value if it matches the `old` value. */
	case Update(key: [QBEColumn: QBEValue], column: QBEColumn, old: QBEValue, new: QBEValue)
}

public enum QBEWarehouseMutation {
	/** Create a data set with the given identifier, and fill it with the given data. */
	case Create(String, QBEData)
}