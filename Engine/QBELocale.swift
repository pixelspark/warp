import Foundation

protocol QBELocale: NSObjectProtocol {
	var decimalSeparator: String { get }
	var constants: [String:QBEValue] { get }
}

class QBEDefaultLocale: NSObject, QBELocale {
	let decimalSeparator = "."
	
	let constants = [
		"TRUE": QBEValue(true),
		"FALSE": QBEValue(false)
	]
}