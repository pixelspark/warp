import Foundation
import WarpCore

class QBEJobViewController: NSViewController, JobDelegate {
	private var job: Job
	var jobDescription: String
	@IBOutlet var descriptionLabel: NSTextField!
	@IBOutlet var progressIndicator: NSProgressIndicator!

	init?(job: Job, description: String) {
		self.job = job
		self.jobDescription = description
		super.init(nibName: "QBEJobViewController", bundle: nil)
		job.addObserver(self)
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	override func viewWillAppear() {
		self.progressIndicator.startAnimation(nil)
		self.progressIndicator.indeterminate = true
		self.update()
	}

	override func viewWillDisappear() {
		self.progressIndicator.stopAnimation(nil)
	}

	@IBAction func cancel(sender: NSObject) {
		self.job.cancel()
		self.dismissController(sender)
	}

	private func update() {
		self.descriptionLabel?.stringValue = jobDescription
		self.progressIndicator.indeterminate = false
		self.progressIndicator.doubleValue = job.progress
	}

	func job(job: AnyObject, didProgress: Double) {
		asyncMain {
			self.update()
		}
	}
}

class JobsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, JobsManagerDelegate {
	@IBOutlet var tableView: NSTableView!
	var jobs: [QBEJobsManager.JobInfo] = []

	override func viewWillAppear() {
		QBEAppDelegate.sharedInstance.jobsManager.addObserver(self)
		self.view.window?.titlebarAppearsTransparent = true
		updateView()
	}

	override func viewWillDisappear() {
		QBEAppDelegate.sharedInstance.jobsManager.removeObserver(self)
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return self.jobs.count
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		let info = jobs[row]

		switch tableColumn?.identifier ?? "" {
			case "description": return info.description
			case "progress": return "\(info.progress)"
			default: return nil
		}
	}

	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let info = jobs[row]

		switch tableColumn?.identifier ?? "" {
		case "description":
			let vw = NSTextField()
			vw.bordered = false
			vw.backgroundColor = NSColor.clearColor()
			vw.stringValue = info.description
			return vw

		case "progress":
			let vw = NSProgressIndicator()
			vw.style = .BarStyle
			vw.indeterminate = false
			vw.doubleValue = info.progress
			vw.maxValue = 1.0
			vw.minValue = 0.0
			return vw

		default: return nil
		}
	}

	private func updateView() {
		assertMainThread()
		self.jobs = QBEAppDelegate.sharedInstance.jobsManager.runningJobs
		self.tableView?.reloadData()
	}

	func jobManager(manager: QBEJobsManager, jobDidStart: AnyObject) {
		asyncMain {
			self.updateView()
		}
	}

	func jobManagerJobsProgressed(manager: QBEJobsManager) {
		asyncMain {
			self.updateView()
		}
	}
}