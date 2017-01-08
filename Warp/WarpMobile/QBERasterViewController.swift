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

enum QBERasterViewState {
	case loading
	case error(String)
	case raster(Raster)
}

protocol QBERasterViewControllerDelegate: class {
	func rasterView(_ controller: QBERasterViewController, filter column: Column, for value: Value)
}

class QBERasterViewController: UIViewController, MDSpreadViewDelegate, MDSpreadViewDataSource {
	@IBOutlet var spreadView: MDSpreadView! = nil
	@IBOutlet var errorLabel: UILabel! = nil
	@IBOutlet var activityIndicator: UIActivityIndicatorView! = nil

	private var selectedRow: MDIndexPath? = nil
	private var selectedColumn: MDIndexPath? = nil

	weak var delegate: QBERasterViewControllerDelegate? = nil

	var state: QBERasterViewState = .loading { didSet {
		if spreadView != nil {
			self.updateView()
		}
	} }

	var raster: Raster? {
		if case .raster(let raster) = self.state {
			return raster
		}
		return nil
	}

	private func updateView() {
		self.spreadView.columnWidth = 140;

		switch self.state {
		case .error(let error):
			self.activityIndicator.isHidden = true
			self.errorLabel.isHidden = false
			self.spreadView.isHidden = true
			self.errorLabel.text = error

		case .raster(_):
			self.activityIndicator.isHidden = true
			self.errorLabel.isHidden = true
			self.spreadView.isHidden = false
			self.spreadView?.reloadData()

		case .loading:
			self.activityIndicator.isHidden = false
			self.errorLabel.isHidden = true
			self.spreadView.isHidden = true
		}
		self.view.layoutSubviews()
	}

	override func viewWillAppear(_ animated: Bool) {
		self.updateView()
		super.viewWillAppear(animated)
	}

	@IBAction func cellMenu(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if let sc = self.selectedColumn, let sr = self.selectedRow, self.becomeFirstResponder(), self.delegate != nil {
				let mc = UIMenuController.shared

				mc.menuItems = [
					UIMenuItem(title: "Filter".localized, action: #selector(QBERasterViewController.filterSelectedValue(_:))),
				]

				mc.setTargetRect(self.spreadView.cellRectForRow(at: sr, forColumnAt: sc), in: self.spreadView)
				mc.setMenuVisible(true, animated: true)
			}
		}
	}

	override var canBecomeFirstResponder: Bool { return true }

	@IBAction func filterSelectedValue(_ sender: AnyObject) {
		if let sc = self.selectedColumn, let sr = self.selectedRow, let r = raster {
			let value = r[sr.row, sc.column]
			let column = r.columns[sc.column]
			self.delegate?.rasterView(self, filter: column, for: value!)
		}
	}

	func numberOfRowSections(in aSpreadView: MDSpreadView!) -> Int {
		return 1
	}

	func numberOfColumnSections(in aSpreadView: MDSpreadView!) -> Int {
		return 1
	}

	func spreadView(_ aSpreadView: MDSpreadView!, numberOfRowsInSection section: Int) -> Int {
		return Int(self.raster?.rows.count ?? 0)
	}

	func spreadView(_ aSpreadView: MDSpreadView!, numberOfColumnsInSection section: Int) -> Int {
		return Int(self.raster?.columns.count ?? 0)
	}

	func spreadView(_ aSpreadView: MDSpreadView!, objectValueForRowAt rowPath: MDIndexPath!, forColumnAt columnPath: MDIndexPath!) -> Any! {
		let lang = QBEAppDelegate.sharedInstance.locale
		if let r = raster {
			return lang.localStringFor(r[rowPath.row, columnPath.column])
		}
		return ""
	}

	func spreadView(_ aSpreadView: MDSpreadView!, titleForHeaderInRowSection rowSection: Int, forColumnSection columnSection: Int) -> Any! {
		return "";
	}

	func spreadView(_ aSpreadView: MDSpreadView!, titleForHeaderInColumnSection section: Int, forRowAt rowPath: MDIndexPath!) -> Any! {
		return "\(rowPath!.row+1)";
	}

	/*func spreadView(_ aSpreadView: MDSpreadView!, titleForFooterInRowSection section: Int, forColumnAt columnPath: MDIndexPath!) -> Any! {
		return "\(columnPath!.row+1)";
	}*/

	func spreadView(_ aSpreadView: MDSpreadView!, titleForHeaderInRowSection section: Int, forColumnAt columnPath: MDIndexPath!) -> Any! {
		if let r = raster {
			return r.columns[columnPath.column].name
		}
		return ""
	}

	func spreadView(_ aSpreadView: MDSpreadView!, heightForRowHeaderInSection rowSection: Int) -> CGFloat {
		return 32.0;
	}

	func spreadView(_ aSpreadView: MDSpreadView!, widthForColumnHeaderInSection columnSection: Int) -> CGFloat {
		return 70.0;
	}

	func spreadView(_ aSpreadView: MDSpreadView!, didSelectCellForRowAt rowPath: MDIndexPath!, forColumnAt columnPath: MDIndexPath!) {
		self.selectedRow = rowPath
		self.selectedColumn = columnPath
	}
}
