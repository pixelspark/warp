import Foundation

class QBEJoinStepView: NSViewController, NSComboBoxDataSource, NSComboBoxDelegate {
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var tabView: NSTabView!
	@IBOutlet var foreignComboBox: NSComboBox!
	@IBOutlet var siblingComboBox: NSComboBox!
	let step: QBEJoinStep?
	
	private var existingOwnColumns: [QBEColumn] = []
	private var existingForeignColumns: [QBEColumn] = []
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEJoinStep {
			self.step = s
			super.init(nibName: "QBEJoinStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEJoinStepView", bundle: nil)
			return nil
		}
	}
	
	var simpleForeign: QBEColumn? {
		get {
			if let foreign = (self.step?.condition as? QBEBinaryExpression)?.first as? QBEForeignExpression {
				return foreign.columnName
			}
			else if let foreign = (self.step?.condition as? QBEBinaryExpression)?.second as? QBEForeignExpression {
				return foreign.columnName
			}
			else {
				return nil
			}
		}
		set {
			setSimpleCondition(sibling: simpleSibling, foreign: newValue)
		}
	}
	
	var simpleSibling: QBEColumn? {
		get {
			if let sibling = (self.step?.condition as? QBEBinaryExpression)?.second as? QBESiblingExpression {
				return sibling.columnName
			}
			else if let sibling = (self.step?.condition as? QBEBinaryExpression)?.first as? QBESiblingExpression {
				return sibling.columnName
			}
			else {
				return nil
			}
		}
		set {
			setSimpleCondition(sibling: newValue, foreign: simpleForeign)
		}
	}
	
	private func setSimpleCondition(#sibling: QBEColumn?, foreign: QBEColumn?) {
		let currentType = (self.step?.condition as? QBEBinaryExpression)?.type ?? QBEBinary.Equal
		let first: QBEExpression = (foreign != nil) ? QBEForeignExpression(columnName: foreign!) : QBELiteralExpression(QBEValue.InvalidValue)
		let second: QBEExpression = (sibling != nil) ? QBESiblingExpression(columnName: sibling!) : QBELiteralExpression(QBEValue.InvalidValue)
		self.step?.condition = QBEBinaryExpression(first: first, second: second, type: currentType)
	}
	
	/**
	Returns whether the currently set join is 'simple' (e.g. only based on a comparison of two columns). This requires the
	join condition to be a binary expression with on either side a column reference. */
	var isSimple: Bool { get {
		if let s = step {
			if let c = s.condition as? QBEBinaryExpression {
				if let left = c.first as? QBEForeignExpression, let right = c.second as? QBESiblingExpression {
					return true
				}
				
				if c.isConstant {
					let constantValue = c.apply(QBERow(), foreign: nil, inputValue: nil)
					if !constantValue.isValid || constantValue == QBEValue.BoolValue(false) {
						return true
					}
				}
			}
		}
		return false
	} }
	
	required init?(coder: NSCoder) {
		step = nil
		super.init(coder: coder)
	}
	
	func comboBox(aComboBox: NSComboBox, objectValueForItemAtIndex index: Int) -> AnyObject {
		if aComboBox == foreignComboBox {
			return existingForeignColumns[index].name
		}
		else if aComboBox == siblingComboBox {
			return existingOwnColumns[index].name
		}
		return ""
	}
	
	func numberOfItemsInComboBox(aComboBox: NSComboBox) -> Int {
		if aComboBox == foreignComboBox {
			return existingForeignColumns.count
		}
		else if aComboBox == siblingComboBox {
			return existingOwnColumns.count
		}
		return 0
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		if let s = step {
			self.formulaField?.stringValue = "=" + (s.condition?.toFormula(self.delegate?.locale ?? QBELocale()) ?? "")
			self.tabView.selectTabViewItemAtIndex(isSimple ? 0 : 1)
		}
		updateView()
	}
	
	private func updateView() {
		if let s = step {
			// Populate the 'simple' view
			siblingComboBox.enabled = isSimple
			foreignComboBox.enabled = isSimple
			if isSimple {
				siblingComboBox.stringValue = simpleSibling?.name ?? ""
				foreignComboBox.stringValue = simpleForeign?.name ?? ""
			}
			else {
				siblingComboBox.stringValue = ""
				foreignComboBox.stringValue = ""
			}
			
			if let f = s.condition {
				self.formulaField?.stringValue = "="+f.toFormula(self.delegate?.locale ?? QBELocale())
			}
			
			// Fetch own sibling columns
			if let selected = tabView.selectedTabViewItem where tabView.indexOfTabViewItem(selected) == 0 {
				let job = QBEJob(.UserInitiated)
				s.previous?.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
					switch data {
					case .Success(let d):
						d.value.columnNames(job) {(cns) in
							QBEAsyncMain {
								switch cns {
								case .Success(let e):
									self.existingOwnColumns = e.value
									
								case .Failure(_):
									self.existingOwnColumns = []
								}
							
								self.siblingComboBox?.reloadData()
							}
						}
						
					case .Failure(let errorMessage):
						break
					}
				}
				
				// Fetch foreign columns
				s.right?.head?.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
					switch data {
					case .Success(let d):
						d.value.columnNames(job) {(cns) in
							QBEAsyncMain {
								switch cns {
								case .Success(let e):
									self.existingForeignColumns = e.value
									
								case .Failure(_):
									self.existingForeignColumns = []
								}
							
								self.foreignComboBox?.reloadData()
							}
						}
						
					case .Failure(let errorMessage):
						break
					}
				}
			}
		}
	}
	
	@IBAction func updateFromSimpleView(sender: NSObject) {
		if isSimple {
			simpleSibling = QBEColumn(siblingComboBox.stringValue)
			simpleForeign = QBEColumn(foreignComboBox.stringValue)
			delegate?.suggestionsView(self, previewStep: self.step)
		}
		updateView()
	}
	
	@IBAction func updateFromComplexView(sender: NSObject) {
		if let s = step {
			// Set formula
			let oldFormula = "=" + (s.condition?.toFormula(self.delegate?.locale ?? QBELocale()) ?? "");
			if let f = self.formulaField?.stringValue {
				if f != oldFormula {
					if let parsed = QBEFormula(formula: f, locale: (self.delegate?.locale ?? QBELocale()))?.root {
						s.condition = parsed
						delegate?.suggestionsView(self, previewStep: s)
						updateView()
					}
					else {
						// TODO this should be a bit more informative
						let a = NSAlert()
						a.messageText = NSLocalizedString("The formula you typed is not valid.", comment: "")
						a.alertStyle = NSAlertStyle.WarningAlertStyle
						a.beginSheetModalForWindow(self.view.window!, completionHandler: nil)
					}
				}
			}
		}
	}
	
	override func viewWillDisappear() {
		self.foreignComboBox.dataSource = nil
		self.siblingComboBox.dataSource = nil
		self.foreignComboBox.delegate = nil
		self.siblingComboBox.delegate = nil
	}
}