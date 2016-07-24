import Foundation
import Cocoa
import WarpCore

internal class QBECacheStepView: QBEConfigurableStepViewControllerFor<QBECacheStep> {
	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBECacheStepView", bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("Cannot load from coder")
	}

	@IBAction func evictCache(_ sender: NSObject) {
		step.evictCache()
		delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
}
