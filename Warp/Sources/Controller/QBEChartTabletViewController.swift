import Cocoa
import Charts
import WarpCore

class QBEChartTabletViewController: QBETabletViewController, QBESentenceViewDelegate, NSUserInterfaceValidations, JobDelegate {
	@IBOutlet var chartView: NSView!
	@IBOutlet var progressView: NSProgressIndicator!
	private var chartBaseView: ChartViewBase? = nil
	private var chartTablet: QBEChartTablet? { return self.tablet as? QBEChartTablet }
	private var presentedRaster: Raster? = nil
	private var presentedDatasetIsFullDataset: Bool = false
	private var useFullDataset: Bool = false
	private var calculator = QBECalculator(incremental: true)

	var chart: QBEChart? = nil { didSet {
		self.updateChart()
	} }

	override func tabletWasSelected() {
		self.delegate?.tabletView(self, didSelectConfigurable: self.chart, configureNow: false, delegate: self)
	}

	override func viewWillAppear() {
		self.chart = self.chartTablet?.chart
		self.reloadData()
		let name = Notification.Name(rawValue: QBEResultNotification.name)
		NotificationCenter.default.addObserver(self, selector: #selector(QBEChartTabletViewController.resultNotificationReceived(_:)), name: name, object: nil)
	}

	@objc private func resultNotificationReceived(_ notification: Notification) {
		assertMainThread()

		if let calculationNotification = notification.object as? QBEResultNotification, calculationNotification.calculator != calculator {
			if let t = self.chartTablet, let source = t.chart.sourceTablet, let step = source.chain.head {
				if step == calculationNotification.step {
					self.presentedRaster = calculationNotification.raster
					self.presentedDatasetIsFullDataset = calculationNotification.isFull
					self.calculator.cancel()
					self.updateProgress()
					self.updateChart(false)
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
		self.updateChart()
	}

	var locale: Language {
		return QBEAppDelegate.sharedInstance.locale
	}

	/** Loads the required raster data fresh from the data source, and repaints the chart. */
	private func reloadData() {
		asyncMain {
			self.presentedRaster = nil
			self.updateChart(false)
		}

		let job = Job(.userInitiated)
		job.addObserver(self)
		self.calculator.cancel()
		self.updateProgress()

		if let t = self.chartTablet, let source = t.chart.sourceTablet, let step = source.chain.head {
			self.calculator.calculate(step, fullDataset: self.useFullDataset, job: job) { _ in
				self.calculator.currentRaster?.get(job) { result in
					switch result {
					case .success(let raster):
						asyncMain {
							self.presentedRaster = raster
							self.presentedDatasetIsFullDataset = self.useFullDataset
							self.updateProgress()
							self.updateChart(true)
						}

					case .failure(let e):
						/// FIXME show failure
						self.updateProgress()
						print("Failed to rasterize: \(e)")
					}
				}
			}
		}
	}

	/** Repaint the chart based on the current data and parameters. Draws no chart in case we are still loading it. */
	private func updateChart(_ animated: Bool = false) {
		assertMainThread()

		// Fade any changes in smoothly
		let tr = CATransition()
		tr.duration = 0.3
		tr.type = kCATransitionFade
		tr.subtype = kCATransitionFromRight
		tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
		self.chartView.layer?.add(tr, forKey: kCATransition)

		// Remove existing chart views
		self.chartView.subviews.forEach { $0.removeFromSuperview() }

		// Chart color theme
		let colors = [
			(0, 55, 100),
			(187, 224, 227),
			(153, 204, 0),
			(236, 0, 0),
			(253, 104, 0),
			(77, 77, 77)
			].map { c in return NSUIColor(calibratedRed: c.0 / 255.0, green: c.1 / 255.0, blue: c.2 / 255.0, alpha: 1.0) }

		if let r = self.presentedRaster, let chart = self.chart {
			// Create chart view
			let xs = r.rows.map { chart.xExpression.apply($0, foreign: nil, inputValue: nil) }

			switch chart.type {
			case .Line:
				let lineChartView = LineChartView(frame: self.chartView.bounds)
				self.chartBaseView = lineChartView

				if r.columns.count >= 2 {
					let data = LineChartData(xVals: xs.map { return $0.doubleValue ?? Double.nan })

					// FIXME: add support for multiple series in QBEChart
					for ySeriesIndex in 1..<2 {
						let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.nan }
						let yse = ys.enumerated().map { idx, i in return ChartDataEntry(value: i, xIndex: idx) }

						let ds = LineChartDataSet(yVals: yse, label: r.columns[ySeriesIndex].name)
						ds.drawValuesEnabled = false
						ds.drawCirclesEnabled = false
						ds.colors = [colors[(ySeriesIndex - 1) % colors.count]]
						data.addDataSet(ds)
					}

					lineChartView.data = data
					lineChartView.gridBackgroundColor = NSUIColor.white
					lineChartView.doubleTapToZoomEnabled = false
					lineChartView.pinchZoomEnabled = false
				}

			case .Radar:
				let radarChartView = RadarChartView(frame: self.chartView.bounds)
				self.chartBaseView = radarChartView

				if r.columns.count >= 2 {
					let data = RadarChartData(xVals: xs.map { return $0.doubleValue ?? Double.nan })

					for ySeriesIndex in 1..<2 {
						let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.nan }
						let yse = ys.enumerated().map { idx, i in return ChartDataEntry(value: i, xIndex: idx) }

						let ds = RadarChartDataSet(yVals: yse, label: r.columns[ySeriesIndex].name)
						ds.drawValuesEnabled = false
						ds.colors = [colors[(ySeriesIndex - 1) % colors.count]]
						data.addDataSet(ds)
					}

					radarChartView.data = data
				}

			case .Bar:
				let barChartView = BarChartView(frame: self.chartView.bounds)
				self.chartBaseView = barChartView

				// Do any additional setup after loading the view.
				if r.columns.count >= 2 {
					let data = BarChartData(xVals: [1])

					let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.nan }

					for (idx, y) in ys.enumerated() {
						let yse = [BarChartDataEntry(value: y, xIndex: 0)]
						let ds = BarChartDataSet(yVals: yse, label: xs[idx].stringValue ?? "")
						ds.drawValuesEnabled = false
						ds.colors = [colors[idx % colors.count]]
						data.addDataSet(ds)
					}

					barChartView.data = data
					barChartView.gridBackgroundColor = NSUIColor.white
					barChartView.doubleTapToZoomEnabled = false
					barChartView.pinchZoomEnabled = false
				}

			case .Pie:
				let pieChartView = PieChartView(frame: self.chartView.bounds)
				self.chartBaseView = pieChartView

				// Do any additional setup after loading the view.
				let data = PieChartData(xVals: xs.map { return $0.stringValue })
				let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.nan }

				let yse = ys.map { ChartDataEntry(value: $0, xIndex: 0) }
				let ds = PieChartDataSet(yVals: yse, label: "Data")
				ds.drawValuesEnabled = true
				ds.colors = colors
				data.addDataSet(ds)

				let nf = NumberFormatter()
				nf.numberStyle = NumberFormatter.Style.decimal
				nf.maximumFractionDigits = 1
				data.setValueFormatter(nf)

				pieChartView.data = data
			}
		}
		else {
			self.chartBaseView = nil
		}

		// Present chart
		if let cb = self.chartBaseView {
			cb.translatesAutoresizingMaskIntoConstraints = false
			self.chartView.addSubview(cb)
			self.chartView.addConstraints([
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: self.chartView, attribute: NSLayoutAttribute.top, multiplier: 1.0, constant: 0.0),
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.bottom, relatedBy: NSLayoutRelation.equal, toItem: self.chartView, attribute: NSLayoutAttribute.bottom, multiplier: 1.0, constant: 0.0),
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.left, relatedBy: NSLayoutRelation.equal, toItem: self.chartView, attribute: NSLayoutAttribute.left, multiplier: 1.0, constant: 0.0),
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.right, relatedBy: NSLayoutRelation.equal, toItem: self.chartView, attribute: NSLayoutAttribute.right, multiplier: 1.0, constant: 0.0)
			])
			cb.canDrawConcurrently = true

			if animated {
				cb.animate(xAxisDuration: 1.0, yAxisDuration: 1.0)
			}
			cb.descriptionFont = NSUIFont.systemFont(ofSize: 12.0)
			cb.descriptionText = ""
		}
	}

	@IBAction func refreshDataset(_ sender: AnyObject) {
		self.reloadData()
	}

	@IBAction func exportFile(_ sender: NSObject) {
		if let w = self.view.window, let chartView = self.chartBaseView {
			let panel = NSSavePanel()
			panel.allowedFileTypes = ["png"]
			panel.beginSheetModal(for: w) { (result) -> Void in
				if result == NSFileHandlingPanelOKButton {
					if let path = panel.url?.path {
						do {
							if !(try chartView.saveToPath(path, format: .png, compressionQuality: 1.0)) {
								trace("saveToPath returned false")
							}
						}
						catch _ {
							trace("saveToPath failed")
						}
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

	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return validateSelector(item.action!)
	}

	private func validateSelector(_ action: Selector) -> Bool {
		if self.chartTablet?.chart.sourceTablet?.chain.head != nil {
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
