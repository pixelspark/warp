import Cocoa

protocol QBEDataViewDelegate: NSObjectProtocol {
	// Returns true if the delegate has handled the change (e.g. converted it to a strutural one)
	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool
}

class QBEDataViewController: NSViewController, MBTableGridDataSource, MBTableGridDelegate {
	@IBOutlet var tableView: MBTableGrid?
	@IBOutlet var formulaField: NSTextField?
	weak var delegate: QBEDataViewDelegate!
	var locale: QBELocale!
	
	var raster: QBERaster? {
		didSet {
			updateColumns()
		}
	}
	
	var data: QBEData? {
		didSet {
			self.raster = nil
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				self.raster = self.data?.raster()
			})
		}
	}
	
	func update() {
		updateColumns()
	}
	
	func numberOfColumnsInTableGrid(aTableGrid: MBTableGrid!) -> UInt {
		if let r = raster {
			return r.columnCount > 0 ? UInt(r.columnCount) : 0
		}
		return 0
	}
	
	func numberOfRowsInTableGrid(aTableGrid: MBTableGrid!) -> UInt {
		if let r = raster {
			return r.rowCount > 0 ? UInt(r.rowCount) : 0
		}
		return 0
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, shouldEditColumn columnIndex: UInt, row rowIndex: UInt) -> Bool {
		//return !(raster?.readOnly ?? true)
		return true
	}
	
	private func setValue(value: QBEValue, inRow: Int, inColumn: Int) {
		if let r = raster {
			let oldValue = r[Int(inRow), Int(inColumn)]
			if !delegate.dataView(self, didChangeValue: oldValue, toValue: value, inRow: Int(inRow), column: Int(inColumn)) {
				if r.readOnly {
					// When raster is read-only, only structural changes are allowed
				}
				else {
					// The raster can be changed directly (it is source data), so change it
					if(inColumn>0) {
						//raster!.setValue(valueObject, forColumn: r.columnNames[Int(columnIndex)], inRow: Int(rowIndex))
					}
				}
			}
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, setObjectValue anObject: AnyObject?, forColumn columnIndex: UInt, row rowIndex: UInt) {
		let valueObject = anObject==nil ? QBEValue("") : QBEValue(anObject!.description)
		setValue(valueObject, inRow: Int(rowIndex), inColumn: Int(columnIndex))
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, objectValueForColumn columnIndex: UInt, row rowIndex: UInt) -> AnyObject! {
		if let r = raster {
			if columnIndex>=0 {
				let x = r[Int(rowIndex), Int(columnIndex)]
				return x.explain(locale)
			}
		}
		return ""
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, headerStringForColumn columnIndex: UInt) -> String! {
		if let d = data {
			if(Int(columnIndex) >= d.columnNames.count) {
				return "";
			}
			
			return d.columnNames[Int(columnIndex)].name;
		}
		return "c\(columnIndex)";
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, withForColumn columnIndex: UInt) -> Float {
		return 100.0
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, headerStringForRow rowIndex: UInt) -> String! {
		return "\(rowIndex)";
	}
	
	private func updateColumns() {
		if let tv = tableView {
			for i in 0...tv.numberOfColumns {
				tv.resizeColumnWithIndex(i, withDistance: 0.0)
			}
			
			tv.reloadData()
			updateFormulaField()
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, setWidthForColumn columnIndex: UInt) -> Float {
		return 60.0
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		return false
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, backgroundColorForColumn columnIndex: UInt, row rowIndex: UInt) -> NSColor! {
		let cols = NSColor.controlAlternatingRowBackgroundColors()
		return (cols[Int(rowIndex) % cols.count] as? NSColor)!
	}
	
	private func updateFormulaField() {
		let selectedRows = tableView!.selectedRowIndexes
		let selectedCols = tableView!.selectedColumnIndexes
		
		if selectedRows?.count > 1 || selectedCols?.count > 1 {
			formulaField?.enabled = false
			formulaField?.stringValue = ""
			formulaField?.placeholderString = "\(selectedRows?.count ?? 0)x\(selectedCols?.count ?? 0)"
		}
		else {
			formulaField?.enabled = true
			formulaField?.placeholderString = ""
			
			if let r = raster {
				let rowIndex = selectedRows!.firstIndex
				let colIndex = selectedCols!.firstIndex
				if rowIndex >= 0 && colIndex >= 0 && rowIndex < r.rowCount && colIndex < r.columnCount {
					let x = r[rowIndex, colIndex]
					formulaField?.stringValue = x.stringValue ?? ""
				}
				else {
					formulaField?.enabled = false
					formulaField?.stringValue = ""
				}
			}
			else {
				formulaField?.enabled = false
				formulaField?.stringValue = ""
			}
		}
	}
	
	@IBAction func setValueFromFormulaField(sender: NSObject) {
		if let selectedRows = tableView?.selectedRowIndexes {
			if let selectedColumns = tableView?.selectedColumnIndexes {
				setValue(QBEValue(formulaField!.stringValue), inRow: selectedRows.firstIndex, inColumn: selectedColumns.firstIndex)
			}
		}
	}
	
	func tableGridDidChangeSelection(aNotification: NSNotification!) {
		updateFormulaField()
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, canMoveColumns columnIndexes: NSIndexSet!, toIndex index: UInt) -> Bool {
		return true
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, moveColumns columnIndexes: NSIndexSet!, toIndex index: UInt) -> Bool {
		println("move \(columnIndexes) toIndex: \(index)")
		return true
	}
	
	override func awakeFromNib() {
		self.view.focusRingType = NSFocusRingType.None
		if self.tableView == nil {
			self.tableView = MBTableGrid(frame: view.frame)
			self.tableView!.focusRingType = NSFocusRingType.None
			self.tableView!.translatesAutoresizingMaskIntoConstraints = false
			self.tableView!.setContentHuggingPriority(1, forOrientation: NSLayoutConstraintOrientation.Horizontal)
			self.tableView!.setContentHuggingPriority(1, forOrientation: NSLayoutConstraintOrientation.Vertical)
			self.view.addSubview(tableView!)
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.formulaField, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 5.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Right, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Right, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0.0));
			
			for v in self.tableView!.subviews {
				if let vw = v as? NSView {
					vw.focusRingType = NSFocusRingType.None
				}
			}
		}
		super.awakeFromNib()
	}
	
	override func viewWillAppear() {
		self.tableView?.dataSource = self
		self.tableView?.delegate = self
		self.tableView?.reloadData()
		super.viewWillAppear()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}
}
