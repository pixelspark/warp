/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Cocoa
import WarpCore
import WarpConduit

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
		self.createTableButton?.isEnabled = self.step.warehouse?.canPerformMutation(.create) ?? false
	}

	@IBAction func createTable(_ sender: NSObject) {
		if let warehouse = self.step.warehouse {
			let vc = QBEAlterTableViewController()
			vc.warehouse = warehouse
			vc.delegate = self
			vc.warehouseName = String(format: NSLocalizedString("SQLite database '%@'", comment: ""), self.step.file?.url?.lastPathComponent ?? "")
			self.presentAsModalWindow(vc)
		}
	}
}
