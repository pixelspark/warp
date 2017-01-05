import UIKit
import WarpCore

protocol QBEDataViewControllerDelegate: class {
	func dataView(_ controller: QBEDataViewController, filter column: Column, for value: Value)
}

class QBEDataViewController: UIViewController, QBERasterViewControllerDelegate {
	weak var delegate: QBEDataViewControllerDelegate? = nil

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

	func rasterView(_ controller: QBERasterViewController, filter column: Column, for value: Value) {
		self.delegate?.dataView(self, filter: column, for: value)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "raster", let dest = segue.destination as? QBERasterViewController {
			self.rasterViewController = dest
			self.rasterViewController.delegate = self
			self.presentData()
		}
	}
}
