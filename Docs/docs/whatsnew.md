# Version 3.4

Released: tbd.

* The formula editor now shows available columns and an example of the formula result
* You can now easily add data sets that are related to a data set (e.g. tables that have a foreign key relationship). To do so drag an arrow out from the table and select the menu item 'related data sets'.
* You can now use the a[b] syntax to access pack items (shorthand syntax for NTH(a;b))
* When you ask Warp to calculate the full result of a calculation, Warp will now stream in the results
* You can now download data from URLs using the 'download data from the web' step
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