import Foundation
import Cocoa
import WarpCore

internal class QBECrawlStepView: NSViewController {
	weak var delegate: QBESuggestionsViewDelegate?
	let step: QBECrawlStep?

	@IBOutlet var targetBodyField: NSTextField!
	@IBOutlet var targetErrorField: NSTextField!
	@IBOutlet var targetStatusField: NSTextField!
	@IBOutlet var targetTimeField: NSTextField!
	@IBOutlet var maxConcurrentField: NSTextField!
	@IBOutlet var maxRequestsField: NSTextField!
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBECrawlStep {
			self.step = s
			super.init(nibName: "QBECrawlStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBECrawlStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		step = nil
		super.init(coder: coder)
	}
	
	@IBAction func updateFromView(sender: NSObject) {
		if let c = step?.crawler {
			var changed = false
			
			if targetBodyField.stringValue != (c.targetBodyColumn?.name ?? "") {
				c.targetBodyColumn = !targetBodyField.stringValue.isEmpty ? QBEColumn(targetBodyField.stringValue) : nil
				changed = true
			}
			
			if targetErrorField.stringValue != (c.targetErrorColumn?.name ?? "") {
				c.targetErrorColumn = !targetErrorField.stringValue.isEmpty ? QBEColumn(targetErrorField.stringValue) : nil
				changed = true
			}
			
			if targetStatusField.stringValue != (c.targetStatusColumn?.name ?? "") {
				c.targetStatusColumn = !targetStatusField.stringValue.isEmpty ? QBEColumn(targetStatusField.stringValue) : nil
				changed = true
			}
			
			if targetTimeField.stringValue != (c.targetResponseTimeColumn?.name ?? "") {
				c.targetResponseTimeColumn = !targetTimeField.stringValue.isEmpty ? QBEColumn(targetTimeField.stringValue) : nil
				changed = true
			}
			
			if maxConcurrentField.integerValue != c.maxConcurrentRequests {
				c.maxConcurrentRequests = maxConcurrentField.integerValue <= 0 ? 1 : maxConcurrentField.integerValue
				changed = true
			}
			
			if maxRequestsField.integerValue != (c.maxRequestsPerSecond ?? 0) {
				c.maxRequestsPerSecond = maxConcurrentField.integerValue <= 0 ? nil : maxConcurrentField.integerValue
				changed = true
			}
			
			if changed {
				delegate?.suggestionsView(self, previewStep: step)
			}
		}
	}
	
	private func updateFromCode() {		
		self.targetBodyField?.stringValue = step?.crawler.targetBodyColumn?.name ?? ""
		self.targetErrorField?.stringValue = step?.crawler.targetErrorColumn?.name ?? ""
		self.targetStatusField?.stringValue = step?.crawler.targetStatusColumn?.name ?? ""
		self.targetTimeField?.stringValue = step?.crawler.targetResponseTimeColumn?.name ?? ""
		
		if let mcp = step?.crawler.maxConcurrentRequests {
			self.maxConcurrentField?.integerValue = mcp
		}
		else {
			self.maxConcurrentField?.stringValue = ""
		}
		
		if let mrps = step?.crawler.maxRequestsPerSecond {
			self.maxRequestsField?.integerValue = mrps
		}
		else {
			self.maxRequestsField?.stringValue = ""
		}
	}
	
	override func viewWillAppear() {
		updateFromCode()
		super.viewWillAppear()
	}
}