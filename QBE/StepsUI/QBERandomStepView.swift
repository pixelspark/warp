import Foundation

internal class QBERandomStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var numberOfRowsField: NSTextField?
	let step: QBERandomStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBERandomStep {
			self.step = s
			super.init(nibName: "QBERandomStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBERandomStepView", bundle: nil)
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
			numberOfRowsField?.stringValue = s.numberOfRows.toString()
		}
	}
	
	@IBAction func update(sender: NSObject) {
		if let s = step {
			s.numberOfRows = (numberOfRowsField?.stringValue ?? "1").toInt() ?? 1
			delegate?.suggestionsView(self, previewStep: s)
		}
	}
}
