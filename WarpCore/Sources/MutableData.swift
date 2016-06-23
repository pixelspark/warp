import Foundation

/** A Warehouse corresponds to a location where data can be stored. Each MutableDataset is located in a QBEWarehouse. */
public protocol Warehouse {
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
	func canPerformMutation(_ mutation: WarehouseMutation) -> Bool

	/** Perform the specified mutation on this data warehouse. Where applicable, the result will include a mutable data
	 object of any newly created or modified item. */
	func performMutation(_ mutation: WarehouseMutation, job: Job, callback: (Fallible<MutableDataset?>) -> ())
}

/** MutableDataset represents a mutable data set (i.e., not the result of a query, but actually stored data). It usually
corresponds with a 'table' in a regular database. A mutable data set can support several mutations on itself. */
public protocol MutableDataset {
	/** The warehouse in which this mutable data set is stored. */
	var warehouse: Warehouse { get }

	/** This function fetches the set of columns using which rows can uniquely be identified. This set of columns can be
	used to perform updates on specific rows. If the mutable data does not support or have a primary key, it may return
	nil. In this case, the user of MutableDataset must choose its own keys (e.g. by asking the user) or use row numbers
	(e.g. with the .edit data mutation if that is supported). */
	func identifier(_ job: Job, callback: (Fallible<Set<Column>?>) -> ())

	/** Returns whether the specified mutation can be performed on this mutable data set. The function indicates support
	of the mutation *at all* rather than whether it would succeed in the current state and on the current data set. The
	function is synchronous and should not make calls to servers to check whether a mutation would succeed.
	
	As a consequence, this function does not guarantee that no errors occur during the actual performance of the mutation
	(user rights, data, et cetera may change between invocations of canPerformMutation and performMutation). This function
	should therefore only perform reasonable and fast checks, such as (1) does the mutable data set support a particular
	mutation at all, (2) are column names suitable for this database, et cetera. */
	func canPerformMutation(_ mutation: DatasetMutation) -> Bool

	/** Perform the specified mutation on this mutable data set. Note that performMutation will fail if a call to the
	canPerformMutation function with the same mutation would return false. */
	func performMutation(_ mutation: DatasetMutation, job: Job, callback: (Fallible<Void>) -> ())

	/** Returns a readable data object for the data contained in this mutable data set. */
	func data(_ job: Job, callback: (Fallible<Dataset>) -> ())
}

/** Proxy for MutableDataset that can be used to create mutable data objects that perform particular operations differently
than the underlying mutable data set, or block certain mutations. */
public class MutableProxyDataset: MutableDataset {
	public let original: MutableDataset

	public init(original: MutableDataset) {
		self.original = original
	}

	public var warehouse: Warehouse {
		return self.original.warehouse
	}

	public func data(_ job: Job, callback: (Fallible<Dataset>) -> ()) {
		self.original.data(job, callback: callback)
	}

	public func performMutation(_ mutation: DatasetMutation, job: Job, callback: (Fallible<Void>) -> ()) {
		self.original.performMutation(mutation, job: job, callback: callback)
	}

	public func canPerformMutation(_ mutation: DatasetMutation) -> Bool {
		return self.original.canPerformMutation(mutation)
	}

	public func identifier(_ job: Job, callback: (Fallible<Set<Column>?>) -> ()) {
		return self.original.identifier(job, callback: callback)
	}
}

public extension MutableDataset {
	public func columns(_ job: Job, callback: (Fallible<[Column]>) -> ()) {
		self.data(job) { result in
			switch result {
			case .success(let data):
				data.columns(job, callback: callback)

			case .failure(let e):
				callback(.failure(e))
			}
		}
	}
}

/** Mapping that defines how source columns are matched to destination columns in an insert operation to a table that 
already has columns defined. The destination columns are the keys, the source column where that column is filled from is 
the value (or the empty column name, if we must attempt to insert nil) */
public typealias ColumnMapping = [Column: Column]

/** Description of a dataset's format (column names primarily). */
public class DatasetDefinition: NSObject, NSCoding {
	public static let pasteboardName = "nl.pixelspark.Warp.DatasetDefinition"

	public var columns: [Column]

	public init(columns: [Column]) {
		assert(Set(columns).count == columns.count, "Column names must be unique")
		self.columns = columns
	}

	public required init?(coder aDecoder: NSCoder) {
		self.columns = (aDecoder.decodeObject(forKey: "columns") as? [String] ?? []).map { return Column($0) }
	}

	public func encode(with aCoder: NSCoder) {
		aCoder.encode(self.columns.map { return $0.name }, forKey: "columns")
	}
}

public enum DatasetMutation {
	/** Truncate: remove all data in the store, but keep the columns (if the store has fixed columns). */
	case truncate

	/** Drop: remove the data in the store and also remove the store itself. */
	case drop

	/** Insert the given row in this dataset. If the row to be inserted contains a column that does not exists in the 
	target data set, it is discarded. If the row to be inserted does not have a column that is required by the target,
	it is filled with .empty. If the target data set does not have required columns, any columns that are omitted
	are simply not present in the record added. */
	case insert(row: Row)

	/** Insert the rows from the source data set in this table. The second argument specifies a mapping table, in which
	the keys are columns in this table, and the values are the names of the corresponding columns in the source data. 
	Columns for which a mapping is missing are filled with NULL. */
	case `import`(data: Dataset, withMapping: ColumnMapping)

	/** Alter the table so that it has columns as listed. Existing columns must be re-used and stay intact. If the table
	does not exist, create the table. */
	case alter(DatasetDefinition)

	/** Rename the columns according to the given mapping. Column names must be unique after performing this operation. */
	case rename([Column: Column])

	/** For rows that have the all values indicated in the key dictionary for each key column, change the value in the 
	indicated column to the `new` value if it matches the `old` value. */
	case update(key: [Column: Value], column: Column, old: Value, new: Value)

	/** Set the value in the indicated `column` and the `row` (by index) to the `new` value if the current value matches
	the `old` value. */
	case edit(row: Int, column: Column, old: Value, new: Value)

	/** Removes the row at the given indices. */
	case remove(rows: [Int])

	/** Removes the rows identified by the given keys. */
	case delete(keys: [[Column: Value]])
}

public enum WarehouseMutation {
	/** Create a data set with the given identifier, and fill it with the given data. */
	case create(String, Dataset)
}
