import UIKit
import WarpCore

class QBEDataViewController: UIViewController {
	var data: Dataset? = nil { didSet {
		self.presentData()
	} }

	private var rasterViewController: QBERasterViewController! = nil

	private func presentData() {
		let job = Job(.userInitiated)
		self.rasterViewController.state = .loading

		data?.raster(job, callback: { (result) in
			asyncMain {
				switch result {
				case .success(let raster):
					self.rasterViewController.state = .raster(raster)

				case .failure(let e):
					self.rasterViewController.state = .error(e)
				}

			}
		})
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "raster", let dest = segue.destination as? QBERasterViewController {
			self.rasterViewController = dest
			self.presentData()
		}
	}
}
