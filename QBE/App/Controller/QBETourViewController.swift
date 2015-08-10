import Cocoa

class QBETourWindowController: NSWindowController {
	override var document: AnyObject? {
		didSet {
			if let tourViewController = window!.contentViewController as? QBETourViewController {
				tourViewController.document = document as? QBEDocument
			}
		}
	}
}

/** The tour controller will show image assets named "Tour@@" where '@@' is between 1 and the tourItemCount. It will fetch
descriptive texts using NSLocalizedString on the Tour strings bundle. */
class QBETourViewController: NSViewController {
	static let tourPrefix = "Tour"
	static let tourItemCount = 8

	@IBOutlet var imageView: NSImageView!
	@IBOutlet var textView: NSTextField!
	@IBOutlet var subTextView: NSTextField!
	@IBOutlet var animatedView: NSView!
	@IBOutlet var pageLabel: NSTextField!
	@IBOutlet var nextButton: NSButton!
	@IBOutlet var skipButton: NSButton!

	var document: QBEDocument? = nil
	private var currentStep = 0

	private func nextStep(animated: Bool) {
		if animated {
			let tr = CATransition()
			tr.duration = 0.3
			tr.type = kCATransitionFade
			tr.subtype = kCATransitionFromRight
			tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
			animatedView.layer?.addAnimation(tr, forKey: kCATransition)
		}
		self.currentStep++
		updateView()
	}

	@IBAction func endTour(sender: NSObject) {
		if let d = document, let ownController = self.view.window?.windowController {
			d.removeWindowController(ownController)
			d.makeWindowControllers()

			if let w = d.windowControllers.first?.window, let ownWindow = self.view.window {
				w.setFrame(ownWindow.convertRectToScreen(self.view.convertRect(self.imageView.frame, toView: nil)), display: false)
			}
			d.showWindows()
			self.document = nil
		}
		self.view.window?.close()
	}

	private func updateView() {
		pageLabel.hidden = currentStep == (QBETourViewController.tourItemCount) || currentStep == 0
		skipButton.hidden = pageLabel.hidden

		if currentStep == 0 {
			nextButton.title = NSLocalizedString("Okay, show me!", comment: "")
		}
		else if currentStep == QBETourViewController.tourItemCount {
			nextButton.title = NSLocalizedString("Get started", comment: "")
		}
		else {
			nextButton.title = NSLocalizedString("Got it!", comment: "")
		}
		
		pageLabel.stringValue = currentStep > 0 ? String(format:NSLocalizedString("Step %d of %d", comment: ""), currentStep, QBETourViewController.tourItemCount - 1) : ""
		imageView.image = NSImage(named: "Tour\(self.currentStep)")
		textView.stringValue = NSLocalizedString("tour.\(currentStep).title", tableName: "Tour", bundle: NSBundle.mainBundle(), value: "", comment: "")
		subTextView.stringValue = NSLocalizedString("tour.\(currentStep).description", tableName: "Tour", bundle: NSBundle.mainBundle(), value: "", comment: "")
	}

	@IBAction func next(sender: NSObject) {
		if currentStep < QBETourViewController.tourItemCount {
			nextStep(true)
		}
		else {
			endTour(sender)
		}
	}

	override func viewWillAppear() {
		self.currentStep = 0
		self.view.window?.titlebarAppearsTransparent = true
		self.view.window?.titleVisibility = NSWindowTitleVisibility.Hidden
		self.view.window?.movableByWindowBackground = true
		updateView()
	}

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
