import Cocoa
import WarpCore

protocol QBEReferenceViewDelegate: NSObjectProtocol {
	func referenceView(view: QBEReferenceViewController, didSelectFunction: Function)
}

class QBEReferenceViewController: NSViewController,  NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet private var searchField: NSSearchField?
	@IBOutlet private var valueList: NSTableView?
	@IBOutlet private var exampleLabel: NSTextField!
	
	private var locale: Locale?
	private var functions: [String] = []
	weak var delegate: QBEReferenceViewDelegate? = nil
	
	@IBAction func insertFormula(sender: NSObject) {
		if let selectedRow = valueList?.selectedRow {
			if selectedRow >= 0 && selectedRow < functions.count {
				let selectedName = functions[selectedRow]
				if let function = locale?.functionWithName(selectedName) {
					delegate?.referenceView(self, didSelectFunction: function)
				}
			}
		}
	}
	
	@IBAction func searchChanged(sender: NSObject) {
		reloadData()
	}
	
	override func viewWillAppear() {
		self.view.window?.titlebarAppearsTransparent = true
		locale = QBEAppDelegate.sharedInstance.locale
		reloadData()
		super.viewWillAppear()
	}
	
	func tableViewSelectionDidChange(notification: NSNotification) {
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
						ma.appendAttributedString(parsedFormula.syntaxColoredFormula)
						ma.appendAttributedString(NSAttributedString(string: " = ", attributes: [:]))
						ma.appendAttributedString(NSAttributedString(string: locale!.localStringFor(result), attributes: [:]))
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
		let functionNames = Array(locale!.functions.keys).sort()
		
		var foundFunctionNames: [String] = []
		for name in functionNames {
			let function = locale!.functionWithName(name)
			if search.isEmpty || name.rangeOfString(search, options: NSStringCompareOptions.CaseInsensitiveSearch) != nil || function?.explain(locale!).rangeOfString(search, options: NSStringCompareOptions.CaseInsensitiveSearch) != nil {
				foundFunctionNames.append(name)
			}
		}
		functions = foundFunctionNames
		self.valueList?.reloadData()
	}
	
	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		if row >= 0 && row < functions.count {
			let functionName = functions[row]
			if let function = locale?.functionWithName(functionName) {
				if let tc = tableColumn {
					switch tc.identifier {
						case "name":
							return functionName
						
						case "description":
							return function.explain(self.locale!)
						
						case "parameters":
							if let parameters = function.parameters {
								var parameterNames = parameters.map({ return $0.name })
								switch function.arity {
									case .Between(_, _), .AtLeast(_), .Any:
										parameterNames.append("...")
									
									default:
										break
								}
								return parameterNames.joinWithSeparator(locale!.argumentSeparator + " ")
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
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return functions.count
	}

	@IBAction func didDoubleClickRow(sender: NSObject) {
		insertFormula(sender)
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		self.valueList?.doubleAction = #selector(QBEReferenceViewController.didDoubleClickRow(_:))
		self.valueList?.target = self
	}
}