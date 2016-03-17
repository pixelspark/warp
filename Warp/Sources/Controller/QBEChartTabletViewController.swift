import Cocoa
import Charts
import WarpCore

class QBEChartTabletViewController: QBETabletViewController, QBESentenceViewDelegate, NSUserInterfaceValidations, JobDelegate {
	@IBOutlet var chartView: NSView!
	@IBOutlet var progressView: NSProgressIndicator!
	private var chartBaseView: ChartViewBase? = nil
	private var chartTablet: QBEChartTablet? { return self.tablet as? QBEChartTablet }
	private var presentedRaster: Raster? = nil
	private var presentedDataIsFullData: Bool = false
	private var useFullData: Bool = false
	private var calculator = QBECalculator()

	var chart: QBEChart? = nil { didSet {
		self.updateChart()
	} }

	override func tabletWasSelected() {
		self.delegate?.tabletView(self, didSelectConfigurable: self.chart, configureNow: false, delegate: self)
	}

	override func viewWillAppear() {
		self.chart = self.chartTablet?.chart
		self.reloadData()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("resultNotificationReceived:"), name: QBEResultNotification.name, object: nil)
	}

	@objc private func resultNotificationReceived(notification: NSNotification) {
		assertMainThread()

		if let calculationNotification = notification.object as? QBEResultNotification where calculationNotification.sender != calculator {
			if let t = self.chartTablet, let source = t.sourceTablet, let step = source.chain.head {
				if step == calculationNotification.step {
					self.presentedRaster = calculationNotification.raster
					self.presentedDataIsFullData = calculationNotification.isFull
					self.calculator.cancel()
					self.updateProgress()
					self.updateChart(false)
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
		self.updateChart()
	}

	var locale: Locale {
		return QBEAppDelegate.sharedInstance.locale
	}

	/** Loads the required raster data fresh from the data source, and repaints the chart. */
	private func reloadData() {
		asyncMain {
			self.presentedRaster = nil
			self.updateChart(false)
		}

		self.calculator.cancel()
		self.updateProgress()

		if let t = self.chartTablet, let source = t.sourceTablet, let step = source.chain.head {
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
						self.updateChart(true)
					}

				case .Failure(let e):
					/// FIXME show failure
					self.updateProgress()
					print("Failed to rasterize: \(e)")
				}
			}
		}
	}

	/** Repaint the chart based on the current data and parameters. Draws no chart in case we are still loading it. */
	private func updateChart(animated: Bool = false) {
		assertMainThread()

		// Fade any changes in smoothly
		let tr = CATransition()
		tr.duration = 0.3
		tr.type = kCATransitionFade
		tr.subtype = kCATransitionFromRight
		tr.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
		self.chartView.layer?.addAnimation(tr, forKey: kCATransition)

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

				if r.columnCount >= 2 {
					let data = LineChartData(xVals: xs.map { return $0.doubleValue ?? Double.NaN })

					// FIXME: add support for multiple series in QBEChart
					for ySeriesIndex in 1..<2 {
						let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.NaN }
						let yse = ys.enumerate().map { idx, i in return ChartDataEntry(value: i, xIndex: idx) }

						let ds = LineChartDataSet(yVals: yse, label: r.columns[ySeriesIndex].name)
						ds.drawValuesEnabled = false
						ds.drawCirclesEnabled = false
						ds.colors = [colors[(ySeriesIndex - 1) % colors.count]]
						data.addDataSet(ds)
					}

					lineChartView.data = data
					lineChartView.gridBackgroundColor = NSUIColor.whiteColor()
					lineChartView.doubleTapToZoomEnabled = false
					lineChartView.pinchZoomEnabled = false
				}

			case .Radar:
				let radarChartView = RadarChartView(frame: self.chartView.bounds)
				self.chartBaseView = radarChartView

				if r.columnCount >= 2 {
					let data = RadarChartData(xVals: xs.map { return $0.doubleValue ?? Double.NaN })

					for ySeriesIndex in 1..<2 {
						let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.NaN }
						let yse = ys.enumerate().map { idx, i in return ChartDataEntry(value: i, xIndex: idx) }

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
				if r.columnCount >= 2 {
					let data = BarChartData(xVals: [1])

					let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.NaN }

					for (idx, y) in ys.enumerate() {
						let yse = [BarChartDataEntry(value: y, xIndex: 0)]
						let ds = BarChartDataSet(yVals: yse, label: xs[idx].stringValue ?? "")
						ds.drawValuesEnabled = false
						ds.colors = [colors[idx % colors.count]]
						data.addDataSet(ds)
					}

					barChartView.data = data
					barChartView.gridBackgroundColor = NSUIColor.whiteColor()
					barChartView.doubleTapToZoomEnabled = false
					barChartView.pinchZoomEnabled = false
				}

			case .Pie:
				let pieChartView = PieChartView(frame: self.chartView.bounds)
				self.chartBaseView = pieChartView

				// Do any additional setup after loading the view.
				let data = PieChartData(xVals: xs.map { return $0.stringValue })
				let ys = r.rows.map { chart.yExpression.apply($0, foreign: nil, inputValue: nil).doubleValue ?? Double.NaN }

				let yse = ys.map { ChartDataEntry(value: $0, xIndex: 0) }
				let ds = PieChartDataSet(yVals: yse, label: "Data")
				ds.drawValuesEnabled = true
				ds.colors = colors
				data.addDataSet(ds)

				let nf = NSNumberFormatter()
				nf.numberStyle = NSNumberFormatterStyle.DecimalStyle
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
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.chartView, attribute: NSLayoutAttribute.Top, multiplier: 1.0, constant: 0.0),
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.chartView, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0.0),
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.chartView, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0.0),
				NSLayoutConstraint(item: cb, attribute: NSLayoutAttribute.Right, relatedBy: NSLayoutRelation.Equal, toItem: self.chartView, attribute: NSLayoutAttribute.Right, multiplier: 1.0, constant: 0.0)
			])
			cb.canDrawConcurrently = true

			if animated {
				cb.animate(xAxisDuration: 1.0, yAxisDuration: 1.0)
			}
			cb.descriptionFont = NSUIFont.systemFontOfSize(12.0)
			cb.descriptionText = ""
		}
	}

	@IBAction func refreshData(sender: AnyObject) {
		self.reloadData()
	}

	@IBAction func exportFile(sender: NSObject) {
		if let w = self.view.window, let chartView = self.chartBaseView {
			let panel = NSSavePanel()
			panel.allowedFileTypes = ["png"]
			panel.beginSheetModalForWindow(w) { (result) -> Void in
				if result == NSFileHandlingPanelOKButton {
					if let path = panel.URL?.path {
						chartView.saveToPath(path, format: .PNG, compressionQuality: 1.0)
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

	override func validateToolbarItem(item: NSToolbarItem) -> Bool {
		if item.action == Selector("toggleFullData:") {
			if let c = item.view as? NSButton {
				c.state = (useFullData || presentedDataIsFullData) ? NSOnState: NSOffState
			}
		}
		else if item.action == Selector("toggleEditing:") {
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
		if self.chartTablet?.sourceTablet?.chain.head != nil {
			switch action {
			case Selector("refreshData:"), Selector("exportFile:"): return true
			case Selector("cancelCalculation:"): return self.calculator.calculating
			case Selector("toggleFullData:"): return true
			default: return false
			}
		}
		return false
	}
}