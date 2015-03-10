import Cocoa

protocol QBEDataViewDelegate: NSObjectProtocol {
	// Returns true if the delegate has handled the change (e.g. converted it to a strutural one)
	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool
}

class QBEDataViewController: NSViewController, MBTableGridDataSource, MBTableGridDelegate {
	var tableView: MBTableGrid?
	@IBOutlet var progressView: NSProgressIndicator!
	@IBOutlet var formulaField: NSTextField?
	@IBOutlet var workingSetSelector: NSSegmentedControl!
	weak var delegate: QBEDataViewDelegate?
	var locale: QBELocale!
	private var columnWidths: [QBEColumn: Float] = [:]
	
	var calculating: Bool = false { didSet {
		update()
	} }
	
	var progress: Double = 0.0 { didSet {
		update()
	} }
	
	var raster: QBERaster? {
		didSet {
			if raster != nil {
				calculating = false
			}
			update()
		}
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
		return delegate != nil
	}
	
	private func setValue(value: QBEValue, inRow: Int, inColumn: Int) {
		if let r = raster {
			let oldValue = r[Int(inRow), Int(inColumn)]
			if let d = delegate {
				if !d.dataView(self, didChangeValue: oldValue, toValue: value, inRow: Int(inRow), column: Int(inColumn)) {
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
		if(Int(columnIndex) >= raster?.columnNames.count) {
			return "";
		}
		
		return raster?.columnNames[Int(columnIndex)].name;
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, widthForColumn columnIndex: UInt) -> Float {
		if let r = raster {
			if Int(columnIndex) < r.columnNames.count {
				let cn = r.columnNames[Int(columnIndex)]
				if let w = columnWidths[cn] {
					return w
				}
			}
		}
		return 160.0
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, setWidth width: Float, forColumn columnIndex: UInt) -> Float {
		if let r = raster {
			if Int(columnIndex) < r.columnNames.count {
				let cn = r.columnNames[Int(columnIndex)]
				columnWidths[cn] = width
			}
		}
		return width
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, headerStringForRow rowIndex: UInt) -> String! {
		return "\(rowIndex+1)";
	}
	
	private func update() {
		// Set visibility
		let hasNoData = (raster==nil)
		
		tableView?.layer?.opacity = (hasNoData || calculating) ? 0.5 : 1.0;
		progressView?.hidden = !calculating
		formulaField?.enabled = !hasNoData
		workingSetSelector?.enabled = !hasNoData || calculating
		progressView?.indeterminate = progress <= 0.0
		progressView?.doubleValue = progress
		progressView?.minValue = 0.0
		progressView?.maxValue = 1.0
		progressView?.layer?.zPosition = 2.0
		
		if calculating {
			progressView?.startAnimation(nil)
		}
		else {
			progressView?.stopAnimation(nil)
		}
		
		if let tv = tableView {
			for i in 0...tv.numberOfColumns {
				tv.resizeColumnWithIndex(i, width: self.tableGrid(tv, widthForColumn: i))
			}
			
			tv.reloadData()
			updateFormulaField()
		}
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		return false
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, backgroundColorForColumn columnIndex: UInt, row rowIndex: UInt) -> NSColor! {
		let cols = NSColor.controlAlternatingRowBackgroundColors()
		return cols[0] as! NSColor
		//return (cols[Int(rowIndex) % cols.count] as? NSColor)!
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
		assert(locale != nil, "Need to set a locale to this data view before showing it")
		self.tableView?.dataSource = self
		self.tableView?.delegate = self
		self.tableView?.reloadData()
		super.viewWillAppear()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}
}
