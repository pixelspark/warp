If you have worked with formulas in Microsoft Excel before, you will find the formula language used in Warp easy to learn. A formula can consists of values (numbers or text), functions and mathematical operations (plus, minus, et cetera). You can group parts of a formula, like in mathematics, with parentheses. 

A formula can optionally start with an equals sign ('='). In some cases, you can indicate that you want to calculate something using a formula by starting with the '=' sign. For instance, you can type '=1+1' in a cell, which will be interpreted as '2'.

# Values

## Numbers

Formulas can contain numeric values, formatted according to the current language setting in Warp. Numeric values may have decimals and may contain thousand separators. For the English language setting, numbers can look like this:

````
1,000,000.123
-1.00
1,000,000
1000000
````

If you edit a formula in Warp, Warp may automatically insert thousands separators to make the number more readable.

You may append SI postfixes to numeric values to indicate magnitude: 
````
1da = 10
1h = 100
1k = 1000
1M = 1000000
1G = 1000000000
1T = 1000^4
1P = 1000^5
1E = 1000^6
1Z = 1000^7
1Y = 1000^8

1d = 0.1
1c = 0.01
1m = 0.001
1µ = 0.001^2
1n = 0.001^3
1p = 0.001^4
1f = 0.001^5
````

## Dates

The easiest way to create a date value is to use one of the date [functions](#functions), such as 'DATE.UTC' which takes the day, month and year as argument, and returns a date value for that day in UTC. You can also use 'NOW' to return the current date and time as date value. You can also specify a date as the number of seconds since the Warp reference date by prefixing the number with the '@' sign.

## Text

Formulas can contain text, enclosed between brackets:

````
"hello world"
````

If the text itself should contain a bracket, you need to put a backslash in front of it, so Warp knows the string doesn't end there:

````
"and then I said \"hello world\"!"
````

If you want to insert a backslash, insert an extra one before it:

````
"This is a backslash: \\"
````

## Constants

The following special words indicate constant values (values that never change):

| Constant | Value |
|----------|-------|
| TRUE     | 1     |
| FALSE    | 0     |
| PI       | 3.14159... |
| NULL     | (empty value) |
| ERROR    | (error value) |

# References

Sometimes, a formula is calculated for a specific row. You may then refer to any of the values in that row. 

In order to refer to a value in another column, you put the column name between '[@' and ']', like so:

````
[@column]
````

You can use the special '@' identifier to refer to the previous value in the current cell (note that this value is not always available, for instance if you are calculating a new column).


In cases where two data sets are joined together, it is possible to refer to values in a row from either table. In that case, you use the #' sign instead of the '@' sign in the reference to refer to the 'foreign' row, as follows:

````
[#otherColumn]
````

Note that in cases where a foreign row is present, the '@' identifier will not work.

# Operators

The following operators can be used to perform (mostly mathematical) operations on two values:

| Operator | Description |
|----------|-------------|
a + b | Adds the number a to b |
a - b | Subtracts the number b from a |
a * b | Multiplies the number a with b |
a / b | Divides the number a by b |
a ~ b | Returns the remainder of dividing a by b (modulus) |
a & b | Concatenates two values (e.g. "1&2" will become "12") |
a[b]  | Accesses the b'th value of a (shorthand syntax for calling NTH(a;b)) |

The following operators can be used to compare two values. They all return the 'true' value when the comparison is true, and the false value when the comparison is false:

| Operator | Description |
|----------|-------------|
a = b | a equals b |
a <> b | a does not equal b |
a > b | a is greater than b |
a >= b | a is greater than or equal to b |
a < b | a is smaller than b |
a <= b | a is smaller than or equal to b |
a ~= b | a contains the string b (case-insensitive) |
a ~~= b | a contains the string b (case-sensitive) |
a ±= b | a matches the pattern b (case-insensitive) |
a ±±= b | a matches the pattern b (case-sensitive) |


Operators follow the precedence rules of general mathematics for the mathematical operators. If you want to be sure a certain order is used, use parentheses.

# Functions

A function is a piece of code that takes one or more values and makes it into a new value.  

There are also special functions that do not take any values as input, but still return a value (e.g. the current time or a random number). 

You call a function by specifying its name followed then an opening and closing parenthesis. It does not matter if the name is spelled in capitals or in lowercase characters, or even a mixture. 

To pass a value to a function; put it between the parentheses. For instance:

````
SQRT(9)
````

The 'SQRT' function calculates the square root of the value given to it. In this case, it will result in '3'.

If you want to pass more than one value (which some functions support), you separate the values with semicolons, as follows:

````
MIN(1; 3; 4; 6)
````

The 'MIN' function returns the smallest value passed to it - in this case it will result in '1'. Note that the spaces between the semicolons and the following number are completely optional.

## List of available functions

| Function|Description|
|---------|-----------|
|[ABS](#abs)(x)|Absolute value of x
|[ACOS](#acos)(x)|Arc cosine of x
|[AFTER](#after)(d; s)|Add s seconds to date d
|[AND](#and)(x; y; ...)|Logical and
|[ASIN](#asin)(x)|Arc sine of x
|[ATAN](#atan)(x)|Arc tangens of x
|[AVERAGE](#average)(x; y; ...)|Average of values
|[CEILING](#ceiling)(x)|Round x up to nearest integer
|[CHOOSE](#choose)(i; x; y; ...)|Return the i'th argument (excluding i itself)
|[COALESCE](#coalesce)(x; y)|Return y if x is empty; otherwise return x
|[CONCAT](#concat)(x; y; ...)|Concatenate strings
|[COS](#cos)(x)|Cosine of x
|[COSH](#cosh)(x)|Hyperbolic cosine of x
|[COUNT](#count)(x; y; ...)|Return the number of numeric arguments
|[COUNTA](#counta)(x; y; ...)|Return the number of arguments
|[DATE.UTC](#date.utc)(y; m; d)|Returns the date corresponding to the given year y; month m and day d in UTC
|[DAY.UTC](#day.utc)(d)|Returns the day in the month in UTC of date d
|[DURATION](#duration)(x; y)|Returns the duration of the period between dates x and y in seconds
|[ENCODEURL](#encodeurl)(s)|URL-encodes the given string
|[EXP](#exp)(x)|Returns e to the power of x
|[FLOOR](#floor)(x)|Round x down to nearest integer
|[FROM.JSON](#from.json)(s)|Parses the specified JSON string, converting arrays and objects to a [pack](pack.md)
|[FROM.EXCELDATE](#from.exceldate)(s)|Returns a date from the Excel serial date s
|[FROM.ISO8601](#from.iso8601)(s)|Returns a date from the given ISO-8601 formatted date string s
|[FROM.UNIX](#from.unix)(s)|Returns a date from the given UNIX timestamp s
|[HOUR.UTC](#hour.utc)(d)|Returns the hour in UTC of date d
|[IF](#if)(condition; if_true; if_false)|Evaluate boolean condition
|[IFERROR](#iferror)(x; y)|Returns x; or y if x is an error value
|[IN](#in)(v; x; y; ...)|Return whether v is equal to one of the arguments (excluding v)
|[ITEMS](#items)(p)|Returns the number of items in pack p
|[LARGE](#large)(x; y; ...)|Returns the largest value among the arguments
|[LEFT](#left)(s; n)|Return the n leftmost characters in string s
|[LENGTH](#length)(s)|Return the length of string s
|[LN](#ln)(x)|Natural logarithm of x
|[LOG](#log)(x[; y])|Logarithm of x; optionally in base y (default: 10)
|[LOWER](#lower)(x)|Make string x loewrcase
|[MAX](#max)(x; y; ...)|Return the highest argument
|[MEDIAN](#median)(x; y; ...)|Return the median argument (average in case of a tie)
|[MEDIAN.HIGH](#median.high)|Return the median argument (highest in case of a tie)
|[MEDIAN.LOW](#median.low)|Return the median argument (lowest in case of a tie)
|[MEDIAN.PACK](#median.pack)|Return the median argument (pack of both in case of a tie)
|[MID](#mid)(t; s; l)|Return substring of t starting at index s and length l
|[MIN](#min)(x; y; ...)|Return the lowest argument
|[MINUTE.UTC](#minute.utc)(d)|Return the minute in UTC of date d
|[MONTH.UTC](#month.utc)(d)|Return the month in UTC of date d
|[NEGATE](#negate)(x)|Negate x
|[NORM.INV](#norm.inv)(p; m; s)|Return the inverse normal value for probability p; average m and standard deviation s
|[NOT](#not)(x)|Logical not
|[NOT.IN](#not.in)(v; x; y; ...)|Returns whether v does not appear in x; y; ...
|[NOW](#now)|The current date
|[NTH](#nth)(p; i)|Returns the i'th value in pack p
|[OR](#or)(x; y; ...)|Logical OR of arguments
|[PACK](#pack)(x; y; ...)|Create a pack value of the arguments
|[POWER](#power)(x; y)|x to the y'th power
|[PROPER](#proper)(s)|capitalize string s
|[RAND](#rand)|Random number between 0 and 1
|[RANDBETWEEN](#randbetween)(x; y)|Random number between x and y
|[RANDSTRING](#randstring)(p)|Random string using pattern
|[READ.DATE](#read.date)(s; f)|Convert string s to date using format f
|[REPLACE](#replace)(s; x; y)|Replace x with y in string s
|[REPLACE.PATTERN](#replace.pattern)(t; x; y)|Replace instances of pattern x with y in string t
|[RIGHT](#right)(s; n)|Return the n rightmost characters from string s
|[ROUND](#round)(x; d)|Rounds x to d decimals
|[SECOND.UTC](#second.utc)(d)|Returns the seconds in UTC for date d
|[SIGN](#sign)(x)|Returns the sign of x (-1 for negative; 1 for positive; 0 for zero)
|[SIMILARITY](#similarity)(x; y)|Returns the Levenshtein similarity for strings x and y
|[SIN](#sin)(x)|Sine of x
|[SINH](#sinh)(x)|Hyperbolic sine of x
|[SMALL](#small)(x; y; ...)|Return the lowest parameter
|[SPLIT](#split)(t; s)|Split string t using separator s; returns a pack
|[SQRT](#sqrt)(x)|Square root of x
|[STDEV.P](#stdev.p)(x; y; ...)|Standard population deviation of arguments
|[STDEV.S](#stdev.s)(x; y; ...)|Standard sample deviation of arguments
|[SUM](#sum)(x; y; ...)|The sum of all arguments
|[TAN](#tan)(x)|Tangens of x
|[TANH](#tanh)(x)|Tangens hyperbolicus of x
|[TO.EXCELDATE](#to.exceldate)(d)|Returns the Excel serial date for date d
|[TO.ISO8601](#to.iso8601)(d)|Convert date d to an ISO-8601 formatted date in the local timezone
|[TO.ISO8601.UTC](#to.iso8601.utc)(d)|Convert date d to an ISO-8601 formatted UTC date
|[TO.UNIX](#to.unix)(d)|Convert date d to a UNIX timestamp
|[TRIM](#trim)(x)|Remove leading and trailing whitespace from string x
|[UPPER](#upper)(x)|Make string x uppercase
|[UUID](#uuid)|Generate a new UUID
|[VAR.P](#var.p)(x; y; ...)|Return population variance of arguments
|[VAR.S](#var.s)(x; y; ...)|Return sample variance of arguments
|[WRITE.DATE](#write.date)(d; f)|Write date d to string in format f
|[XOR](#xor)(x; y)|Exclusive logical or
|[YEAR.UTC](#year.utc)(d)|Get year in UTC of date d

# Interpretation

When calculating the result of a formula, Warp will automatically convert numeric values to text, and the other way around. This means that the following formulas will calculate:

````
"1"+2 results in 3
1&2 results in "12"
````

# Translation of formulas

For convenience, formulas are translated into the language set in Warp's settings screen. Note that translation is completely transparent: it is safe to create a formula in one language, and edit it in another. Translation affects the following things:

* Function names
* Constant names
* Number formatting (in particular what is considered the decimal and thousand separator)
* The character used to separate arguments to functions