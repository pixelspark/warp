/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit
import WarpCore

protocol QBEDataViewControllerDelegate: class {
	func dataView(_ controller: QBEDataViewController, filter column: Column, for value: Value)
	func dataView(_ controller: QBEDataViewController, sort column: Column)
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

	func rasterView(_ controller: QBERasterViewController, sort column: Column) {
		self.delegate?.dataView(self, sort:column)
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
