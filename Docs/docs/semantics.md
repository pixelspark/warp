## Data types

Warp supports the following value types:

| Type | Description |
|------|-------------|
| String | Text |
| Integer | Integer numbers, which may be positive or negative |
| Double | Double-precision decimal numbers |
| Boolean | Either true or false |
| [Date](date.md) | An absolute timestamp |
| [Empty](specials.md) | A special value indicating missing data |
| [Invalid](specials.md) | A special value indicating a calculation error |
| [Blob](blobs.md) | Binary data |
| [List](lists.md) | List of values |

Warp only uses these types 'behind the scenes', that is - values of one type will be automatically converted to another when that is necessary. If you are for instance adding two strings ("1" + "2"), Warp will first convert the two strings to numbers, and then calculate the addition (1+2). Because of this, every operator or function has a strictly defined preference for types. If conversion of types is impossible (e.g. if you are trying to do "a" + "b", neither can be converted to a number), it will result in an error value.

## Mapping to SQL

When performing data transformations on data coming from an SQL database, Warp will try to perform most of the work in the database itself, for performance. This requires the type semantics to be mapped to SQL. This generally works as expected, with the following caveats:

* The empty value is mapped to NULL. A comparison with the empty value is translated to '.. IS NULL'.
* There is no boolean type in SQL. The boolean value 'true' is written in SQL as '(1=1)' and false as '(1=0)' so it automatically uses the database's native type for boolean values.

# Column names

Column names are case-insensitive. In a table, a column name may appear only once. This combined means that there can never be two columns in a table that only differ by capitalization (e.g. "test" and "TEST" cannot co-exist in the same table). 