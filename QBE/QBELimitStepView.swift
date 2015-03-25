import Foundation
import Cocoa

internal class QBELimitStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var numberOfRowsField: NSTextField?
	let step: QBELimitStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBELimitStep {
			self.step = s
			super.init(nibName: "QBELimitStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBELimitStepView", bundle: nil)
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

internal class QBEOffsetStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var numberOfRowsField: NSTextField?
	let step: QBEOffsetStep?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEOffsetStep {
			self.step = s
			super.init(nibName: "QBELimitStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBELimitStepView", bundle: nil)
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