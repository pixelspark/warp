import Foundation
import WarpCore

class QBEJoinStepView: QBEConfigurableStepViewControllerFor<QBEJoinStep>, NSComboBoxDataSource, NSComboBoxDelegate, NSTabViewDelegate {
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var tabView: NSTabView!
	@IBOutlet var foreignComboBox: NSComboBox!
	@IBOutlet var siblingComboBox: NSComboBox!
	@IBOutlet var joinTypeBox: NSPopUpButton!
	
	private var existingOwnColumns: [Column] = []
	private var existingForeignColumns: [Column] = []

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEJoinStepView", bundle: nil)
	}
	
	var simpleForeign: Column? {
		get {
			if let foreign = (self.step.condition as? Comparison)?.first as? Foreign {
				return foreign.column
			}
			else if let foreign = (self.step.condition as? Comparison)?.second as? Foreign {
				return foreign.column
			}
			else {
				return nil
			}
		}
		set {
			setSimpleCondition(sibling: simpleSibling, foreign: newValue)
		}
	}
	
	var simpleSibling: Column? {
		get {
			if let sibling = (self.step.condition as? Comparison)?.second as? Sibling {
				return sibling.column
			}
			else if let sibling = (self.step.condition as? Comparison)?.first as? Sibling {
				return sibling.column
			}
			else {
				return nil
			}
		}
		set {
			setSimpleCondition(sibling: newValue, foreign: simpleForeign)
		}
	}
	
	private func setSimpleCondition(sibling sibling: Column?, foreign: Column?) {
		let currentType = (self.step.condition as? Comparison)?.type ?? Binary.Equal
		let first: Expression = (foreign != nil) ? Foreign(foreign!) : Literal(Value.InvalidValue)
		let second: Expression = (sibling != nil) ? Sibling(sibling!) : Literal(Value.InvalidValue)
		self.step.condition = Comparison(first: first, second: second, type: currentType)
	}
	
	func tabView(tabView: NSTabView, didSelectTabViewItem tabViewItem: NSTabViewItem?) {
		updateView()
	}
	
	/**
	Returns whether the currently set join is 'simple' (e.g. only based on a comparison of two columns). This requires the
	join condition to be a binary expression with on either side a column reference. */
	var isSimple: Bool { get {
		if let c = step.condition as? Comparison {
			if c.first is Foreign && c.second is Sibling {
				return true
			}
			
			if c.second is Foreign && c.first is Sibling {
				return true
			}
			
			if c.isConstant {
				let constantValue = c.apply(Row(), foreign: nil, inputValue: nil)
				if !constantValue.isValid || constantValue == Value.BoolValue(false) {
					return true
				}
			}

			return false
		}
		else {
			return true
		}
	} }
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
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
		self.formulaField?.stringValue = (step.condition?.toFormula(self.delegate?.locale ?? Locale(), topLevel: true) ?? "")
		self.tabView.selectTabViewItemAtIndex(isSimple ? 0 : 1)
		updateView()
	}
	
	private func updateView() {
		switch step.joinType {
			case .LeftJoin: self.joinTypeBox.selectItemWithTag(0)
			case .InnerJoin: self.joinTypeBox.selectItemWithTag(1)
		}
		
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
		
		if let f = step.condition {
			let formula = f.toFormula(self.delegate?.locale ?? Locale(), topLevel: true)
			if let parsed = Formula(formula: formula, locale: self.delegate?.locale ?? Locale()) {
				self.formulaField?.attributedStringValue = parsed.syntaxColoredFormula
			}
		}
		
		// Fetch own sibling columns
		if let selected = tabView.selectedTabViewItem where tabView.indexOfTabViewItem(selected) == 0 {
			let job = Job(.UserInitiated)
			step.previous?.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
				switch data {
				case .Success(let d):
					d.columns(job) { (cns) in
						asyncMain {
							switch cns {
							case .Success(let e):
								self.existingOwnColumns = e
								
							case .Failure(_):
								self.existingOwnColumns = []
							}
						
							self.siblingComboBox?.reloadData()
						}
					}
					
				case .Failure(_):
					break
				}
			}
			
			// Fetch foreign columns
			step.right?.head?.exampleData(job, maxInputRows: 100, maxOutputRows: 100) { (data) in
				switch data {
				case .Success(let d):
					d.columns(job) { (cns) in
						asyncMain {
							switch cns {
							case .Success(let e):
								self.existingForeignColumns = e
								
							case .Failure(_):
								self.existingForeignColumns = []
							}
						
							self.foreignComboBox?.reloadData()
						}
					}
					
				case .Failure(_):
					break
				}
			}
		}
	}
	
	@IBAction func updateFromJoinTypeSelector(sender: NSObject) {
		let newJoinType: JoinType
		switch self.joinTypeBox.selectedTag() {
		case 0:
			newJoinType = .LeftJoin
			
		case 1:
			newJoinType = .InnerJoin
			
		default:
			newJoinType = .LeftJoin
		}
		
		let s = self.step.joinType
		if s != newJoinType {
			self.step.joinType = newJoinType
			delegate?.configurableView(self, didChangeConfigurationFor: step)
			updateView()
		}
	}
	
	@IBAction func updateFromSimpleView(sender: NSObject) {
		if isSimple {
			simpleSibling = Column(siblingComboBox.stringValue)
			simpleForeign = Column(foreignComboBox.stringValue)
			delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
		updateView()
	}
	
	@IBAction func updateFromComplexView(sender: NSObject) {
		// Set formula
		let oldFormula = step.condition?.toFormula(self.delegate?.locale ?? Locale(), topLevel: true) ?? ""
		if let f = self.formulaField?.stringValue {
			if f != oldFormula {
				if let parsed = Formula(formula: f, locale: (self.delegate?.locale ?? Locale()))?.root {
					step.condition = parsed
					delegate?.configurableView(self, didChangeConfigurationFor: step)
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
	
	override func viewWillDisappear() {
		self.foreignComboBox.dataSource = nil
		self.siblingComboBox.dataSource = nil
		self.foreignComboBox.delegate = nil
		self.siblingComboBox.delegate = nil
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
}