A pack is a list of values saved as a string. Packs are used when multiple values need to be saved in a single cell, but need to be split later on.

## Creating a pack

Values in a pack are separated by a comma. The following is a pack of the values 'foo', 'bar' and 'baz':

````
foo,bar,baz
````

If a value contains a comma, there is an issue with interpretation: is the comma part of the value, or does it separate two values? In order to overcome this issue, the pack format 'escapes' commas present inside values by replacing them with the text "$0". Because it should also be possible to have "$0" as value, the dollar sign itself is written as "$1".

In Warp, you can use the 'PACK' function to create a pack:

````
=PACK.VALUES("foo";"bar";"baz") will return "foo,bar,baz"
=PACK.VALUES("foo,bar";"baz") will return "foo$0bar,baz"
````

## Extracting values from a pack

In Warp, you can use the UNPACK function to unpack a pack into a list. After that, you can access elements in the list using square brackets.This will return the value at the specified index in the pack, or return an invalid value if that index does not exist.

````
=UNPACK("foo,bar,baz")[2] will return "bar"
````

## Key-value pairs

Packs can also be used to store key-value pairs: simply alternate the keys and values in the pack, like so:

````
first_name,Tommy,last_name,van der Vorst
````

You can use the 'arrow' syntax to extract values:

````
=UNPACK("first_name,Tommy,last_name,van der Vorst")->"first_name" will return "Tommy"
````