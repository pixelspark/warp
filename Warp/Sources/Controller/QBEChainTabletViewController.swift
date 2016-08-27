import Cocoa

internal class QBEChainTabletViewController: QBETabletViewController, QBEChainViewDelegate {
	var chainViewController: QBEChainViewController? = nil { didSet { bind() } }

	override func tabletWasDeselected() {
		self.chainViewController?.selected = false
	}

	override func tabletWasSelected() {
		self.chainViewController?.selected = true
	}

	private func bind() {
		self.chainViewController?.chain = (self.tablet as! QBEChainTablet).chain
		self.chainViewController?.delegate = self
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "chain" {
			self.chainViewController = segue.destinationController as? QBEChainViewController
		}
	}

	override func selectArrow(_ arrow: QBETabletArrow) {
		if let s = arrow.fromStep, s != self.chainViewController?.currentStep {
			self.chainViewController?.currentStep = s
			self.chainViewController?.calculate()
		}
	}

	override func startEditing() {
		self.chainViewController?.startEditing(self)
	}

	/** Chain view delegate implementation */
	func chainViewDidClose(_ view: QBEChainViewController) -> Bool {
		return self.delegate?.tabletViewDidClose(self) ?? true
	}

	func chainView(_ view: QBEChainViewController, configureStep step: QBEStep?, necessary: Bool, delegate: QBESentenceViewDelegate) {
		self.delegate?.tabletView(self, didSelectConfigurable:step, configureNow: necessary, delegate: delegate)
	}

	func chainViewDidChangeChain(_ view: QBEChainViewController) {
		self.delegate?.tabletViewDidChangeContents(self)
	}

	func chainView(_ view: QBEChainViewController, exportChain chain: QBEChain) {
		self.delegate?.tabletView(self, exportObject: chain)
	}
}
