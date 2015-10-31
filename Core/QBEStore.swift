import Foundation

public enum QBEMutation {
	/** Truncate: remove all data in the store, but keep the columns (if the store has fixed columns). */
	case Truncate

	/** Drop: remove the data in the store and also remove the store itself. */
	case Drop
}

/** A QBEStore represents a mutable set of original data (i.e., not the result of a query, but actually stored data). A
store can support several mutations on itself. */
public protocol QBEStore {
	func canPerformMutation(mutation: QBEMutation) -> Bool
	func performMutation(mutation: QBEMutation, job: QBEJob, callback: (QBEFallible<Void>) -> ())
}