import Cocoa
import MapKit
import WarpCore

class QBEMapAnnotation: NSObject, MKAnnotation {
	let coordinate: CLLocationCoordinate2D
	let title: String?
	let subtitle: String?

	init?(row: Row, map: QBEMap, locale: Language) {
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

			if let value = row[col] {
				description += "\(col.name): \(locale.localStringFor(value))\r\n"
			}
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
	private var presentedDatasetIsFullDataset = false
	private var mapTablet: QBEMapTablet? { return self.tablet as? QBEMapTablet }
	private var useFullDataset: Bool = false
	private var calculator = QBECalculator()

	private func updateMap(_ animated: Bool) {
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
		NotificationCenter.default.addObserver(self, selector: #selector(QBEMapTabletViewController.resultNotificationReceived(_:)), name: NSNotification.Name(rawValue: QBEResultNotification.name), object: nil)
	}

	@objc private func resultNotificationReceived(_ notification: Notification) {
		assertMainThread()

		if let calculationNotification = notification.object as? QBEResultNotification where calculationNotification.calculator != calculator {
			if let t = self.mapTablet, let source = t.sourceTablet, let step = source.chain.head {
				if step == calculationNotification.step {
					self.presentedRaster = calculationNotification.raster
					self.presentedDatasetIsFullDataset = calculationNotification.isFull
					self.calculator.cancel()
					self.updateProgress()
					self.updateMap(false)
				}
			}
		}
	}

	override func viewWillDisappear() {
		NotificationCenter.default.removeObserver(self)
	}

	func job(_ job: AnyObject, didProgress: Double) {
		asyncMain {
			self.progressView.doubleValue = (job as! Job).progress * 100.0
			self.progressView.isIndeterminate = false
		}
	}

	private func updateProgress() {
		asyncMain {
			if self.calculator.calculating {
				if self.progressView.isHidden {
					self.progressView.isIndeterminate = true
					self.progressView.startAnimation(nil)
				}
				self.progressView.isHidden = false

			}
			else {
				self.progressView.stopAnimation(nil)
				self.progressView.doubleValue = 0.0
				self.progressView.isHidden = true
			}
		}
	}

	func sentenceView(_ view: QBESentenceViewController, didChangeConfigurable: QBEConfigurable) {
		self.updateMap(true)
	}

	var locale: Language {
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
			self.calculator.calculate(step, fullDataset: self.useFullDataset)
			let job = Job(.userInitiated)
			job.addObserver(self)

			self.calculator.currentRaster?.get(job) { result in
				switch result {
				case .success(let raster):
					asyncMain {
						self.presentedRaster = raster
						self.presentedDatasetIsFullDataset = self.useFullDataset
						self.updateProgress()
						self.updateMap(true)
					}

				case .failure(let e):
					/// FIXME show failure
					self.updateProgress()
					print("Failed to rasterize: \(e)")
				}
			}
		}
	}

	@IBAction func exportFile(_ sender: NSObject) {
		if let w = self.view.window {
			let panel = NSSavePanel()
			panel.allowedFileTypes = ["png"]
			panel.beginSheetModal(for: w) { (result) -> Void in
				if result == NSFileHandlingPanelOKButton {
					if let url = panel.url {
						let opts = MKMapSnapshotOptions()
						opts.region = self.mapView.region
						opts.mapType = MKMapType.standard
						opts.size = self.tablet.frame?.size ?? CGSize(width: 1024, height: 768)

						let snapshotter = MKMapSnapshotter(options: opts)
						snapshotter.start(completionHandler: { (snapshot, err) in
							if let e = err {
								NSAlert.showSimpleAlert("Could save a snapshot of this map".localized, infoText: e.localizedDescription, style: .critical, window: w)
							}

							if let s = snapshot {
								// Draw annotations
								let pin = MKPinAnnotationView(annotation: nil, reuseIdentifier: "")
								let pinCenterOffset = pin.centerOffset

								if let pinImage = pin.image {
									s.image.lockFocus()

									for annotation in self.mapView.annotations {
										var point = s.point(for: annotation.coordinate)
										point.x -= pin.bounds.size.width / 2.0
										point.y -= pin.bounds.size.height / 2.0
										point.x += pinCenterOffset.x
										point.y -= pinCenterOffset.y
										pinImage.draw(at: point, from: NSZeroRect, operation: NSCompositingOperation.sourceOver, fraction: 1.0)
									}

									let rep = NSBitmapImageRep(focusedViewRect: NSMakeRect(0, 0, s.image.size.width, s.image.size.height))
									s.image.unlockFocus()
									if let data = rep?.representation(using: .PNG, properties: [:]) {
										if !((try? data.write(to: url, options: [.atomic])) != nil) {
											NSAlert.showSimpleAlert("Could save a snapshot of this map".localized, infoText: "", style: .critical, window: w)
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

	@IBAction func cancelCalculation(_ sender: NSObject) {
		self.calculator.cancel()
		self.updateProgress()
	}

	@IBAction func toggleFullDataset(_ sender: NSObject) {
		useFullDataset = !(useFullDataset || presentedDatasetIsFullDataset)
		self.reloadData()
		self.view.window?.update()
	}

	@IBAction func toggleEditing(_ sender: NSObject) {
	}

	override func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.action == #selector(QBEChartTabletViewController.toggleFullDataset(_:)) {
			if let c = item.view as? NSButton {
				c.state = (useFullDataset || presentedDatasetIsFullDataset) ? NSOnState: NSOffState
			}
		}
		else if item.action == #selector(QBEChartTabletViewController.toggleEditing(_:)) {
			if let c = item.view as? NSButton {
				c.state = NSOffState
			}
		}

		return validateSelector(item.action!)
	}

	func validate(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return self.validateUserInterfaceItem(item)
	}

	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return validateSelector(item.action!)
	}

	private func validateSelector(_ action: Selector) -> Bool {
		if self.mapTablet?.sourceTablet?.chain.head != nil {
			switch action {
			case #selector(QBEChartTabletViewController.refreshDataset(_:)), #selector(QBEChartTabletViewController.exportFile(_:)): return true
			case #selector(QBEChartTabletViewController.cancelCalculation(_:)): return self.calculator.calculating
			case #selector(QBEChartTabletViewController.toggleFullDataset(_:)): return true
			default: return false
			}
		}
		return false
	}
}
