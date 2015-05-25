import Foundation

internal class QBEDebugStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var action: NSPopUpButton?
	let step: QBEDebugStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEDebugStep {
			self.step = s
			super.init(nibName: "QBEDebugStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEDebugStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			action?.selectItem(action?.menu?.itemWithTag(s.type.rawValue))
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			if let tag = action?.selectedItem?.tag, let type = QBEDebugStep.QBEDebugType(rawValue: tag) {
				if type != s.type {
					s.type = type
					delegate?.suggestionsView(self, previewStep: s)
				}
			}
		}
	}
}
