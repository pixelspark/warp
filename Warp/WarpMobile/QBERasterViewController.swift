import UIKit
import WarpCore

enum QBERasterViewState {
	case loading
	case error(String)
	case raster(Raster)
}

class QBERasterViewController: UIViewController, MDSpreadViewDelegate, MDSpreadViewDataSource {
	@IBOutlet var spreadView: MDSpreadView! = nil
	@IBOutlet var errorLabel: UILabel! = nil
	@IBOutlet var activityIndicator: UIActivityIndicatorView! = nil

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
			return lang!.localStringFor(r[rowPath.row, columnPath.column])
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
}
