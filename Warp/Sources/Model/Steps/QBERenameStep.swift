import Foundation
import WarpCore

class QBERenameStep: QBEStep {
	var renames: [Column: Column] = [:]

	required init() {
		super.init()
	}
	
	init(previous: QBEStep?, renames: [Column:Column] = [:]) {
		self.renames = renames
		super.init(previous: previous)
	}

	override func sentence(locale: Locale, variant: QBESentenceVariant) -> QBESentence {
		if renames.isEmpty {
			return QBESentence([QBESentenceText(NSLocalizedString("Rename columns", comment: ""))])
		}
		else if renames.count == 1 {
			let rename = renames.first!
			return QBESentence(format: NSLocalizedString("Rename column [#] to [#]", comment: ""),
				QBESentenceTextInput(value: rename.0.name, callback: { [weak self] (newName) -> (Bool) in
					if !newName.isEmpty {
						let oldTo = self?.renames.removeValueForKey(rename.0)
						self?.renames[Column(newName)] = oldTo
						return true
					}
					return false
				}),
				QBESentenceTextInput(value: rename.1.name, callback: { [weak self] (newName) -> (Bool) in
					if !newName.isEmpty {
						self?.renames[rename.0] = Column(newName)
						return true
					}
					return false
				})
			)
		}
		else {
			return QBESentence([QBESentenceText(String(format: NSLocalizedString("Rename %d columns", comment: ""), renames.count))])
		}
	}
	
	required init(coder aDecoder: NSCoder) {
		let renames = (aDecoder.decodeObjectForKey("renames") as? [String:String]) ?? [:]
		self.renames = [:]
		
		for (key, value) in renames {
			self.renames[Column(key)] = Column(value)
		}
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		var renames: [String: String] = [:]
		for (key, value) in self.renames {
			renames[key.name] = value.name
		}
		coder.encodeObject(renames, forKey: "renames")
		super.encodeWithCoder(coder)
	}
	
	override func apply(data: Data, job: Job, callback: (Fallible<Data>) -> ()) {
		// If we have nothing to rename, bypass this step
		if self.renames.isEmpty {
			callback(.Success(data))
			return
		}
		
		data.columns(job) { (existingColumnsFallible) -> () in
			callback(existingColumnsFallible.use {(existingColumnNames) -> Data in
				var calculations: [Column: Expression] = [:]
				var newColumns: [Column] = []
				
				// Create a calculation that performs the rename
				for oldName in existingColumnNames {
					if let newName = self.renames[oldName] where newName != oldName {
						if !newColumns.contains(newName) {
							calculations[newName] = Sibling(oldName)
							newColumns.append(newName)
						}
					}
					else {
						newColumns.append(oldName)
					}
				}
				return data.calculate(calculations).selectColumns(newColumns)
			})
		}
	}
	
	override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if let p = prior as? QBERenameStep {
			var renames = p.renames
			
			// Find out which columns are created by the prior step
			var renamed: [Column: Column] = [:]
			for (old, new) in renames {
				renamed[new] = old
			}
			
			// Merge our renames with the previous ones
			for (old, new) in self.renames {
				if let older = renamed[old] {
					// We are renaming a column that was renamed previously, overwrite the rename
					renames[older] = new
				}
				else {
					renames[old] = new
				}
			}
			self.renames = renames
			
			// This step can ony be a further subset of the columns selected by the prior
			return QBEStepMerge.Advised(self)
		}
		return QBEStepMerge.Impossible
	}
}