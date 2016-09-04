You can load data into Warp in one of the following ways:

* Use the menu bar and select 'File' -> 'Load data from file'.
* Drag one or more files to the Warp window
* Use the '+' button in the toolbar. From there you can add data from files and databases

When you add data to Warp, the data itself is *not* stored in the Warp document itself - it is only linked to. After adding, Warp will show the data in a table. Above the table is a symbol indicating where the data came from - this is the 'loading step'. After the loading step, you can add data transformation steps (read all about [data transformation here](steps)).

Warp supports the following data sources:

| Name | Description |
|------|-------------|
| ![CSV](img/steps/csv.png) [CSV](#csv) | Comma-, tab- or otherwise separated text files |
| ![DBF](img/steps/dbf.png) [DBF](#dbf) | dBaseIII data files |
| ![MySQL](img/steps/mysql.png) [MySQL](#mysql) | MySQL, MariaDB or PerconaDB databases |
| ![PostgreSQL](img/steps/postgresql.png) [PostgreSQL](#postgresql) | PostgreSQL open-source database |
| ![Presto](img/steps/presto.png) [Presto](#presto) | Engine by Facebook that allows connecting to multiple data warehouse systems |
| ![RethinkDB](img/steps/rethinkdb.png) [RethinkDB](#rethinkdb) | A NoSQL, real-time database |
| ![Sequence](img/steps/sequence.png) [A sequence](#sequence) | Generate a list of values according to a pattern |
| ![SQLite](img/steps/sqlite.png) [SQLite](#sqlite) | A file-based SQL database |


# CSV

![CSV step icon](img/steps/csv.png)

Warp supports loading data directly from CSV files. In order to successfully load a CSV file, it must conform to the following requirements:

* The file must be in Unicode encoding (preferably UTF-8). 
* Each row must contain the same number of values
* Rows may be separated by Windows (\r\n) or UNIX (\n) newlines.
* Strings may be enclosed by "quotes". Inside quotation the separator character may be freely used and is interpreted as part of the value.
* Double quotes may be used to add quotes to a value itself inside quotation.

Numeric values inside the CSV file will be interpreted according to the language set ([see here for more information](language.md)). 

Warp will use the first row of a CSV file to set the column names, but can be configured to treat the first row as data.

Warp currently does not support making changes to CSV files. It is however possible to export data to CSV files.


# DBF

![DBF step icon](img/steps/dbf.png)

Warp supports loading data directly from dBase III (DBF) files. 

Warp currently does not support making changes to DBF files. It is however possible to export a data set to a DBF file.

# MySQL

![SQLite step icon](img/steps/mysql.png)

Warp supports loading data directly from [MySQL](http://www.mysql.com) databases. MySQL is a database system traditionally used to store data for dynamic websites. After MySQL was acquired by Oracle, MySQL is being developed as [MariaDB](http://mariadb.org), which Warp is also compatible with. 

Warp can connect to any MySQL 5.0 or higher server over TCP/IP (UNIX domain sockets are not supported). Warp will also support any database that supports the MySQL *protocol* and understands MySQL 5.0 commands (e.g. MariaDB).

# PostgreSQL

![Postgresql step icon](img/steps/postgresql.png)

Warp supports loading data directly from PostgreSQL databases.

# Presto

![Presto step icon](img/steps/presto.png)

Warp supports loading data from [Presto](https://prestodb.io). Presto is an open source distributed SQL query engine for running interactive analytic queries against data sources of all sizes ranging from gigabytes to petabytes.

# RethinkDB

![SQLite step icon](img/steps/rethinkdb.png)

Warp supports reading and writing data from and to [RethinkDB](http://www.rethinkdb.com). RethinkDB is the first open-source, scalable JSON database built from the ground up for the realtime web. It inverts the traditional database architecture by exposing an exciting new access model – instead of polling for changes, the developer can tell RethinkDB to continuously push updated query results to applications in realtime. RethinkDB’s realtime push architecture dramatically reduces the time and effort necessary to build scalable realtime apps.

Note that RethinkDB is a *schemaless* database. This means that rows do not all have data for the same column, nor that type requirements are enforced. 

Warp can make changes to data contained in RethinkDB if the data set contains the primary key that uniquely identifies a row. 

# Sequence

![Sequence step icon](img/steps/sequence.png)

Warp can generate data from a pattern - this is called a 'sequence'. The pattern generally follows the regular expression syntax. Warp returns a row for each possible value that matches the pattern. For instance, the pattern "[a-z]" will generate 26 rows ("a","b"..."z"). 

Sequences can be used to quickly generate mock data, or to enumerate a set of possible values (e.g. ID values) for subsequent linking or crawling.

A pattern can be built out of the following elements:

* Strings: "abc" indicates that the string "abc" should match fully.
* Character sets: "[abc]" specifies that either the character 'a', 'b' or 'c' matches. The characters between brackets are taken literally (i.e. they cannot be other expressions)
* Character ranges: "[a-z]" specifies that any character between and including 'a' and 'z' matches.
* Parentheses: "(abc)" specifies that 'abc' must match as a whole.
* Alternative: "a|b" specifies that *either* a or b matches. The 'a' and 'b' can be subexpressions (grouped using parentheses).
* Repetition: "x{5}" specifies that 'x' must match exactly five times, where 'x' may be a subexpression.
* Optional: "x?" specifies that 'x' may optionally match.

Note that the number of possible values increases very quickly with longer patterns, especially when many alternatives and character sets are used.

# SQLite

![SQLite step icon](img/steps/sqlite.png)

Warp can read and write data from and to SQLite databases.