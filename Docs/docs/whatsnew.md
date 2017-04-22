# Version 3.9

Released: April 24, 2017

* You can now rank rows as well as calculate running aggregates (e.g. running average)
* You can set a minimum cell size for aggregations (e.g. in pivot table)	 which helps preserve statistical anonymity
* Warp can now read JSON files
* The formula syntax for referencing columns has been simplified. Simply use the column name if it contains only alphanumeric characters and starts with an alphabetic character. Otherwise just use "[colum_name]" instead of "[@column_name]".
* Likewise, the syntax for referencing foreign columns has been simplified to "#column" and "#[column_name]"
* Presto performance has been greatly improved, as Warp now pushes down operations to Presto when multiple tables from the same server are involved.
* Warp now supports blob values
* A native data type for lists has been introduced
* Empty (NULL) values are now sorted consistently when sorting

# Version 3.8

Released: March 6, 2017
* Minor bug fixes and improvements

# Version 3.7

Released: February 19, 2017 (iOS)

* You can now calculate columns using formulas on iOS
* You can now sort by column on iOS
* Warp now has keyboard shortcuts on iOS
* Various bug fixes and performance improvements

# Version 3.6

Released: January 8, 2017 (iOS)

* First version of Warp for iOS!

# Version 3.5

Released: November 27, 2016

# Version 3.4

Released: September 12, 2016

* You can now more easily extract values from JSON-formatted data. Simply select a JSON value and go to 'Value' -> 'Extract data from JSON'. This will present a visual representation of the JSON data and allows you to select the data to be extracted.
* The formula editor now shows available columns and an example of the formula result
* You can now easily add data sets that are related to a data set (e.g. tables that have a foreign key relationship). To do so drag an arrow out from the table and select the menu item 'related data sets'.
* You can now use the a[b] syntax to access pack items (where b is a numeric value; this is shorthand syntax for NTH(a;b)). You can use the a->"b" syntax to access a value from a map.
* When you ask Warp to calculate the full result of a calculation, Warp will now stream in the results.
* You can now download data from URLs using the 'download data from the web' step.
* You can now split lists to multiple rows and to multiple columns using the corresponding steps available in the 'Rows' and 'Columns' menu respectively.
* You can now ask Warp to cache data from 'slow' data sources in-memory, so you can work with them more quickly. To do so, go to the 'Table' menu and select 'Cache data'. Remember to click 'Clear cache' to re-load the cache with the latest version of the data, if the source data changes.

# Version 3.3

Released: May 29, 2016

* When you edit a value in a table that can be written to, Warp will ask you whether you want to add a transformation step, or change the value in the source data set permanently. Warp will also show a list of alternatives in case you choose to add a transformation step.
* You can now create a new, empty SQLite file when uploading data to an SQLite database.
* Data that contained quotes could in some cases not be properly uploaded to SQL databases - this has been fixed.
* You can now click the circle to the top right of a table to show a menu for uploading and exporting data. Dragging the circle to the workspace or another table remains possible.
* The FROM.JSON function can now be used from formulas to read JSON objects
* You can now split rows based on list (pack-formatted) data contained in a cell
* Warp now supports the v1.0 RethinkDB protocol, which allows for secure authentication using a username and password.
* Column filters are now automatically added as a step
* Warp now properly connects to MySQL databases that do not have a database called 'test'

# Version 3.2

Released: April 8, 2016

* When you double-click a colum nheader, Warp now shows you statistics of data in the column and easy access to sorting functions
* When you change a table, all tables and charts that read data from it are updated automatically as well
* Warp can now draw maps from data sets that contain coordinates (latitude/longitude). To make a map, drag off an arrow from a data table into the document, and select 'create map here'.
* Credentials for MySQL and PostgreSQL databases are now remembered in your Keychain and can be quickly selected from a list when connecting
* Source data to which processing steps have been applied can now in some cases still be edited
* Filter lists now show how many times an item occurs, and you can also sort by it to show the most occurring items first
* You can now drag off a column into the document to easily create a frequency table of that column. Using the built-in chart functionality you can then easily turn this into a histogram
* You can now edit data sets that do not have a primary key - Warp will ask you to select the columns that are unique if there is no primary key.
* Many bugs fixed, in particular related to aggregation and filtering performance

# Version 3.1

Released: Mar 15, 2016

# Version 3.0

Released: Jan 27, 2016

# Version 2.4

Released: Dec 4, 2015

# Version 2.3

Released: Oct 24, 2015

# Version 2.2

Released: Aug 20, 2015

# Version 2.1

Released: Jul 31, 2015

# Version 2.0

Released: May 29, 2015

# Version 1.2

Released: April 9, 2015

# Version 1.1

Released: Mar 29, 2015

# Version 1.0

Released: Mar 18, 2015