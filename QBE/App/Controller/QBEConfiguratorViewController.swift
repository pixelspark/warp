import Cocoa

class QBEConfiguratorViewController: NSViewController {
	@IBOutlet var titleLabel: NSTextField?
	@IBOutlet var configuratorView: NSView?
	
	func configure(step: QBEStep?, delegate: QBESuggestionsViewDelegate?) {
		if let s = step {
			let className = s.className
			let stepView = QBEFactory.sharedInstance.viewForStep(s.self, delegate: delegate!)
			self.contentView = stepView
			self.titleLabel?.hidden = false
			self.titleLabel?.attributedStringValue = NSAttributedString(string: s.explain(delegate!.locale, short: true))
		}
		else {
			self.titleLabel?.hidden = true
			self.titleLabel?.attributedStringValue = NSAttributedString(string: "")
			self.contentView = nil
		}
	}
	
	var contentView: NSViewController? {
		willSet(newValue) {
			if let s = contentView {
				s.removeFromParentViewController()
				s.view.removeFromSuperview()
			}
		}
		
		didSet {
			if let vc = contentView {
				if let cv = configuratorView {
					self.addChildViewController(vc)
					vc.view.translatesAutoresizingMaskIntoConstraints = false
					vc.view.frame = cv.bounds
					self.configuratorView?.addSubview(vc.view)
					
					cv.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|[CTRL_VIEW]|", options: NSLayoutFormatOptions.allZeros, metrics: nil, views: ["CTRL_VIEW": vc.view]))
					
					cv.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|[CTRL_VIEW]|", options: NSLayoutFormatOptions.allZeros, metrics: nil, views: ["CTRL_VIEW": vc.view]))
				}
			}
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		self.configuratorView?.translatesAutoresizingMaskIntoConstraints = false
	}
}
