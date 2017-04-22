Warp supports values of a list type. A list is a (possibly empty) ordered collection of values, which may be of any type. Lists can hence also be nested.

## Expressing lists

Lists can be accessed using brackets: ````{1,2,3}[2]```` returns the second element, or '2' from the list (lists start counting at '1'). If the  index does not exist, the returned value will be invalid.

If a list contains key-value pairs (e.g. ````{"foo";"bar";"baz";"bam"}```` you can access the value corresponding to a key using the arrow syntax: ````{"foo";"bar";"baz";"bam"}->"baz"```` returns 'bam' in this example. The value returned will be invalid when the indicated  key does not exist.

## Working with lists

The following function can be used to work with lists:

| Function|Description|
|---------|-----------|
|ITEMS(x)|Returns the number of items in list x|
|PACK(x)|Creates a [pack](pack.md) from list x|
|UNPACK(p)|Creates a list from the [pack](pack.md) p|
|APPEND(xs; x1; x2; ...)|Appends items x1, x2, ... to list xs|
|APPEND.LIST(xs; ys1; ys2)|Appends the items in lists ys1, ys2, .. to list xs|
|LIST(x1;x2;..)|Creates a list of items x1, x2, ...|
|GLUE(xs; separator)|Creates a string by joining items in the list together, separated by separator|
|TO.JSON(x)|Formats list x as JSON string|


Note: the above functions all return an invalid value when a list parameters is filled with a value that is not a list. Single values are never implicitly converted to lists and vice-versa.

The following functions produce lists:

| Function|Description|
|---------|-----------|
|FROM.JSON(x)|Returns a list representation of the JSON string x|
|UNPACK(s)|Returns a list by unpacking the pack string s|
|SPLIT(s; separator)|Returns a list of strings by splitting string s by separator|

## JSON and lists

Using the FROM.JSON function, you can parse JSON strings into packs. This is useful when you want to extract specific fields from JSON strings. JSON objects are translated to packs with key-value pairs, whereas arrays are converted to plain list packs. For instance, the following JSON string:

````
{"foo":"bar", "baz":{"deepSpace": 9}}
````

Will be represented as the following list:

````
{"foo"; "bar"; "baz"; {"deepSpace"; 9}}
````

Reading fields from this list is simple:

````
=FROM.JSON("{""foo"":""bar"", ""baz"":{""deepSpace"": 9}}")->"baz"->"deepSpace" will return 9
````