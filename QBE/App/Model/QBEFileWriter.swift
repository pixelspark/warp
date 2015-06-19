import Foundation

protocol QBEFileWriter {
	init(locale: QBELocale, title: String?)
	func writeData(data: QBEData, toFile: NSURL, job: QBEJob, callback: (QBEFallible<Void>) -> ())
}