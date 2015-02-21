import Foundation

class QBEResultViewController: NSViewController {
	var locale: QBELocale!
	var raster: QBERaster!

	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "tableGrid" {
			if let dv = segue.destinationController as? QBEDataViewController {
				dv.raster = raster
				dv.locale = locale
			}
		}
	}
}