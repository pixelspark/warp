import Cocoa

protocol QBEDataViewDelegate: NSObjectProtocol {
	// Returns true if the delegate has handled the change (e.g. converted it to a strutural one)
	func dataView(view: QBEDataViewController, didChangeValue: QBEValue, toValue: QBEValue, inRow: Int, column: Int) -> Bool
}

class QBEDataViewController: NSViewController, MBTableGridDataSource, MBTableGridDelegate {
	@IBOutlet var tableView: MBTableGrid?
	weak var delegate: QBEDataViewDelegate!
	
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
	
	func tableGrid(aTableGrid: MBTableGrid!, setObjectValue anObject: AnyObject?, forColumn columnIndex: UInt, row rowIndex: UInt) {
		let valueObject = anObject==nil ? QBEValue("") : QBEValue(anObject!.description)
		
		if let r = raster {
			let oldValue = r[Int(rowIndex), Int(columnIndex)]
			if !delegate.dataView(self, didChangeValue: oldValue, toValue: valueObject, inRow: Int(rowIndex), column: Int(columnIndex)) {
				if r.readOnly {
					// When raster is read-only, only structural changes are allowed
				}
				else {
					// The raster can be changed directly (it is source data), so change it
					if(columnIndex>0) {
						//raster!.setValue(valueObject, forColumn: r.columnNames[Int(columnIndex)], inRow: Int(rowIndex))
					}
				}
			}
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, objectValueForColumn columnIndex: UInt, row rowIndex: UInt) -> AnyObject! {
		if let r = raster {
			if columnIndex>=0 {
				let x = r[Int(rowIndex), Int(columnIndex)]
				return x.description
			}
		}
		return ""
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, headerStringForColumn columnIndex: UInt) -> String! {
		if let d = data {
			if(Int(columnIndex) >= d.columnNames.count) {
				return "";
			}
			
			return d.columnNames[Int(columnIndex)];
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
		}
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, setWidthForColumn columnIndex: UInt) -> Float {
		return 60.0
	}
	
	func validateUserInterfaceItem(item: NSValidatedUserInterfaceItem) -> Bool {
		return false
	}
	
	func tableGrid(aTableGrid: MBTableGrid!, backgroundColorForColumn columnIndex: UInt, row rowIndex: UInt) -> NSColor! {
		return NSColor.whiteColor()
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
			self.view.addConstraint(NSLayoutConstraint(item: self.tableView!, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.view, attribute: NSLayoutAttribute.Top, multiplier: 1.0, constant: 0.0));
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
