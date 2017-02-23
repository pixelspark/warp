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

class QBEDataViewController: UIViewController, QBERasterViewControllerDelegate, QBEEditViewControllerDelegate {
	weak var delegate: QBEDataViewControllerDelegate? = nil

	var data: Dataset? = nil { didSet {
		self.presentData()
	} }

	var mutableData: MutableDataset? = nil

	private var rasterViewController: QBERasterViewController! = nil

	private func presentData(completion: (() -> ())? = nil) {
		let job = Job(.userInitiated)
		self.rasterViewController.state = .loading

		data?.raster(job, callback: { (result) in
			asyncMain {
				switch result {
				case .success(let raster):
					self.rasterViewController.state = .raster(raster)
					completion?()

				case .failure(let e):
					self.rasterViewController.state = .error(e)
					completion?()
				}

			}
		})
	}

	@IBAction func editRow(_ sender: AnyObject) {
		if let md = self.mutableData, let _ = data, let raster = self.rasterViewController.raster {
			let selectedRowIndex = min(self.rasterViewController.selectedRow ?? 0, raster.rowCount)
			if raster.rowCount != 0 {
				let row = raster[selectedRowIndex]
				let editor = QBEEditViewController()
				editor.delegate = self

				let nav = UINavigationController(rootViewController: editor)

				if UIDevice.current.userInterfaceIdiom == .pad {
					nav.modalPresentationStyle = .formSheet
				}
				self.present(nav, animated: true) {
					editor.startEditing(row: row, dataset: md)
				}
			}
		}
		else {
			let ua = UIAlertController(title: "This data set cannot be edited".localized, message: "The source data set may not support editing or is read-only".localized, preferredStyle: .alert)
			ua.addAction(UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil))
			self.present(ua, animated: true)
		}
	}

	@IBAction func addRow(_ sender: AnyObject) {
		if let md = self.mutableData, let _ = data {
			let editor = QBEEditViewController()
			editor.delegate = self
			let nav = UINavigationController(rootViewController: editor)

			if UIDevice.current.userInterfaceIdiom == .pad {
				nav.modalPresentationStyle = .formSheet
			}
			self.present(nav, animated: true) {
				editor.startEditing(row: nil, dataset: md)
			}
		}
		else {
			let ua = UIAlertController(title: "This data set cannot be edited".localized, message: "The source data set may not support editing or is read-only".localized, preferredStyle: .alert)
			ua.addAction(UIAlertAction(title: "Dismiss".localized, style: .default, handler: nil))
			self.present(ua, animated: true)
		}
	}

	func editViewController(_: QBEEditViewController, didPerform mutation: DatasetMutation, completion: @escaping () -> ()) {
		// Replay mutation on the current raster
		let job = Job(.userInitiated)

		if let r = self.rasterViewController.raster {
			let rm = RasterMutableDataset(raster: r)
			rm.performMutation(mutation, job: job, callback: { result in
				switch result {
				case .success(_):
					self.rasterViewController.state = .raster(r)
					completion()

				case .failure(let e):
					print("Could not replay mutation on editing raster: \(e)")
					self.presentData(completion: completion)
				}
			})
		}
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
