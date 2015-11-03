import Foundation
import Cocoa
import WarpCore

internal class QBEMySQLSourceStepView: NSViewController {
	let step: QBEMySQLSourceStep?
	weak var delegate: QBESuggestionsViewDelegate?
	@IBOutlet var userField: NSTextField?
	@IBOutlet var passwordField: NSTextField?
	@IBOutlet var hostField: NSTextField?
	@IBOutlet var portField: NSTextField?
	@IBOutlet var infoLabel: NSTextField?
	@IBOutlet var infoProgress: NSProgressIndicator?
	@IBOutlet var infoIcon: NSImageView?
	
	init?(step: QBEStep?, delegate: QBESuggestionsViewDelegate) {
		self.delegate = delegate
		
		if let s = step as? QBEMySQLSourceStep {
			self.step = s
			super.init(nibName: "QBEMySQLSourceStepView", bundle: nil)
		}
		else {
			self.step = nil
			super.init(nibName: "QBEMySQLSourceStepView", bundle: nil)
			return nil
		}
	}
	
	required init?(coder: NSCoder) {
		self.step = nil
		super.init(coder: coder)
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	@IBAction func updateStep(sender: NSObject) {
		if let s = step {
			var changed = false
			
			if let u = self.userField?.stringValue where u != s.user {
				s.user = u
				changed = true
			}
			
			if let u = self.passwordField?.stringValue where u != s.password {
				s.password = u
				changed = true
			}
			
			if let u = self.hostField?.stringValue where u != s.host {
				s.host = u
				changed = true
			}
			
			if let u = self.portField?.stringValue where Int(u) != s.port {
				s.port = Int(u)
				changed = true
			}
		
			if changed {
				delegate?.suggestionsView(self, previewStep: step)
				updateView()
			}
		}
	}

	private var checkConnectionJob: QBEJob? = nil { willSet {
		if let o = checkConnectionJob {
			o.cancel()
		}
	} }

	private func updateView() {
		checkConnectionJob = QBEJob(.UserInitiated)
		
		if let s = step {
			self.userField?.stringValue = s.user ?? ""
			self.passwordField?.stringValue = s.password ?? ""
			self.hostField?.stringValue = s.host ?? ""
			self.portField?.stringValue = "\(s.port ?? 0)"

			self.infoProgress?.hidden = false
			self.infoLabel?.stringValue = NSLocalizedString("Trying to connect...", comment: "")
			self.infoIcon?.image = nil
			self.infoIcon?.hidden = true
			self.infoProgress?.startAnimation(nil)

			checkConnectionJob!.async {
				if let database = s.database {
					switch database.connect() {
					case .Success(let con):
						con.serverInformation({ (fallibleInfo) -> () in
							QBEAsyncMain {
								self.infoProgress?.stopAnimation(nil)
								switch fallibleInfo {
								case .Success(let v):
									self.infoLabel?.stringValue = String(format: NSLocalizedString("Connected (%@)", comment: ""),v)
									self.infoIcon?.image = NSImage(named: "CheckIcon")
									self.infoProgress?.hidden = true
									self.infoIcon?.hidden = false

								case .Failure(let e):
									self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
									self.infoIcon?.image = NSImage(named: "SadIcon")
									self.infoProgress?.hidden = true
									self.infoIcon?.hidden = false
								}
							}
						})

					case .Failure(let e):
						self.infoLabel?.stringValue = String(format: NSLocalizedString("Could not connect: %@", comment: ""), e)
						self.infoIcon?.image = NSImage(named: "SadIcon")
						self.infoProgress?.hidden = true
						self.infoIcon?.hidden = false
					}
				}
			}
		}
	}
}