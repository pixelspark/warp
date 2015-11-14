import Foundation

/** A QBEDataWarehouse corresponds to a location where data can be stored. Each QBEMutableData is located in a QBEWarehouse. */
public protocol QBEDataWarehouse {
	/** Whether tables in this database require that column names are known in advance. NoSQL databases should set this
	to false (and accept any Insert mutation on their mutable data) whereas relational databases will set this to true. */
	var hasFixedColumns: Bool { get }
	
	func canPerformMutation(mutation: QBEWarehouseMutation) -> Bool
	func performMutation(mutation: QBEWarehouseMutation, job: QBEJob, callback: (QBEFallible<QBEMutableData?>) -> ())
}

/** QBEMutableData represents a mutable data set (i.e., not the result of a query, but actually stored data). It usually
corresponds with a 'table' in a regular database. A mutable data set can support several mutations on itself. */
public protocol QBEMutableData {
	var warehouse: QBEDataWarehouse { get }
	func canPerformMutation(mutation: QBEDataMutation) -> Bool
	func performMutation(mutation: QBEDataMutation, job: QBEJob, callback: (QBEFallible<Void>) -> ())
}

public enum QBEDataMutation {
	/** Truncate: remove all data in the store, but keep the columns (if the store has fixed columns). */
	case Truncate

	/** Drop: remove the data in the store and also remove the store itself. */
	case Drop

	/** Insert the rows from the source data set in this table. The second argument specifies a mapping table, in which
	the keys are columns in this table, and the values are the names of the corresponding columns in the source data. 
	Columns for which a mapping is missing are filled with NULL. */
	case Insert(QBEData, [QBEColumn: QBEColumn])
}

public enum QBEWarehouseMutation {
	/** Create a data set with the given identifier, and fill it with the given data. */
	case Create(String, QBEData)
}