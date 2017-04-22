Dates are internally represented as the number of seconds since a particular reference date. They are shown in Warp in a 'friendly' format and in the local timezone. 

## Working with dates

The following functions can be used with dates:

| Function| Description |
|---------|-------------|
|NOW()|Return the current date|
|FROM.EXCELDATE(e)|Return the date represented as Excel date number e|
|TO.EXCELDATE(d)|Return the Excel date number for date d|
|DATE.UTC(y;m;d)|Return a date for the indicated year, month, day (at 00:00 UTC that day)|
|READ.DATE(s;format)|Reads string s as date in format and returns the date|
|WRITE.DATE(d;format)|Writes date d as string in the format specified|
|AFTER(d; seconds)|Returns the date that happens seconds after date d|
|DAY.UTC(d)|Returns the day of month of date d in UTC|
|HOUR.UTC(d)|Returns the hour of day of date d in UTC|
|MONTH.UTC(d)|Returns the month of date d in UTC|
|MINUTE.UTC(d)|Returns the minute of hour of date d in UTC|
|SECOND.UTC(d)|Returns the second of minute of date d in UTC|
|YEAR.UTC(d)|Returns the year of date d in UTC|
|FROM.ISO8601(s)|Returns the date from ISO-8601 formatted string s|
|TO.ISO8601(d)|Returns the ISO-8601 formatted string for date d (displayed in local time zone)|
|TO.ISO8601.UTC(d)|Returns the ISO-8601 formatted string for date d (displayed in UTC)|
|TO.UNIX(d)|Returns the UNIX timestamp for date d|
|FROM.UNIX(n)|Returns the date from UNIX timestamp n|
|DURATION(a;b)|Returns the number of seconds that elapses between date a and b|

Month and month day numbers start counting at 1 (e.g. month 1 equals January). Date formats are expressed as follows: ````yyyy-MM-dd````.