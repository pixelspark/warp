import Foundation
import Cocoa
import WarpCore

internal class QBESQLiteSourceStepView: QBEConfigurableStepViewControllerFor<QBESQLiteSourceStep>, QBEAlterTableViewDelegate {
	@IBOutlet var createTableButton: NSButton?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBESQLiteSourceStepView", bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}

	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}

	func alterTableView(_ view: QBEAlterTableViewController, didAlterTable table: MutableDataset?) {
		if let s = table as? SQLMutableDataset {
			self.step.tableName = s.tableName
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
			self.updateView()
		}
	}

	private func updateView() {
		self.createTableButton?.isEnabled = self.step.warehouse?.canPerformMutation(.create("table", RasterDataset())) ?? false
	}

	@IBAction func createTable(_ sender: NSObject) {
		if let warehouse = self.step.warehouse {
			let vc = QBEAlterTableViewController()
			vc.warehouse = warehouse
			vc.delegate = self
			vc.warehouseName = String(format: NSLocalizedString("SQLite database '%@'", comment: ""), self.step.file?.url?.lastPathComponent ?? "")
			self.presentViewControllerAsModalWindow(vc)
		}
	}
}
