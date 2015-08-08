import Foundation
import SwiftParser

internal extension NSDate {
	static func fromISO8601FormattedDate(date: String) -> NSDate? {
		let dateFormatter = NSDateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
		return dateFormatter.dateFromString(date)
	}
	
	/** The 'Excel epoch', or the beginning of time according to Microsoft Excel. This is what the date '0' translates
	to in Excel (actually on my PC it says '0 january 1900', which of course doesn't exist). */
	static var excelEpoch: NSDate { get {
		let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
		let comps = NSDateComponents()
		comps.year = 1899
		comps.month = 12
		comps.day = 30
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		calendar.timeZone = NSTimeZone(abbreviation: "UTC")!
		return calendar.dateFromComponents(comps)!
	} }
	
	/** Returns the time at which the indicated Gregorian date starts in the UTC timezone. */
	static func startOfGregorianDateInUTC(year: Int, month: Int, day: Int) -> NSDate {
		let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
		let comps = NSDateComponents()
		comps.year = year
		comps.month = month
		comps.day = day
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		calendar.timeZone = NSTimeZone(abbreviation: "UTC")!
		return calendar.dateFromComponents(comps)!
	}
	
	static func startOfLocalDate(locale: QBELocale, year: Int, month: Int, day: Int) -> NSDate {
		let comps = NSDateComponents()
		comps.year = year
		comps.month = month
		comps.day = day
		comps.hour = 0
		comps.minute = 0
		comps.second = 0
		return locale.calendar.dateFromComponents(comps)!
	}
	
	func localComponents(locale: QBELocale) -> NSDateComponents {
		return locale.calendar.componentsInTimeZone(locale.timeZone, fromDate: self)
	}
	
	var gregorianComponentsInUTC: NSDateComponents { get {
		let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
		return calendar.componentsInTimeZone(NSTimeZone(abbreviation: "UTC")!, fromDate: self)
	} }
	
	func fullDaysTo(otherDate: NSDate) -> Int {
		let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
		let  components = calendar.components(NSCalendarUnit.Day, fromDate: self, toDate: otherDate, options: [])
		return components.day
	}
	
	/** Calculates a date by adding the specified number of days. Note that this is not just doing time + x * 86400, but
	takes leap seconds into account. */
	func dateByAddingDays(days: Int) -> NSDate? {
		let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
		let comps = NSDateComponents()
		comps.day = days
		return calendar.dateByAddingComponents(comps, toDate: self, options: [])
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
		return self.timeIntervalSinceDate(NSDate.excelEpoch) / 86400.0
	} }
	
	static func fromExcelDate(date: Double) -> NSDate? {
		let daysSinceEpoch = Int(floor(date))
		let fractionalPart = date - Double(daysSinceEpoch)
		let startOfDaySinceEpoch = NSDate(timeIntervalSinceReferenceDate: NSDate.excelEpoch.timeIntervalSinceReferenceDate + (Double(daysSinceEpoch) * 86400.0))
		return NSDate(timeInterval: 86400.0 * fractionalPart, sinceDate: startOfDaySinceEpoch)
	}
	
	/**	Returns an ISO-8601 formatted string of this date, in the locally preferred timezone. Should only be used for
	presentational purposes. */
	var iso8601FormattedLocalDate: String { get {
		let dateFormatter = NSDateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
		return dateFormatter.stringFromDate(self)
		} }
	
	/** Returns an ISO-8601 formatted string representation of this date, in the UTC timezone ('Zulu time', that's why it
	ends in 'Z'). */
	var iso8601FormattedUTCDate: String { get {
		let formatter = NSDateFormatter()
		formatter.timeZone = NSTimeZone(abbreviation: "UTC")
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
		return formatter.stringFromDate(self)
	} }
	
	var unixTime: Double { get {
		return self.timeIntervalSince1970
	} }
}