import Foundation
import WarpCore

internal class QBERethinkStepView: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	let step: QBERethinkSourceStep!
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var addColumnTextField: NSTextField!
	@IBOutlet var serverField: NSTextField!
	@IBOutlet var portField: NSTextField!
	@IBOutlet var authenticationKeyField: NSTextField!

	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate

		if let s = step as? QBERethinkSourceStep {
			self.step = s
			super.init(nibName: "QBERethinkStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBERethinkStepView", bundle: nil)
			return nil
		}
	}

	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}

	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}

	private func updateView() {
		tableView?.reloadData()
		self.serverField?.stringValue = self.step.server
		self.portField?.stringValue = "\(self.step.port)"
		self.authenticationKeyField?.stringValue = self.step.authenticationKey ?? ""
	}

	@IBAction func updateFromFields(sender: NSObject) {
		var change = false

		if self.serverField.stringValue != self.step.server {
			self.step.server = self.serverField.stringValue
			change = true
		}

		if self.portField.integerValue != self.step.port {
			let p = self.portField.integerValue
			if p>0 && p<65536 {
				self.step.port = p
				change = true
			}
		}

		if self.authenticationKeyField.stringValue != self.step.authenticationKey {
			self.step.authenticationKey = self.authenticationKeyField.stringValue
			change = true
		}

		if change {
			self.updateView()
			self.delegate?.suggestionsView(self, previewStep: step)
		}
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return step.columns.count
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if let s = step {
			s.columns[row] = QBEColumn(object as! String)
			self.delegate?.suggestionsView(self, previewStep: s)
		}
	}

	internal func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if let tc = tableColumn {
			if (tc.identifier ?? "") == "column" {
				return step.columns[row].name
			}
		}
		return nil
	}

	@IBAction func addColumn(sender: NSObject) {
		let s = self.addColumnTextField.stringValue
		if !s.isEmpty {
			if !step.columns.contains(QBEColumn(s)) {
				step.columns.append(QBEColumn(s))
				self.updateView()
				self.delegate?.suggestionsView(self, previewStep: step)
			}
		}
		self.addColumnTextField.stringValue = ""
	}

	@IBAction func removeColumns(sender: NSObject) {
		if let sr = self.tableView?.selectedRow where sr >= 0 && sr != NSNotFound && sr < self.step.columns.count {
			self.step.columns.removeAtIndex(sr)
			self.updateView()
			self.delegate?.suggestionsView(self, previewStep: step)
		}
	}
}