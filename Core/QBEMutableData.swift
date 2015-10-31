import Foundation

public enum QBEDataMutation {
	/** Truncate: remove all data in the store, but keep the columns (if the store has fixed columns). */
	case Truncate

	/** Drop: remove the data in the store and also remove the store itself. */
	case Drop
}

/** A QBEDataWarehouse corresponds to a location where data can be stored. Each QBEStore is located in a QBEWarehouse. */
public protocol QBEDataWarehouse {
}

/** QBEMutableData represents a mutable data set (i.e., not the result of a query, but actually stored data). It usually
corresponds with a 'table' in a regular database. A mutable data set can support several mutations on itself. */
public protocol QBEMutableData {
	var warehouse: QBEDataWarehouse { get }
	func canPerformMutation(mutation: QBEDataMutation) -> Bool
	func performMutation(mutation: QBEDataMutation, job: QBEJob, callback: (QBEFallible<Void>) -> ())
}