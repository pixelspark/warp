import Cocoa
import WarpCore

protocol QBEDatasetViewDelegate: NSObjectProtocol {
	// Returns true if the delegate has handled the change (e.g. converted it to a strutural one)
	@discardableResult func dataView(_ view: QBEDatasetViewController, didChangeValue: Value, toValue: Value, inRow: Int, column: Int) -> Bool
	@discardableResult func dataView(_ view: QBEDatasetViewController, didOrderColumns: [Column], toIndex: Int) -> Bool
	func dataView(_ view: QBEDatasetViewController, didSelectValue: Value, changeable: Bool)
	func dataView(_ view: QBEDatasetViewController, viewControllerForColumn: Column, info: Bool, callback: (NSViewController) -> ())
	func dataView(_ view: QBEDatasetViewController, addValue: Value, inRow: Int?, column: Int?, callback: (Bool) -> ())
	func dataView(_ view: QBEDatasetViewController, hasFilterForColumn: Column) -> Bool
	func dataView(_ view: QBEDatasetViewController, didRenameColumn: Column, to: Column)
}

extension NSFont {
	func sizeOfString(_ string: String) -> NSSize {
		let s = NSString(string: string)
		return s.size(withAttributes: [NSFontAttributeName: self])
	}
}

private class QBEValueCell: MBTableGridCell {
	var value: Value { didSet { self.objectValue = self.language.localStringFor(value) } }
	var language: Language

	init(language: Language, value: Value = .invalid) {
		self.value = value
		self.language = language
		super.init(textCell: "")

		let monospace = QBESettings.sharedInstance.monospaceFont
		self.font = monospace ? NSFont.userFixedPitchFont(ofSize: 9.0) : NSFont.userFont(ofSize: 11.0)
	}

	required init(coder: NSCoder) {
		fatalError("Do not call")
	}

	private override func encode(with aCoder: NSCoder) {
		fatalError("Do not call")
	}

	private override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
		switch value {
		case .int(_), .double(_):
			self.textColor = NSColor.black
			self.alignment = .right

		case .invalid:
			self.alignment = .center
			self.textColor = NSColor.red
			NSColor.red.withAlphaComponent(0.3).set()
			NSRectFill(cellFrame)

		case .empty:
			self.textColor = NSColor.black
			NSColor.black.withAlphaComponent(0.05).set()
			NSRectFill(cellFrame)

		case .bool(_):
			self.textColor = NSColor.blue
			self.alignment = .center

		default:
			self.textColor = NSColor.black
			self.alignment = .left
			break
		}

		super.draw(withFrame: cellFrame, in: controlView)
	}
}

/** A data view shows data in a Raster as a table. It can also show a progress bar to indicate loading progress, and has
footer cells that allow filtering of the data. */
class QBEDatasetViewController: NSViewController, MBTableGridDataSource, MBTableGridDelegate, NSUserInterfaceValidations {
	var tableView: MBTableGrid?
	@IBOutlet var columnContextMenu: NSMenu!
	@IBOutlet var errorLabel: NSTextField!
	weak var delegate: QBEDatasetViewDelegate?
	var locale: Language! { didSet { self.updateFonts() } }
	private let DefaultColumnWidth = 100.0
	private var footerCells: [UInt: QBEFilterCell] = [:] // Holds cached instances of footer cells
	private var columnsAutosized = false
	private var valueFont: NSFont! = nil
	private var valueCell: QBEValueCell!

	deinit {
		self.tableView?.dataSource = nil
		self.tableView?.delegate = nil
	}

	var showNewRow = false { didSet {
		assertMainThread()
		if showNewRow != oldValue {
			update()
		}
	} }

	var showNewColumn = false { didSet {
		assertMainThread()
		if showNewColumn != oldValue {
			update()
		}
	} }

	var showFooters: Bool = true {
		didSet {
			assertMainThread()

			if !showFooters {
				footerCells.forEach { $0.value.cancel() }
				footerCells.removeAll(keepingCapacity: true)

				if let fv = self.tableView?.columnFooterView {
					fv.setNeedsDisplay(fv.bounds)
				}
			}
		}
	}

	// When an error message is set, no raster can be set (and vice-versa)
	var errorMessage: String? { didSet {
		assertMainThread()
		if errorMessage != nil {
			raster = nil
		}
		update()
	} }
	
	var raster: Raster? {
		didSet {
			assertMainThread()
			footerCells.forEach { $0.value.cancel() }
			footerCells.removeAll(keepingCapacity: true)
			if raster != nil {
				errorMessage = nil
			}
			update()
		}
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, backgroundColorForColumn columnIndex: UInt, row rowIndex: UInt) -> NSColor! {
		return NSColor.clear
	}
	
	func numberOfColumns(in aTableGrid: MBTableGrid!) -> UInt {
		if let r = raster {
			return (r.columns.count > 0 ? UInt(r.columns.count) : 0) + (self.showNewColumn ? 1 : 0)
		}
		return (self.showNewColumn ? 1 : 0)
	}
	
	func numberOfRows(in aTableGrid: MBTableGrid!) -> UInt {
		if let r = raster {
			return (r.rowCount > 0 ? UInt(r.rowCount) : 0) + (self.showNewRow ? 1 : 0)
		}
		return (self.showNewRow ? 1 : 0)
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, shouldEditColumn columnIndex: UInt, row rowIndex: UInt) -> Bool {
		return delegate != nil
	}
	
	private func setValue(_ value: Value, inRow: Int, inColumn: Int) {
		if let r = raster {
			if inRow < r.rowCount && inColumn < r.columns.count {
				let oldValue = r[Int(inRow), Int(inColumn)]!
				if oldValue != value {
					if let d = delegate {
						d.dataView(self, didChangeValue: oldValue, toValue: value, inRow: Int(inRow), column: Int(inColumn))
					}
				}
			}
			else if inRow == r.rowCount && inColumn < r.columns.count && !value.isEmpty {
				// New row
				self.delegate?.dataView(self, addValue: value, inRow: nil, column: inColumn) { didAddRow in
				}
			}
			else if inRow < r.rowCount && inColumn == r.columns.count && !value.isEmpty {
				// New column
				self.delegate?.dataView(self, addValue: value, inRow: inRow, column: nil) { didAddColumn in
				}
			}
			else if inRow == r.rowCount && inColumn == r.columns.count && !value.isEmpty {
				// New row and column
				self.delegate?.dataView(self, addValue: value, inRow: nil, column: nil) { didAddColumn in
				}
			}
		}
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, setObjectValue anObject: AnyObject?, forColumn columnIndex: UInt, row rowIndex: UInt) {
		let valueObject = anObject==nil ? Value.empty : locale.valueForLocalString(anObject!.description)
		setValue(valueObject, inRow: Int(rowIndex), inColumn: Int(columnIndex))
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, cellForColumn columnIndex: UInt, row rowIndex: UInt) -> NSCell! {
		if let r = raster {
			if Int(columnIndex) == r.columns.count || Int(rowIndex) == r.rowCount {
				// Template row, return empty string
				self.valueCell.value = .empty
				return valueCell
			}
			else if columnIndex >= 0 && Int(columnIndex) < r.columns.count && rowIndex >= 0 && Int(rowIndex) < r.rowCount {
				let x = r[Int(rowIndex), Int(columnIndex)]!
				self.valueCell.value = x
				return self.valueCell
			}
		}
		return nil
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, objectValueForColumn columnIndex: UInt, row rowIndex: UInt) -> AnyObject? {
		if let r = raster {
			if Int(columnIndex) == r.columns.count || Int(rowIndex) == r.rowCount {
				// Template row, return empty string
				return ""
			}
			else if columnIndex >= 0 && Int(columnIndex) < r.columns.count && rowIndex >= 0 && Int(rowIndex) < r.rowCount {
				let x = r[Int(rowIndex), Int(columnIndex)]!
				return self.locale.localStringFor(x)
			}
		}
		return nil
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, headerStringForColumn columnIndex: UInt) -> String! {
		if Int(columnIndex) == raster?.columns.count {
			// Template column
			return "+"
		}
		else if Int(columnIndex) >= raster?.columns.count {
			// Out of range
			return ""
		}
		else {
			return raster?.columns[Int(columnIndex)].name
		}
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, canMoveColumns columnIndexes: IndexSet!, to index: UInt) -> Bool {
		// Make sure we are not dragging the template column, and not past the template column
		if let r = raster, !columnIndexes.contains(r.columns.count) && Int(index) < r.columns.count {
			return true
		}
		return false
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, writeColumnsWith columnIndexes: IndexSet!, to pboard: NSPasteboard!) -> Bool {
		return true
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, moveColumns columnIndexes: IndexSet!, to index: UInt) -> Bool {
		if let r = raster {
			var columnsOrdered: [Column] = []
			for columnIndex in 0..<r.columns.count {
				if columnIndexes.contains(columnIndex) {
					columnsOrdered.append(r.columns[columnIndex])
				}
			}
			
			return delegate?.dataView(self, didOrderColumns: columnsOrdered, toIndex: Int(index)) ?? false
		}

		return false
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, moveRows rowIndexes: IndexSet!, to index: UInt) -> Bool {
		return true
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, writeRowsWith rowIndexes: IndexSet!, to pboard: NSPasteboard!) -> Bool {
		return false
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, setWidth width: Float, forColumn columnIndex: UInt)  {
		if let r = raster {
			if Int(columnIndex) < r.columns.count {
				let cn = r.columns[Int(columnIndex)]
				let previousWidth = QBESettings.sharedInstance.defaultWidthForColumn(cn)
				
				if width != Float(self.DefaultColumnWidth) || (previousWidth != nil && previousWidth! > 0) {
					QBESettings.sharedInstance.setDefaultWidth(Double(width), forColumn: cn)
				}
			}
		}
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, headerStringForRow rowIndex: UInt) -> String! {
		if Int(rowIndex) == raster?.rowCount {
			return "+"
		}
		return "\(rowIndex+1)"
	}
	
	private func updateProgress() {
		assertMainThread()
		// Set visibility
		errorLabel.isHidden = errorMessage == nil
		errorLabel.stringValue = errorMessage ?? ""
		tableView?.isHidden = errorMessage != nil
	}
	
	private func update() {
		assertMainThread()
		
		if let tv = tableView {
			if !showNewRow {
				let tr = CATransition()
				tr.duration = 0.3
				tr.type = kCATransitionFade
				tr.subtype = kCATransitionFromBottom
				tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
				self.tableView?.layer?.add(tr, forKey: kCATransition)
			}

			updateFonts()
			updateProgress()

			if let r = raster {
				// Update column sizes
				for i in 0..<r.columns.count {
					let cn = r.columns[i]
					if let w = QBESettings.sharedInstance.defaultWidthForColumn(cn), w > 0 {
						tv.resizeColumn(with: UInt(i), width: Float(w))
					}
					else {
						tv.resizeColumn(with: UInt(i), width: Float(self.DefaultColumnWidth))
					}
				}

				// Force the 'new' column to a certain fixed size
				if self.showNewColumn {
					tv.resizeColumn(with: UInt(r.columns.count), width: Float(self.DefaultColumnWidth / 2.0))
				}
			}

			tv.reloadData()
			tv.singleClickCellEdit = self.showNewRow
			//tv.needsDisplay = true

			if !columnsAutosized && self.raster != nil {
				self.columnsAutosized = true
				self.sizeAllColumnsToFit()
			}
		}
	}

	func validate(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return self.validateUserInterfaceItem(item)
	}
	
	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		switch item.action {
		case .some(#selector(QBEDatasetViewController.sizeAllColumnsToFit(_:))),
			 .some(#selector(QBEDatasetViewController.sizeAllColumnsToDefault(_:))),
			 .some(#selector(QBEDatasetViewController.sizeAllColumnsToFitTable(_:))):
			return true

		case .some(#selector(QBEDatasetViewController.renameSelectedColumn(_:))),
			 .some(#selector(QBEDatasetViewController.sizeSelectedColumnToFit(_:))),
			 .some(#selector(QBEDatasetViewController.sizeSelectedColumnToDefault(_:))):
			if self.tableView?.selectedColumnIndexes.first != nil {
				return true
			}
			return false

		default:
			return false
		}
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, footerCellForColumn columnIndex: UInt) -> NSCell! {
		assertMainThread()

		if let r = raster, Int(columnIndex) >= 0 && Int(columnIndex) < r.columns.count {
			let cn = r.columns[Int(columnIndex)]

			if !self.showFooters {
				return QBEFilterPlaceholderCell()
			}

			// If we have a cached instance, use that
			let filterCell: QBEFilterCell
			if let fc = footerCells[columnIndex] {
				filterCell = fc
			}
			else {
				filterCell = QBEFilterCell(raster: r, column: cn)
				footerCells[columnIndex] = filterCell
			}

			filterCell.active = delegate?.dataView(self, hasFilterForColumn: cn) ?? false
			filterCell.selected = aTableGrid.selectedColumnIndexes.contains(Int(columnIndex))
			return filterCell
		}
		return nil
	}

	@IBAction func renameSelectedColumn(_ sender: NSObject) {
		if let si = self.tableView?.selectedColumnIndexes.first {
			self.renameColumnPopup(UInt(si))
		}
	}

	private func renameColumnPopup(_ columnIndex: UInt) {
		if let r = raster, Int(columnIndex) < r.columns.count {
			self.delegate?.dataView(self, viewControllerForColumn: r.columns[Int(columnIndex)], info: true, callback: { vc in
				if let rect = self.tableView?.headerRect(ofColumn: columnIndex) {
					self.presentViewController(vc, asPopoverRelativeTo: rect, of: self.tableView!, preferredEdge: NSRectEdge.minY, behavior: NSPopoverBehavior.transient)
				}
			})
		}
	}

	@IBAction func sizeSelectedColumnToFit(_ sender: NSObject) {
		if let tv = self.tableView {
			for idx in tv.selectedColumnIndexes {
				self.sizeColumnToFit(UInt(idx))
			}
		}
	}

	@IBAction func sizeSelectedColumnToDefault(_ sender: NSObject) {
		if let tv = self.tableView {
			for idx in tv.selectedColumnIndexes {
				tv.resizeColumn(with: UInt(idx), width: Float(DefaultColumnWidth))
				self.tableGrid(tv, setWidth: Float(DefaultColumnWidth), forColumn: UInt(idx))
			}
		}
	}

	@IBAction func sizeAllColumnsToDefault(_ sender: NSObject) {
		if let tv = self.tableView {
			for idx in 0..<tv.numberOfColumns {
				tv.resizeColumn(with: UInt(idx), width: Float(DefaultColumnWidth))
				self.tableGrid(tv, setWidth: Float(DefaultColumnWidth), forColumn: UInt(idx))
			}
		}
	}

	@IBAction func sizeAllColumnsToFitTable(_ sender: NSObject) {
		if let tv = self.tableView {
			let w = max(15.0, Double(tv.frame.size.width) / Double(tv.numberOfColumns))

			for idx in 0..<tv.numberOfColumns {
				tv.resizeColumn(with: UInt(idx), width: Float(w))
				self.tableGrid(tv, setWidth: Float(w), forColumn: UInt(idx))
			}
		}
	}

	func sizeColumnToFit(_ name: Column) {
		if let idx = self.raster?.indexOfColumnWithName(name) {
			self.sizeColumnToFit(UInt(idx))
		}
	}

	@IBAction func sizeAllColumnsToFit(_ sender: NSObject) {
		self.sizeAllColumnsToFit()
	}

	private func sizeColumnToFit(_ columnIndex: UInt) {
		let maxWidth: CGFloat = 250.0
		let maxRowsToConsider = 500

		if let tv = self.tableView {
			var w: CGFloat = 25.0 // minimum width
			let vr = tv.contentView().visibleRect
			let firstRow = max(0, tv.row(at: CGPoint(x: vr.origin.x + 3.0, y: vr.origin.y + 3.0)))
			let lastRow = min(firstRow + maxRowsToConsider, tv.row(at: CGPoint(x: 3.0 + vr.origin.x + vr.size.width, y: 3.0 + vr.origin.y + vr.size.height)))
			let font = self.valueFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize())

			if let r = raster {
				for rowNumber in firstRow...lastRow {

					if let v = r[rowNumber, Int(columnIndex)] {
						let stringValue = locale.localStringFor(v)
						w = max(w, font.sizeOfString(stringValue).width)
					}
				}
			}

			tv.resizeColumn(with: columnIndex, width: Float(min(maxWidth, w + 10.0)))
			self.tableGrid(tv, setWidth: Float(w), forColumn: columnIndex)
		}
	}

	private func sizeAllColumnsToFit() {
		if let tv = self.tableView {
			for cn in 0..<tv.numberOfColumns {
				self.sizeColumnToFit(cn)
			}
		}
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, didDoubleClickColumn columnIndex: UInt) {
		//self.sizeColumnToFit(columnIndex)
		self.renameColumnPopup(columnIndex)
	}

	func tableGrid(_ aTableGrid: MBTableGrid!, footerCellClicked cell: NSCell!, forColumn columnIndex: UInt, with theEvent: NSEvent!) {
		showFilterPopup(Int(columnIndex), atFooter: true)
	}

	private func showFilterPopup(_ columnIndex: Int, atFooter: Bool) {
		if let tv = self.tableView, let r = raster, columnIndex < r.columns.count {
			self.delegate?.dataView(self, viewControllerForColumn: r.columns[Int(columnIndex)], info: false) { viewFilterController in
				assertMainThread()
				let pv = NSPopover()
				pv.behavior = NSPopoverBehavior.semitransient
				pv.contentViewController = viewFilterController

				let columnRect = tv.rect(ofColumn: UInt(columnIndex))
				let footerHeight = tv.columnFooterView.frame.size.height
				let filterRect: CGRect
				if atFooter {
					filterRect = CGRect(x: columnRect.origin.x, y: tv.frame.size.height - footerHeight, width: columnRect.size.width, height: footerHeight)
				}
				else {
					filterRect = CGRect(x: columnRect.origin.x, y: 0, width: columnRect.size.width, height: footerHeight)
				}

				pv.show(relativeTo: filterRect, of: tv, preferredEdge: atFooter ? NSRectEdge.maxY : NSRectEdge.minY)
			}
		}
	}
	
	private func updateFormulaField() {
		let selectedRows = tableView!.selectedRowIndexes
		let selectedCols = tableView!.selectedColumnIndexes

		if selectedRows?.count > 1 || selectedCols?.count > 1 {
			delegate?.dataView(self, didSelectValue: Value.invalid, changeable: false)
		}
		else {
			if let r = raster, let sr = selectedRows {
				if let rowIndex = sr.first, let colIndex = sr.first {
					if rowIndex >= 0 && colIndex >= 0 && rowIndex < r.rowCount && colIndex < r.columns.count {
						let x = r[rowIndex, colIndex]!
						delegate?.dataView(self, didSelectValue: x, changeable: true)
					}
					else {
						delegate?.dataView(self, didSelectValue: Value.invalid, changeable: false)
					}
				}
			}
			else {
				delegate?.dataView(self, didSelectValue: Value.invalid, changeable: false)
			}
		}
	}
	
	func changeSelectedValue(_ toValue: Value) {
		if let selectedRows = tableView?.selectedRowIndexes, let first = selectedRows.first {
			if let selectedColumns = tableView?.selectedColumnIndexes, let firstColumn = selectedColumns.first {
				setValue(toValue, inRow: first, inColumn: firstColumn)
			}
		}
	}

	func tableGridDidChangeSelection(_ aNotification: Notification!) {
		updateFormulaField()
	}
	
	private func updateFonts() {
		let monospace = QBESettings.sharedInstance.monospaceFont
		self.valueFont = monospace ? NSFont.userFixedPitchFont(ofSize: 9.0) : NSFont.userFont(ofSize: 11.0)
		self.valueCell = QBEValueCell(language: self.locale ?? Language())

		if let tv = self.tableView {
			tv.rowHeaderView.headerCell?.textColor = NSColor.headerTextColor.withAlphaComponent(0.8)
			tv.columnHeaderView.headerCell?.textColor = NSColor.headerTextColor.withAlphaComponent(0.8)
			tv.rowHeaderView.headerCell?.labelFont = self.valueFont
			tv.columnHeaderView.headerCell?.labelFont = self.valueFont
			tv.contentView().rowHeight = monospace ? 16.0 : 18.0
		}
	}
	
	override func awakeFromNib() {
		self.view.focusRingType = NSFocusRingType.none
		self.view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawPolicy.onSetNeedsDisplay
		self.view.wantsLayer = true
		self.view.layer?.isOpaque = true
		
		if self.tableView == nil {
			self.tableView = MBTableGrid(frame: view.frame)
			self.tableView!.wantsLayer = true
			self.tableView!.layer?.isOpaque = true
			self.tableView!.layer?.drawsAsynchronously = true
			self.tableView!.layerContentsRedrawPolicy = NSViewLayerContentsRedrawPolicy.onSetNeedsDisplay
			self.tableView!.focusRingType = NSFocusRingType.none
			self.tableView!.translatesAutoresizingMaskIntoConstraints = false
			self.tableView!.setContentHuggingPriority(1, for: NSLayoutConstraintOrientation.horizontal)
			self.tableView!.setContentHuggingPriority(1, for: NSLayoutConstraintOrientation.vertical)
			self.tableView!.awakeFromNib()
			self.tableView?.register(forDraggedTypes: [])
			self.tableView!.columnHeaderView.menu = self.columnContextMenu
			self.view.addSubview(tableView!)
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.top, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.left, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.left, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.right, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.right, multiplier: 1.0, constant: 0.0));
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.bottom, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.bottom, multiplier: 1.0, constant: 0.0));
			
			for vw in self.tableView!.subviews {
				vw.focusRingType = NSFocusRingType.none
			}
		}
		
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
	
	func tableGrid(_ aTableGrid: MBTableGrid!, copyCellsAtColumns columnIndexes: IndexSet!, rows rowIndexes: IndexSet!) {
		if let r = raster {
			var rowDataset: [String] = []
			
			rowIndexes.enumerated().forEach { (rowIndex, stop) -> Void in
				var colDataset: [String] = []
				columnIndexes.enumerated().forEach { (colIndex, stop) -> Void in
					if let cellValue = r[rowIndex, colIndex].stringValue {
						// FIXME formatting
						colDataset.append(cellValue)
					}
					else {
						colDataset.append("")
					}
				}
				
				rowDataset.append(colDataset.joined(separator: "\t"))
			}
			
			let tsv = rowDataset.joined(separator: "\r\n")
			let pasteboard = NSPasteboard.general()
			pasteboard.clearContents()
			pasteboard.declareTypes([NSPasteboardTypeTabularText, NSPasteboardTypeString], owner: nil)
			pasteboard.setString(tsv, forType: NSPasteboardTypeTabularText)
			pasteboard.setString(tsv, forType: NSPasteboardTypeString)
		}
	}
	
	func tableGrid(_ aTableGrid: MBTableGrid!, pasteCellsAtColumns columnIndexes: IndexSet!, rows rowIndexes: IndexSet!) {
		if let r = raster {
			let tsvString = NSPasteboard.general().string(forType: NSPasteboardTypeTabularText)
			
			let startRow: Int = rowIndexes.first ?? 0
			let startColumn: Int = columnIndexes.first ?? 0
			
			let rowCount = r.rowCount
			let columnCount = r.columns.count
			
			if let rowStrings = tsvString?.components(separatedBy: "\r\n") {
				var row = startRow
				if row < rowCount {
					for rowString in rowStrings {
						let cellStrings = rowString.components(separatedBy: "\t")
						var col = startColumn
						for cellString in cellStrings {
							if col < columnCount {
								setValue(Value(cellString), inRow: row, inColumn: col)
							}
							col += 1
						}
						row += 1
					}
				}
			}
		}
	}
}
