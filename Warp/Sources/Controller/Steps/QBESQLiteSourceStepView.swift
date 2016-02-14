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

	func alterTableView(view: QBEAlterTableViewController, didAlterTable table: MutableData?) {
		if let s = table as? SQLMutableData {
			self.step.tableName = s.tableName
			self.delegate?.configurableView(self, didChangeConfigurationFor: step)
			self.updateView()
		}
	}

	private func updateView() {
		self.createTableButton?.enabled = self.step.mutableData?.warehouse.canPerformMutation(.Create("table", RasterData())) ?? false
	}

	@IBAction func createTable(sender: NSObject) {
		if let mutableData = self.step.mutableData {
			let vc = QBEAlterTableViewController()
			vc.warehouse = mutableData.warehouse
			vc.delegate = self
			vc.warehouseName = String(format: NSLocalizedString("SQLite database '%@'", comment: ""), self.step.file?.url?.lastPathComponent ?? "")
			self.presentViewControllerAsModalWindow(vc)
		}
	}
}