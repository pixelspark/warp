/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Cocoa
import WarpCore

protocol QBEReferenceViewDelegate: NSObjectProtocol {
	func referenceView(_ view: QBEReferenceViewController, didSelectFunction: Function)
}

class QBEReferenceViewController: NSViewController,  NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet private var searchField: NSSearchField?
	@IBOutlet private var valueList: NSTableView?
	@IBOutlet private var exampleLabel: NSTextField!
	
	private var locale: Language?
	private var functions: [String] = []
	weak var delegate: QBEReferenceViewDelegate? = nil
	
	@IBAction func insertFormula(_ sender: NSObject) {
		if let selectedRow = valueList?.selectedRow {
			if selectedRow >= 0 && selectedRow < functions.count {
				let selectedName = functions[selectedRow]
				if let function = locale?.functionWithName(selectedName) {
					delegate?.referenceView(self, didSelectFunction: function)
				}
			}
		}
	}
	
	@IBAction func searchChanged(_ sender: NSObject) {
		reloadData()
	}
	
	override func viewWillAppear() {
		self.view.window?.titlebarAppearsTransparent = true
		locale = QBEAppDelegate.sharedInstance.locale
		reloadData()
		super.viewWillAppear()
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		updateExample()
	}
	
	private func updateExample() {
		if let selectedRow = valueList?.selectedRow {
			if selectedRow >= 0 && selectedRow < functions.count {
				let selectedName = functions[selectedRow]
				let function = locale!.functionWithName(selectedName)!
				if let parameters = function.parameters {
					let expression = Call(arguments: parameters.map({ return Literal($0.exampleValue) }), type: function)
					let result = expression.apply(Row(), foreign: nil, inputValue: nil)
					
					let formula = expression.toFormula(locale!, topLevel: true)
					if let parsedFormula = Formula(formula: formula, locale: locale!) {
						let ma = NSMutableAttributedString()
						ma.append(parsedFormula.syntaxColoredFormula)
						ma.append(NSAttributedString(string: " = ", attributes: [:]))
						ma.append(NSAttributedString(string: locale!.localStringFor(result), attributes: [:]))
						self.exampleLabel.attributedStringValue = ma
					}
					return
				}
			}
		}
		
		self.exampleLabel?.attributedStringValue = NSAttributedString(string: "")
	}
	
	private func reloadData() {
		let search = searchField?.stringValue ?? ""
		let functionNames = Array(locale!.functions.keys).sorted()
		
		var foundFunctionNames: [String] = []
		for name in functionNames {
			let function = locale!.functionWithName(name)
			if search.isEmpty || name.range(of: search, options: String.CompareOptions.caseInsensitive) != nil || function?.localizedName.range(of: search, options: String.CompareOptions.caseInsensitive) != nil {
				foundFunctionNames.append(name)
			}
		}
		functions = foundFunctionNames
		self.valueList?.reloadData()
	}
	
	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		if row >= 0 && row < functions.count {
			let functionName = functions[row]
			if let function = locale?.functionWithName(functionName) {
				if let tc = tableColumn {
					switch tc.identifier {
						case "name":
							return functionName
						
						case "description":
							return function.localizedName
						
						case "parameters":
							if let parameters = function.parameters {
								var parameterNames = parameters.map({ return $0.name })
								switch function.arity {
									case .between(_, _), .atLeast(_), .any:
										parameterNames.append("...")
									
									default:
										break
								}
								return parameterNames.joined(separator: locale!.argumentSeparator + " ")
							}
							else {
								return function.arity.explanation
							}
						
						default:
							return nil
					}
				}
			}
		}
		
		return nil
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return functions.count
	}

	@IBAction func didDoubleClickRow(_ sender: NSObject) {
		insertFormula(sender)
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		self.valueList?.doubleAction = #selector(QBEReferenceViewController.didDoubleClickRow(_:))
		self.valueList?.target = self
	}
}
