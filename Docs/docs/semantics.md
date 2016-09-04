# Values

## Types

Warp supports the following value types:

| Type | Description |
|------|-------------|
| String | Text |
| Integer | Integer numbers, which may be positive or negative |
| Double | Double-precision decimal numbers |
| Boolean | Either true or false |
| Date | An absolute timestamp |
| Empty | A special value indicating missing data |
| Error | A special value indicating a calculation error |

Warp only uses these types 'behind the scenes', that is - values of one type will be automatically converted to another when that is necessary. If you are for instance adding two strings ("1" + "2"), Warp will first convert the two strings to numbers, and then calculate the addition (1+2). Because of this, every operator or function has a strictly defined preference for types. If conversion of types is impossible (e.g. if you are trying to do "a" + "b", neither can be converted to a number), it will result in an error value.

## Dates

Dates are internally represented as the number of seconds since a particular reference date. They are shown in Warp in a 'friendly' format and in the local timezone. 

## Special values

The 'empty value' is used to indicate data that is missing - it is present on other rows but deliberately not on this row. The empty value is equal to other empty values, and equal to an empty string (""). The empty value is however not equal to any number.

The 'error value' is used to indicate that the value is the result of a calculation gone wrong. For instance, dividing a value by zero will result in an error value. If a function is given wrong arguments or cannot do its work, it will also result in an error value. An error value is never equal to any other value, including other error values.

## Mapping to SQL

When performing data transformations on data coming from an SQL database, Warp will try to perform most of the work in the database itself, for performance. This requires the type semantics to be mapped to SQL. This generally works as expected, with the following caveats:

* The empty value is mapped to NULL. A comparison with the empty value is translated to '.. IS NULL'.
* There is no boolean type in SQL. The boolean value 'true' is written in SQL as '(1=1)' and false as '(1=0)' so it automatically uses the database's native type for boolean values.

# Column names

Column names are case-insensitive. In a table, a column name may appear only once. This combined means that there can never be two columns in a table that only differ by capitalization (e.g. "test" and "TEST" cannot co-exist in the same table). 