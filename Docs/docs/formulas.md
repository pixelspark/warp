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

## Lists

List values are expressed as follows:

````
{"foo";"bar"}
````

Lists can contain values of all types (even other lists), and types may be mixed. An empty list is expressed as ````{}````.

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

In order to refer to a value in another column, you put the column name between '[' and ']', like so:

````
[column]
````

If the column name contains only alphanumeric characters and starts with an alphabetic character, you can omit the brackets:

````
column
````

You can use the special '@' identifier to refer to the previous value in the current cell (note that this value is not always available, for instance if you are calculating a new column).


In cases where two data sets are joined together, it is possible to refer to values in a row from either table. In that case, you use the #' to refer to the 'foreign' row, as follows:

````
#[otherColumn]
#otherColumn
````

Note that in cases where a foreign row is present, the '@' identifier will not work. The shorthand syntax for foreign columns is only applicable to foreign columns that have an alphanumeric name that start with an alphabetic character.

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