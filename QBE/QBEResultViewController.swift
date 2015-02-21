import Foundation

class QBEResultViewController: NSViewController {
	var locale: QBELocale!
	
	var raster: QBERaster! { didSet {
		dataView?.raster = raster
	} }
	
	private var dataView: QBEDataViewController?

	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "tableGrid" {
			if let dv = segue.destinationController as? QBEDataViewController {
				dataView = dv
				dv.calculating = (raster==nil)
				dv.raster = raster
				dv.locale = locale
			}
		}
	}
}