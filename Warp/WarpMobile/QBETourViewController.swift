import UIKit

protocol QBEMobileTourViewControllerDelegate: class {
	func tourFinished(_ viewController: QBEMobileTourViewController)
}

class QBEMobileTourViewController: UIViewController {
	struct QBETourItem {
		let image: String
		let title: String
		let subtitle: String
	}
	
	@IBOutlet var imageView: UIImageView! = nil
	@IBOutlet var titleView: UILabel! = nil
	@IBOutlet var subtitleView: UITextView! = nil
	@IBOutlet var nextButton: UIButton! = nil

	private var currentIndex = 0
	weak var delegate: QBEMobileTourViewControllerDelegate? = nil
	private var items: [QBETourItem] = []

	@IBAction func skipTour(_ sender: AnyObject) {
		self.delegate?.tourFinished(self)
		self.dismiss(animated: true, completion: nil)
	}

	override func viewWillAppear(_ animated: Bool) {
		items = (0...4).map { n in
			return QBETourItem(
				image: NSLocalizedString("mtour.\(n).image", tableName: "MobileTour", bundle: Bundle.main, value: "", comment: ""),
				title: NSLocalizedString("mtour.\(n).title", tableName: "MobileTour", bundle: Bundle.main, value: "", comment: ""),
				subtitle: NSLocalizedString("mtour.\(n).subtitle", tableName: "MobileTour", bundle: Bundle.main, value: "", comment: "")
			)
		}

		self.currentIndex = 0
		self.update()
	}

	private func update() {
		// Set image view
		let item = self.items[self.currentIndex]
		self.imageView.image = UIImage(named: item.image)
		self.titleView.text = item.title
		self.subtitleView.text = item.subtitle

		let title: String
		switch self.currentIndex {
		case 0: title = "Okay, show me!".localized
		case self.items.count-1: title = "Get started".localized
		default: title = "Got it!".localized
		}

		self.nextButton.setTitle(title, for: .normal)
	}

	@IBAction func next(_ sender: AnyObject) {
		if self.currentIndex < self.items.count-1 {
			let trans = CATransition()
			trans.duration = 0.3
			trans.type = kCATransitionPush
			trans.subtype = kCATransitionFromRight
			self.view.layer.add(trans, forKey: "push")

			self.currentIndex += 1
			self.update()
		}
		else {
			self.delegate?.tourFinished(self)
			self.dismiss(animated: true, completion: nil)
		}
	}
}
