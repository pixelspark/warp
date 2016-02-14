import Foundation
import Cocoa
import WarpCore

internal class QBECrawlStepView: QBEConfigurableStepViewControllerFor<QBECrawlStep> {
	@IBOutlet var targetBodyField: NSTextField!
	@IBOutlet var targetErrorField: NSTextField!
	@IBOutlet var targetStatusField: NSTextField!
	@IBOutlet var targetTimeField: NSTextField!
	@IBOutlet var maxConcurrentField: NSTextField!
	@IBOutlet var maxRequestsField: NSTextField!

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBECrawlStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	@IBAction func updateFromView(sender: NSObject) {
		let c = step.crawler
		var changed = false
		
		if targetBodyField.stringValue != (c.targetBodyColumn?.name ?? "") {
			c.targetBodyColumn = !targetBodyField.stringValue.isEmpty ? Column(targetBodyField.stringValue) : nil
			changed = true
		}
		
		if targetErrorField.stringValue != (c.targetErrorColumn?.name ?? "") {
			c.targetErrorColumn = !targetErrorField.stringValue.isEmpty ? Column(targetErrorField.stringValue) : nil
			changed = true
		}
		
		if targetStatusField.stringValue != (c.targetStatusColumn?.name ?? "") {
			c.targetStatusColumn = !targetStatusField.stringValue.isEmpty ? Column(targetStatusField.stringValue) : nil
			changed = true
		}
		
		if targetTimeField.stringValue != (c.targetResponseTimeColumn?.name ?? "") {
			c.targetResponseTimeColumn = !targetTimeField.stringValue.isEmpty ? Column(targetTimeField.stringValue) : nil
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
			delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
	}
	
	private func updateFromCode() {		
		self.targetBodyField?.stringValue = step.crawler.targetBodyColumn?.name ?? ""
		self.targetErrorField?.stringValue = step.crawler.targetErrorColumn?.name ?? ""
		self.targetStatusField?.stringValue = step.crawler.targetStatusColumn?.name ?? ""
		self.targetTimeField?.stringValue = step.crawler.targetResponseTimeColumn?.name ?? ""
		self.maxConcurrentField?.integerValue = step.crawler.maxConcurrentRequests
		self.maxRequestsField?.integerValue = step.crawler.maxRequestsPerSecond ?? 0
	}
	
	override func viewWillAppear() {
		updateFromCode()
		super.viewWillAppear()
	}
}