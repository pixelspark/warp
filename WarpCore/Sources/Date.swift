import Foundation
import SwiftParser

public extension Date {
	static func fromISO8601FormattedDate(_ date: String) -> Date? {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
		return dateFormatter.date(from: date)
	}
	
	/** The 'Excel epoch', or the beginning of time according to Microsoft Excel. This is what the date '0' translates
	to in Excel (actually on my PC it says '0 january 1900', which of course doesn't exist). */
	static var excelEpoch: Date { get {
		var calendar = Calendar(identifier: Calendar.Identifier.gregorian)
		var comps = DateComponents()
		comps.year = 1899
		comps.month = 12
		comps.day = 30
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		calendar.timeZone = TimeZone(abbreviation: "UTC")!
		return calendar.date(from: comps)!
	} }
	
	/** Returns the time at which the indicated Gregorian date starts in the UTC timezone. */
	static func startOfGregorianDateInUTC(_ year: Int, month: Int, day: Int) -> Date {
		var calendar = Calendar(identifier: Calendar.Identifier.gregorian)
		var comps = DateComponents()
		comps.year = year
		comps.month = month
		comps.day = day
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		calendar.timeZone = TimeZone(abbreviation: "UTC")!
		return calendar.date(from: comps)!
	}
	
	static func startOfLocalDate(_ locale: Language, year: Int, month: Int, day: Int) -> Date {
		var comps = DateComponents()
		comps.year = year
		comps.month = month
		comps.day = day
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		return locale.calendar.date(from: comps)!
	}
	
	func localComponents(_ locale: Language) -> DateComponents {
		return locale.calendar.dateComponents(in: locale.timeZone, from: self)
	}
	
	var gregorianComponentsInUTC: DateComponents { get {
		let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
		return calendar.dateComponents(in: TimeZone(abbreviation: "UTC")!, from: self)
	} }

	func fullDaysTo(_ otherDate: Date) -> Int {
		let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
		let components = calendar.dateComponents([.day], from: self)
		return components.day!
	}
	
	/** Calculates a date by adding the specified number of days. Note that this is not just doing time + x * 86400, but
	takes leap seconds into account. */
	func dateByAddingDays(_ days: Int) -> Date? {
		let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
		var comps = DateComponents()
		comps.day = days
		return calendar.date(byAdding: comps, to: self)
	}
	
	/** Returns the Excel representation of a date. This is a decimal number where the integer part indicates the number
	of days since the 'Excel epoch' (which appears to be 1899-12-30T00:00:00Z; the date'0' represents '0 january 1900'
	in Excel). The fractional part is the number of seconds that has passed that day, divided by 86400.
	
	In our implementation, we simply divide by 86400. Excel seems to assume days always are 86400 (24 * 60 * 60) seconds
	long (i.e. no leap seconds).
	
	Note that Excel seems to be using the user's timezone instead of UTC in calculating the above (I haven't tested, but
	it may even use a calculation in UTC to determine the integer part of the Excel date, but show the time in the local
	time zone. ',999' translates to 23:59 and I'm in UTC+2 currently). */
	var excelDate: Double? { get {
		return self.timeIntervalSince(Date.excelEpoch) / 86400.0
	} }
	
	static func fromExcelDate(_ date: Double) -> Date? {
		let daysSinceEpoch = Int(floor(date))
		let fractionalPart = date - Double(daysSinceEpoch)
		let startOfDaySinceEpoch = Date(timeIntervalSinceReferenceDate: Date.excelEpoch.timeIntervalSinceReferenceDate + (Double(daysSinceEpoch) * 86400.0))
		return Date(timeInterval: 86400.0 * fractionalPart, since: startOfDaySinceEpoch)
	}
	
	/**	Returns an ISO-8601 formatted string of this date, in the locally preferred timezone. Should only be used for
	presentational purposes. */
	var iso8601FormattedLocalDate: String { get {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
		return dateFormatter.string(from: self)
		} }
	
	/** Returns an ISO-8601 formatted string representation of this date, in the UTC timezone ('Zulu time', that's why it
	ends in 'Z'). */
	var iso8601FormattedUTCDate: String { get {
		let formatter = DateFormatter()
		formatter.timeZone = TimeZone(abbreviation: "UTC")
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
		return formatter.string(from: self)
	} }
	
	var unixTime: Double { get {
		return self.timeIntervalSince1970
	} }
}
