import Foundation

class QBEFileWriter: NSObject {
	let locale: QBELocale
	
	required init(locale: QBELocale, title: String? = nil) {
		self.locale = locale
	}
	
	func writeData(data: QBEData, toFile: NSURL, job: QBEJob?, callback: () -> ()) {
		fatalError("Must be subclassed")
	}
}