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

	private func updateView() {
		let job = QBEJob(.UserInitiated)
		
		if let s = step {
			self.userField?.stringValue = s.user ?? ""
			self.passwordField?.stringValue = s.password ?? ""
			self.hostField?.stringValue = s.host ?? ""
			self.portField?.stringValue = "\(s.port ?? 0)"

			job.async {
				if let database = s.database {
					let dbFallible = database.connect()
					switch dbFallible {
						case .Success(let db):
							// TODO OK, show some nice 'connected' message
							break;

						case .Failure(_):
							// TODO: failure, show error
							break;
					}
				}
			}
		}
	}
}