import Cocoa

class QBEReferenceViewController: NSViewController,  NSTableViewDataSource, NSTableViewDelegate {
	/** When a function is selected and 'inserted' from this reference view, a notification with the name given below is
	sent. The 'object' of the NSNotification will contain the raw (internal) name of the selected QBEFunction (i.e. its
	rawValue). */
	static let notificationName = "nl.pixelspark.Warp.QBEFunctionName"
	
	@IBOutlet var searchField: NSSearchField?
	@IBOutlet var valueList: NSTableView?
	@IBOutlet var exampleLabel: NSTextField!
	
	private var locale: QBELocale?
	private var functions: [String] = []
	
	@IBAction func insertFormula(sender: NSObject) {
		if let selectedRow = valueList?.selectedRow {
			if selectedRow >= 0 && selectedRow < functions.count {
				let selectedName = functions[selectedRow]
				let function = locale!.functionWithName(selectedName)!
				let n = NSNotification(name: QBEReferenceViewController.notificationName, object: function.rawValue)
				NSNotificationCenter.defaultCenter().postNotification(n)
			}
		}
	}
	
	@IBAction func searchChanged(sender: NSObject) {
		reloadData()
	}
	
	override func viewWillAppear() {
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
					let expression = QBEFunctionExpression(arguments: parameters.map({ return QBELiteralExpression($0.exampleValue) }), type: function)
					let result = expression.apply(QBERow(), foreign: nil, inputValue: nil)
					
					let formula = expression.toFormula(locale!, topLevel: true)
					if let parsedFormula = QBEFormula(formula: formula, locale: locale!) {
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
								return parameterNames.implode(locale!.argumentSeparator + " ")
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
}