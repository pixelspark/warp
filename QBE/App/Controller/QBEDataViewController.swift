import Cocoa

protocol QBEDataViewDelegate: NSObjectProtocol {
	// Returns true if the delegate has handled the change (e.g. converted it to a strutural one)
	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool
	func dataView(view: QBEDataViewController, didOrderColumns: [QBEColumn], toIndex: Int) -> Bool
	func dataView(view: QBEDataViewController, didSelectValue: QBEValue, changeable: Bool)
	func dataView(view: QBEDataViewController, filterControllerForColumn: QBEColumn, callback: (NSViewController) -> ())
	func dataView(view: QBEDataViewController, hasFilterForColumn: QBEColumn) -> Bool
}

class QBEDataViewController: NSViewController, MBTableGridDataSource, MBTableGridDelegate {
	var tableView: MBTableGrid?
	@IBOutlet var fullDataIndicatorView: NSImageView!
	@IBOutlet var progressView: NSProgressIndicator!
	@IBOutlet var columnContextMenu: NSMenu!
	@IBOutlet var errorLabel: NSTextField!
	weak var delegate: QBEDataViewDelegate?
	var locale: QBELocale!
	private var textCell: MBTableGridCell!
	private var numberCell: MBTableGridCell!
	private let DefaultColumnWidth = 100.0
	
	deinit {
		self.tableView?.dataSource = nil
		self.tableView?.delegate = nil
	}
	
	var hasFullData: Bool = false { didSet {
		fullDataIndicatorView.hidden = !hasFullData
	} }
	
	var calculating: Bool = false { didSet {
		update()
	} }
	
	var progress: Double = 0.0 { didSet {
		updateProgress()
	} }
	
	// When an error message is set, no raster can be set (and vice-versa)
	var errorMessage: String? { didSet {
		if errorMessage != nil {
			raster = nil
		}
		update()
	} }
	
	var raster: QBERaster? {
		didSet {
			if raster != nil {
				errorMessage = nil
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
		if let r = raster where inRow < r.rowCount && inColumn < r.columnCount {
			let oldValue = r[Int(inRow), Int(inColumn)]
			if oldValue != value {
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
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, setObjectValue anObject: AnyObject?, forColumn columnIndex: UInt, row rowIndex: UInt) {
		let valueObject = anObject==nil ? QBEValue.EmptyValue : locale.valueForLocalString(anObject!.description)
		setValue(valueObject, inRow: Int(rowIndex), inColumn: Int(columnIndex))
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, objectValueForColumn columnIndex: UInt, row rowIndex: UInt) -> AnyObject! {
		if let r = raster {
			if columnIndex>=0 {
				let x = r[Int(rowIndex), Int(columnIndex)]
				return locale.localStringFor(x)
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
	
	func tableGrid(aTableGrid: MBTableGrid!, canMoveColumns columnIndexes: NSIndexSet!, toIndex index: UInt) -> Bool {
		return true
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, writeColumnsWithIndexes columnIndexes: NSIndexSet!, toPasteboard pboard: NSPasteboard!) -> Bool {
		return true
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, moveColumns columnIndexes: NSIndexSet!, toIndex index: UInt) -> Bool {
		if let r = raster {
			var columnsOrdered: [QBEColumn] = []
			for columnIndex in 0..<r.columnCount {
				if columnIndexes.containsIndex(columnIndex) {
					columnsOrdered.append(r.columnNames[columnIndex])
				}
			}
			
			return delegate?.dataView(self, didOrderColumns: columnsOrdered, toIndex: Int(index)) ?? false
		}

		return false
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, moveRows rowIndexes: NSIndexSet!, toIndex index: UInt) -> Bool {
		return true
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, writeRowsWithIndexes rowIndexes: NSIndexSet!, toPasteboard pboard: NSPasteboard!) -> Bool {
		return false
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, cellForColumn columnIndex: UInt) -> NSCell! {
		// Check the first row to see what kind of value is in this column
		if let r = raster where r.rowCount > 0 && r.columnCount > Int(columnIndex) {
			var prototypeValue = r[0, Int(columnIndex)]
			
			// Find the first non-invalid, non-empty value
			var row = 0
			while (!prototypeValue.isValid || prototypeValue.isEmpty) && row < r.rowCount {
				prototypeValue = r[row, Int(columnIndex)]
				row++
			}
			
			switch prototypeValue {
				case .IntValue(_):
					return numberCell
					
				case .DoubleValue(_):
					return numberCell
					
				default:
					return textCell
			}
		}
		
		return textCell
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, setWidth width: Float, forColumn columnIndex: UInt)  {
		if let r = raster {
			if Int(columnIndex) < r.columnNames.count {
				let cn = r.columnNames[Int(columnIndex)]
				let previousWidth = QBESettings.sharedInstance.defaultWidthForColumn(cn)
				
				if width != Float(self.DefaultColumnWidth) || (previousWidth != nil && previousWidth! > 0) {
					QBESettings.sharedInstance.setDefaultWidth(Double(width), forColumn: cn)
				}
			}
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, headerStringForRow rowIndex: UInt) -> String! {
		return "\(rowIndex+1)";
	}
	
	private func updateProgress() {
		// Set visibility
		let hasNoData = (raster==nil)
		
		errorLabel.hidden = calculating || errorMessage == nil
		errorLabel.stringValue = errorMessage ?? ""
		
		tableView?.hidden = errorMessage != nil
		tableView?.layer?.opacity = (hasNoData || calculating) ? 0.5 : 1.0;
		
		progressView?.hidden = !calculating
		progressView?.indeterminate = progress <= 0.0
		progressView?.doubleValue = progress
		progressView?.minValue = 0.0
		progressView?.maxValue = 1.0
		progressView?.layer?.zPosition = 2.0
		progressView.usesThreadedAnimation = false // This is to prevent lock-ups involving __psync_cvwait, NSViewHierarchyLock + NSCollectionView
		
		if calculating {
			progressView?.startAnimation(nil)
		}
		else {
			progressView?.stopAnimation(nil)
		}
	}
	
	private func update() {
		QBEAssertMainThread()
		updateFonts()
		updateProgress()
		
		if let tv = tableView {
			if let r = raster {
				for i in 0..<r.columnCount {
					let cn = r.columnNames[i]
					if let w = QBESettings.sharedInstance.defaultWidthForColumn(cn) where w > 0 {
						tv.resizeColumnWithIndex(UInt(i), width: Float(w))
					}
					else {
						tv.resizeColumnWithIndex(UInt(i), width: Float(self.DefaultColumnWidth))
					}
				}
				tv.reloadData()
			}

			tv.needsDisplay = true
		}
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action() == Selector("addColumnBeforeSelectedColumn:") ||
			item.action() == Selector("addColumnAfterSelectedColumn:") ||
			item.action() == Selector("removeSelectedColumn:") ||
			item.action() == Selector("keepSelectedColumn:") {
			return true
		}
		return false
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, footerCellForColumn columnIndex: UInt) -> NSCell! {
		if let r = raster where Int(columnIndex) < r.columnNames.count {
			let cn = r.columnNames[Int(columnIndex)]
			let filterCell = QBEFilterCell(raster: r, column: cn)
			filterCell.active = delegate?.dataView(self, hasFilterForColumn: cn) ?? false
			filterCell.selected = aTableGrid.selectedColumnIndexes.containsIndex(Int(columnIndex))
			return filterCell
		}
		return nil
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, footerCellClicked cell: NSCell!, forColumn columnIndex: UInt, withEvent theEvent: NSEvent!) {
		if let r = raster where Int(columnIndex) < r.columnNames.count {
			self.delegate?.dataView(self, filterControllerForColumn: r.columnNames[Int(columnIndex)]) { (viewFilterController) in
				let pv = NSPopover()
				pv.behavior = NSPopoverBehavior.Semitransient
				pv.contentViewController = viewFilterController
				
				let columnRect = aTableGrid.rectOfColumn(columnIndex)
				let footerHeight = aTableGrid.columnFooterView.frame.size.height
				let filterRect = CGRectMake(columnRect.origin.x, aTableGrid.frame.size.height - footerHeight, columnRect.size.width, footerHeight)
				pv.showRelativeToRect(filterRect, ofView: aTableGrid, preferredEdge: NSRectEdge.MaxY)
			}
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, backgroundColorForColumn columnIndex: UInt, row rowIndex: UInt) -> NSColor! {
		return NSColor.controlAlternatingRowBackgroundColors()[0]
		//return (cols[Int(rowIndex) % cols.count] as? NSColor)!
	}
	
	private func updateFormulaField() {
		let selectedRows = tableView!.selectedRowIndexes
		let selectedCols = tableView!.selectedColumnIndexes

		if selectedRows?.count > 1 || selectedCols?.count > 1 {
			delegate?.dataView(self, didSelectValue: QBEValue.InvalidValue, changeable: false)
		}
		else {
			if let r = raster {
				let rowIndex = selectedRows!.firstIndex
				let colIndex = selectedCols!.firstIndex
				if rowIndex >= 0 && colIndex >= 0 && rowIndex < r.rowCount && colIndex < r.columnCount {
					let x = r[rowIndex, colIndex]
					delegate?.dataView(self, didSelectValue: x, changeable: true)
				}
				else {
					delegate?.dataView(self, didSelectValue: QBEValue.InvalidValue, changeable: false)
				}
			}
			else {
				delegate?.dataView(self, didSelectValue: QBEValue.InvalidValue, changeable: false)
			}
		}
	}
	
	func changeSelectedValue(toValue: QBEValue) {
		if let selectedRows = tableView?.selectedRowIndexes {
			if let selectedColumns = tableView?.selectedColumnIndexes {
				setValue(toValue, inRow: selectedRows.firstIndex, inColumn: selectedColumns.firstIndex)
			}
		}
	}

	func tableGridDidChangeSelection(aNotification: NSNotification!) {
		updateFormulaField()
	}
	
	private func updateFonts() {
		let monospace = QBESettings.sharedInstance.monospaceFont
		let font = monospace ? NSFont.userFixedPitchFontOfSize(10.0) : NSFont.userFontOfSize(12.0)
		self.textCell.font = font
		self.numberCell.font = font
		if let tv = self.tableView {
			tv.rowHeaderView.headerCell?.labelFont = font
			tv.columnHeaderView.headerCell?.labelFont = font
		}
	}
	
	override func awakeFromNib() {
		self.textCell = MBTableGridCell(textCell: "")
		self.numberCell = MBTableGridCell(textCell: "")
		self.numberCell.alignment = NSTextAlignment.Right
		
		self.view.focusRingType = NSFocusRingType.None
		self.view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawPolicy.OnSetNeedsDisplay
		self.view.wantsLayer = true
		self.view.layer?.opaque = true
		
		if self.tableView == nil {
			self.tableView = MBTableGrid(frame: view.frame)
			self.tableView!.wantsLayer = true
			self.tableView!.layer?.opaque = true
			self.tableView!.layer?.drawsAsynchronously = true
			self.tableView!.layerContentsRedrawPolicy = NSViewLayerContentsRedrawPolicy.OnSetNeedsDisplay
			self.tableView!.focusRingType = NSFocusRingType.None
			self.tableView!.translatesAutoresizingMaskIntoConstraints = false
			self.tableView!.setContentHuggingPriority(1, forOrientation: NSLayoutConstraintOrientation.Horizontal)
			self.tableView!.setContentHuggingPriority(1, forOrientation: NSLayoutConstraintOrientation.Vertical)
			self.tableView!.awakeFromNib()
			self.tableView!.columnHeaderView.menu = self.columnContextMenu
			self.view.addSubview(tableView!)
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Top, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Right, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Right, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0.0));
			
			for vw in self.tableView!.subviews {
				vw.focusRingType = NSFocusRingType.None
			}
		}
		
		// Move the full data indicator on top of the table grid, which was only just added
		self.view.addSubview(self.fullDataIndicatorView)
		updateFonts()
		super.awakeFromNib()
	}
	
	override func viewWillAppear() {
		assert(locale != nil, "Need to set a locale to this data view before showing it")
		self.tableView?.dataSource = self
		self.tableView?.delegate = self
		self.tableView?.reloadData()
		super.viewWillAppear()
	}
	
	override func viewWillDisappear() {
		self.tableView?.dataSource = nil
		self.tableView?.delegate = nil
		super.viewWillDisappear()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, formatterForColumn columnIndex: UInt) -> NSFormatter! {
		return nil
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, copyCellsAtColumns columnIndexes: NSIndexSet!, rows rowIndexes: NSIndexSet!) {
		if let r = raster {
			var rowData: [String] = []
			
			rowIndexes.enumerateIndexesUsingBlock { (rowIndex, stop) -> Void in
				var colData: [String] = []
				columnIndexes.enumerateIndexesUsingBlock({ (colIndex, stop) -> Void in
					if let cellValue = r[rowIndex, colIndex].stringValue {
						// FIXME formatting
						colData.append(cellValue)
					}
					else {
						colData.append("")
					}
				})
				
				rowData.append(colData.implode("\t") ?? "")
			}
			
			let tsv = rowData.implode("\r\n") ?? ""
			let pasteboard = NSPasteboard.generalPasteboard()
			pasteboard.clearContents()
			pasteboard.declareTypes([NSPasteboardTypeTabularText, NSPasteboardTypeString], owner: nil)
			pasteboard.setString(tsv, forType: NSPasteboardTypeTabularText)
			pasteboard.setString(tsv, forType: NSPasteboardTypeString)
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, pasteCellsAtColumns columnIndexes: NSIndexSet!, rows rowIndexes: NSIndexSet!) {
		if let r = raster {
			let tsvString = NSPasteboard.generalPasteboard().stringForType(NSPasteboardTypeTabularText)
			
			var startRow = rowIndexes.firstIndex
			var startColumn = columnIndexes.firstIndex
			if startRow == NSNotFound {
				startRow = 0
			}
			if startColumn == NSNotFound {
				startColumn = 0
			}
			
			let rowCount = r.rowCount
			let columnCount = r.columnCount
			
			if let rowStrings = tsvString?.componentsSeparatedByString("\r\n") {
				var row = startRow
				if row < rowCount {
					for rowString in rowStrings {
						let cellStrings = rowString.componentsSeparatedByString("\t")
						var col = startColumn
						for cellString in cellStrings {
							if col < columnCount {
								setValue(QBEValue(cellString), inRow: row, inColumn: col)
							}
							col++
						}
						row++
					}
				}
			}
		}
	}
}