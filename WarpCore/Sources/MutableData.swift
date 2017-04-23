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
	func canPerformMutation(_ mutation: WarehouseMutationKind) -> Bool

	/** Perform the specified mutation on this data warehouse. Where applicable, the result will include a mutable data
	 object of any newly created or modified item. */
	func performMutation(_ mutation: WarehouseMutation, job: Job, callback: @escaping (Fallible<MutableDataset?>) -> ())
}

/** MutableDataset represents a mutable data set (i.e., not the result of a query, but actually stored data). It usually
corresponds with a 'table' in a regular database. A mutable data set can support several mutations on itself. */
public protocol MutableDataset {
	/** The warehouse in which this mutable data set is stored. */
	var warehouse: Warehouse { get }

	/** Returns whether the specified mutation can be performed on this mutable data set. The function indicates support
	of the mutation *at all* rather than whether it would succeed in the current state and on the current data set. The
	function is synchronous and should not make calls to servers to check whether a mutation would succeed.
	
	As a consequence, this function does not guarantee that no errors occur during the actual performance of the mutation
	(user rights, data, et cetera may change between invocations of canPerformMutation and performMutation). This function
	should therefore only perform reasonable and fast checks, such as (1) does the mutable data set support a particular
	mutation at all, (2) are column names suitable for this database, et cetera. */
	func canPerformMutation(_ kind: DatasetMutationKind) -> Bool

	/** Perform the specified mutation on this mutable data set. Note that performMutation will fail if a call to the
	canPerformMutation function with the same mutation would return false. */
	func performMutation(_ mutation: DatasetMutation, job: Job, callback: @escaping (Fallible<Void>) -> ())

	/** Returns a readable data object for the data contained in this mutable data set. */
	func data(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ())

	/** Returns the schema for this mutable data set. */
	func schema(_ job: Job, callback: @escaping (Fallible<Schema>) -> ())
}

/** Proxy for MutableDataset that can be used to create mutable data objects that perform particular operations differently
than the underlying mutable data set, or block certain mutations. */
open class MutableProxyDataset: MutableDataset {
	public let original: MutableDataset

	public init(original: MutableDataset) {
		self.original = original
	}

	open var warehouse: Warehouse {
		return self.original.warehouse
	}

	open func data(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		self.original.data(job, callback: callback)
	}

	open func performMutation(_ mutation: DatasetMutation, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		self.original.performMutation(mutation, job: job, callback: callback)
	}

	open func canPerformMutation(_ kind: DatasetMutationKind) -> Bool {
		return self.original.canPerformMutation(kind)
	}

	open func schema(_ job: Job, callback: @escaping (Fallible<Schema>) -> ()) {
		return self.original.schema(job, callback: callback)
	}
}

/** Proxy mutable data set that blocks edits to certain columns (e.g. those that have been calculated) */
open class MaskedMutableDataset: MutableProxyDataset {
	public let deny: Set<Column>

	public init(original: MutableDataset, deny: Set<Column>) {
		self.deny = deny
		super.init(original: original)
	}

	open override func performMutation(_ mutation: DatasetMutation, job: Job, callback: @escaping (Fallible<Void>) -> ()) {
		switch mutation {
		case .update(key: _, column: let column, old: _, new: _):
			if deny.contains(column) {
				return callback(.failure(String(format: translationForString("The column '%@' is not editable."), column.name)))
			}

		default:
			break;
		}

		super.performMutation(mutation, job: job, callback: callback)
	}
}

/** Mapping that defines how source columns are matched to destination columns in an insert operation to a table that 
already has columns defined. The destination columns are the keys, the source column where that column is filled from is 
the value (or the empty column name, if we must attempt to insert nil) */
public typealias ColumnMapping = [Column: Column]

/** DatasetMutation represents a mutation that can be performed on a mutable dataset (MutableDataset). */
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
	case alter(Schema)

	/** Rename the columns according to the given mapping. Column names must be unique after performing this operation. */
	case rename([Column: Column])

	/** For rows that have the all values indicated in the key dictionary for each key column, change the value in the 
	indicated column to the `new` value if it matches the `old` value. */
	case update(key: [Column: Value], column: Column, old: Value, new: Value)

	/** Removes the rows identified by the given keys. */
	case delete(keys: [[Column: Value]])

	public var kind: DatasetMutationKind {
		switch self {
		case .truncate: return .truncate
		case .drop: return .drop
		case .insert(row: _): return .insert
		case .import(data: _, withMapping: _): return .`import`
		case .alter(_): return .alter
		case .update(key: _, column: _, old: _, new: _): return .update
		case .rename(_): return .rename
		case .delete(keys: _): return .delete
		}
	}
}

public enum DatasetMutationKind {
	case truncate
	case drop
	case insert
	case `import`
	case alter
	case rename
	case update
	case delete
}

/** WarehouseMutation represents a mutation that can be performed on a mutable data warehouse (Warehouse). */
public enum WarehouseMutation {
	/** Create a data set with the given identifier, and fill it with the given data. */
	case create(String, Dataset)

	public var kind: WarehouseMutationKind {
		switch self {
		case .create(_, _): return .create
		}
	}
}

public enum WarehouseMutationKind {
	case create
}
