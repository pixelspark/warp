/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import WarpCore
import Foundation

/** QBESettings stores application-wide settings, primarily user preferences. These settings are currently stored in OS X
user defaults, but in the future may also be saved to iCloud or any other place. No security-sensitive information (e.g.
passwords) should be stored using QBESettings. */
class QBESettings {
	static let sharedInstance = QBESettings()
	private let defaults: UserDefaults
	
	init () {
		defaults = UserDefaults.standard
		
		#if DEBUG
			resetOnces()
		#endif
	}

	private var lastTip: Date? {
		get {
			let i = defaults.double(forKey: "lastTip")
			return i > 0 ? Date(timeIntervalSinceReferenceDate: i) : nil
		}
		set {
			if let d = newValue {
				defaults.set(d.timeIntervalSinceReferenceDate, forKey: "lastTip")
			}
		}
	}

	private let timeBetweenTips: TimeInterval = 30.0

	/** Calls the given block if the last time this function was called more than `timeBetweenTips` seconds ago, and no
	call to showTip or once has been made with the given key before. This is useful for ensuring that tip balloons don't 
	show up to soon after each other. */
	func showTip(_ onceKey: String, block: () -> ()) {
		let last = self.lastTip
		if last == nil || abs(last!.timeIntervalSinceNow) > timeBetweenTips {
			once(onceKey) {
				block()
				self.lastTip = Date()
			}
		}
	}
	
	var monospaceFont: Bool {
		get {
			return defaults.bool(forKey: "monospaceFont") 
		}
		set {
			defaults.set(newValue, forKey: "monospaceFont")
		}
	}
	
	var locale: Language.LanguageIdentifier {
		get {
			return defaults.string(forKey: "locale") ?? Language.defaultLanguage
		}
	}
	
	var defaultFieldSeparator: String {
		get {
			return defaults.string(forKey: "defaultSeparator") ?? ","
		}
	}
	
	var exampleMaximumTime: Double {
		get {
			let maxTime = defaults.double(forKey: "exampleMaximumTime")
			if maxTime <= 0.0 {
				return 1.5
			}
			return maxTime
		}
		
		set {
			defaults.set(max(0.25, newValue), forKey: "exampleMaximumTime")
		}
	}
	
	var exampleMaximumRows: Int {
		get {
			let maxRows = defaults.integer(forKey: "exampleMaximumRows")
			if maxRows <= 0 {
				return 500
			}
			return maxRows
		}
		
		set {
			defaults.set(max(100, newValue), forKey: "exampleMaximumRows")
		}
	}
	
	func defaultWidthForColumn(_ withName: Column) -> Double? {
		return defaults.double(forKey: "width.\(withName.name)")
	}
	
	func setDefaultWidth(_ width: Double, forColumn: Column) {
		defaults.set(width, forKey: "width.\(forColumn.name)")
	}
	
	/** Return whether it is allowable to cache a file of the indicated size in the indicated location. This function
	bases its decision on the amount of disk space free in the target location (and allows any file to be cached to
	only use a particular fraction of it). In the future, it may use preferences exposed to the user. The result of this
	function should be used to set the default preference for caching in steps that allow the user to toggle caching.
	Caching explicitly requested by the user should be disabled anyway if this function returns false. */
	func shouldCacheFile(ofEstimatedSize size: Int, atLocation: URL) -> Bool {
		// Let's find out how much disk space is left in the proposed cache location
		do {
			let attrs = try FileManager.default.attributesOfFileSystem(forPath: atLocation.path)
			if let freeSpace = attrs[FileAttributeKey.systemFreeSize] as? NSNumber {
				let freeSize = Double(size) / Double(truncating: freeSpace)
				if freeSize < 0.8 {
					return true
				}
			}
		} catch {}
		return false
	}
	
	/** Call the provided callback only when this function has not been called before with the same key. This can be used
	to show the user certain things (such as tips) only once. Returns true if the block was executed. */
	@discardableResult func once(_ key: String, callback: () -> ()) -> Bool {
		let onceKey = "once.\(key)"
		if !defaults.bool(forKey: onceKey) {
			defaults.set(true, forKey: onceKey)
			callback()
			return true
		}
		return false
	}
	
	func resetOnces() {
		/* In debug builds, all keys starting with "once." are removed, to re-enable all 'once' actions such as
		first-time tips. */
		let dict = defaults.dictionaryRepresentation()
		for (key, _) in dict {
			if let r = key.range(of: "once.", options: NSString.CompareOptions.caseInsensitive, range: nil, locale: nil), r.lowerBound==key.startIndex {
				defaults.removeObject(forKey: key)
			}
		}
	}
}
