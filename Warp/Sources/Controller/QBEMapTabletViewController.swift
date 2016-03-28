import Cocoa
import MapKit
import WarpCore

class QBEMapAnnotation: NSObject, MKAnnotation {
	let coordinate: CLLocationCoordinate2D
	let title: String?
	let subtitle: String?

	init?(row: Row, map: QBEMap, locale: Locale) {
		if row.columns.count < 2 {
			return nil
		}

		guard let latitude = map.latitudeExpression.apply(row, foreign: nil, inputValue: nil).doubleValue else { return nil }
		guard let longitude = map.longitudeExpression.apply(row, foreign: nil, inputValue: nil).doubleValue else {return nil }
		self.coordinate = CLLocationCoordinate2DMake(latitude, longitude)

		var description = ""

		for col in row.columns {
			if let latSibling = map.latitudeExpression as? Sibling where latSibling.column == col {
				continue
			}

			if let lngSibling = map.longitudeExpression as? Sibling where lngSibling.column == col {
				continue
			}

			if let titleSibling = map.titleExpression as? Sibling where titleSibling.column == col {
				continue
			}

			let value = row[col]
			description += "\(col.name): \(locale.localStringFor(value))\r\n"
		}

		let titleValue = map.titleExpression.apply(row, foreign: nil, inputValue: nil)
		self.title = locale.localStringFor(titleValue)
		self.subtitle = description
	}
}

class QBEMapTabletViewController: QBETabletViewController, MKMapViewDelegate,  QBESentenceViewDelegate, NSUserInterfaceValidations, JobDelegate   {
	@IBOutlet var progressView: NSProgressIndicator!
	@IBOutlet var mapView: MKMapView!

	private var presentedRaster: Raster? = nil
	private var updateJob: Job? = nil
	private var map: QBEMap? = nil
	private var presentedDataIsFullData = false
	private var mapTablet: QBEMapTablet? { return self.tablet as? QBEMapTablet }
	private var useFullData: Bool = false
	private var calculator = QBECalculator()

	private func updateMap(animated: Bool) {
		let zoomToFit = self.mapView.annotations.count == 0
		self.mapView.removeAnnotations(self.mapView.annotations)

		if let r = self.presentedRaster, let map = self.map {
			for row in r.rows {
				if let a = QBEMapAnnotation(row: row, map: map, locale: self.locale) {
					self.mapView.addAnnotation(a)
				}
			}
		}

		if zoomToFit {
			self.mapView.showAnnotations(self.mapView.annotations, animated: animated)
		}
	}

	override func tabletWasSelected() {
		self.delegate?.tabletView(self, didSelectConfigurable: self.map, configureNow: false, delegate: self)
	}

	override func viewWillAppear() {
		self.map = self.mapTablet?.map
		self.reloadData()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(QBEMapTabletViewController.resultNotificationReceived(_:)), name: QBEResultNotification.name, object: nil)
	}

	@objc private func resultNotificationReceived(notification: NSNotification) {
		assertMainThread()

		if let calculationNotification = notification.object as? QBEResultNotification where calculationNotification.calculator != calculator {
			if let t = self.mapTablet, let source = t.sourceTablet, let step = source.chain.head {
				if step == calculationNotification.step {
					self.presentedRaster = calculationNotification.raster
					self.presentedDataIsFullData = calculationNotification.isFull
					self.calculator.cancel()
					self.updateProgress()
					self.updateMap(false)
				}
			}
		}
	}

	override func viewWillDisappear() {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func job(job: AnyObject, didProgress: Double) {
		asyncMain {
			self.progressView.doubleValue = (job as! Job).progress * 100.0
			self.progressView.indeterminate = false
		}
	}

	private func updateProgress() {
		asyncMain {
			if self.calculator.calculating {
				if self.progressView.hidden {
					self.progressView.indeterminate = true
					self.progressView.startAnimation(nil)
				}
				self.progressView.hidden = false

			}
			else {
				self.progressView.stopAnimation(nil)
				self.progressView.doubleValue = 0.0
				self.progressView.hidden = true
			}
		}
	}

	func sentenceView(view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable) {
		self.updateMap(true)
	}

	var locale: Locale {
		return QBEAppDelegate.sharedInstance.locale
	}

	/** Loads the required raster data fresh from the data source, and repaints the chart. */
	private func reloadData() {
		asyncMain {
			self.presentedRaster = nil
			self.updateMap(false)
		}

		self.calculator.cancel()
		self.updateProgress()

		if let t = self.mapTablet, let source = t.sourceTablet, let step = source.chain.head {
			self.calculator.calculate(step, fullData: self.useFullData)
			let job = Job(.UserInitiated)
			job.addObserver(self)

			self.calculator.currentRaster?.get(job) { result in
				switch result {
				case .Success(let raster):
					asyncMain {
						self.presentedRaster = raster
						self.presentedDataIsFullData = self.useFullData
						self.updateProgress()
						self.updateMap(true)
					}

				case .Failure(let e):
					/// FIXME show failure
					self.updateProgress()
					print("Failed to rasterize: \(e)")
				}
			}
		}
	}

	@IBAction func exportFile(sender: NSObject) {
		if let w = self.view.window {
			let panel = NSSavePanel()
			panel.allowedFileTypes = ["png"]
			panel.beginSheetModalForWindow(w) { (result) -> Void in
				if result == NSFileHandlingPanelOKButton {
					if let url = panel.URL {
						let opts = MKMapSnapshotOptions()
						opts.region = self.mapView.region
						opts.mapType = MKMapType.Standard
						opts.size = self.tablet.frame?.size ?? CGSizeMake(1024, 768)

						let snapshotter = MKMapSnapshotter(options: opts)
						snapshotter.startWithCompletionHandler({ (snapshot, err) in
							if let e = err {
								NSAlert.showSimpleAlert("Could save a snapshot of this map".localized, infoText: e.localizedDescription, style: .CriticalAlertStyle, window: w)
							}

							if let s = snapshot {
								// Draw annotations
								let pin = MKPinAnnotationView(annotation: nil, reuseIdentifier: "")
								let pinCenterOffset = pin.centerOffset

								if let pinImage = pin.image {
									s.image.lockFocus()

									for annotation in self.mapView.annotations {
										var point = s.pointForCoordinate(annotation.coordinate)
										point.x -= pin.bounds.size.width / 2.0
										point.y -= pin.bounds.size.height / 2.0
										point.x += pinCenterOffset.x
										point.y -= pinCenterOffset.y
										pinImage.drawAtPoint(point, fromRect: NSZeroRect, operation: NSCompositingOperation.CompositeSourceOver, fraction: 1.0)
									}

									let rep = NSBitmapImageRep(focusedViewRect: NSMakeRect(0, 0, s.image.size.width, s.image.size.height))
									s.image.unlockFocus()
									if let data = rep?.representationUsingType(.NSPNGFileType, properties: [:]) {
										if !data.writeToURL(url, atomically: true) {
											NSAlert.showSimpleAlert("Could save a snapshot of this map".localized, infoText: "", style: .CriticalAlertStyle, window: w)
										}
									}
								}
							}
						})

					}
				}
			}
		}
	}

	@IBAction func cancelCalculation(sender: NSObject) {
		self.calculator.cancel()
		self.updateProgress()
	}

	@IBAction func toggleFullData(sender: NSObject) {
		useFullData = !(useFullData || presentedDataIsFullData)
		self.reloadData()
		self.view.window?.update()
	}

	@IBAction func toggleEditing(sender: NSObject) {
	}

	override func validateToolbarItem(item: NSToolbarItem) -> Bool {
		if item.action == #selector(QBEChartTabletViewController.toggleFullData(_:)) {
			if let c = item.view as? NSButton {
				c.state = (useFullData || presentedDataIsFullData) ? NSOnState: NSOffState
			}
		}
		else if item.action == #selector(QBEChartTabletViewController.toggleEditing(_:)) {
			if let c = item.view as? NSButton {
				c.state = NSOffState
			}
		}

		return validateSelector(item.action)
	}

	func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
		return validateSelector(anItem.action())
	}

	private func validateSelector(action: Selector) -> Bool {
		if self.mapTablet?.sourceTablet?.chain.head != nil {
			switch action {
			case #selector(QBEChartTabletViewController.refreshData(_:)), #selector(QBEChartTabletViewController.exportFile(_:)): return true
			case #selector(QBEChartTabletViewController.cancelCalculation(_:)): return self.calculator.calculating
			case #selector(QBEChartTabletViewController.toggleFullData(_:)): return true
			default: return false
			}
		}
		return false
	}
}