Blobs are opaque binary values.

# Expressing blobs

Blobs are expressed in formulas as base64-encoded strings between backtick quotes, e.g. 
````
`aGvsbG8=`
````

# Working with blobs

## Creating blobs

The following functions can be used to create blobs:

| Function|Description|
|---------|-----------|
|ENCODE(s; encoding)|Encodes the string s in the specified encoding and return as blob|
|BASE64.DECODE(s)|Decode the string s as base64 and return as blob|
|HEX.DECODE(s)|Decode the string s as hex string and return as blob|

## Reading blobs

| Function|Description|
|---------|-----------|
|DECODE(b; encoding)|Decode the blob b in the specified encoding and return the decoded string|
|BASE64.ENCODE(b)|Encode the blob b as base64 string|
|HEX.ENCODE(b)|Encode the blob b as hex string|
|SIZE.OF(b)|Returns the size of blob b in bytes|

### String encodings

The string encodings supported by Warp are the following:

| Encoding name |Description|
|---------|-----------|
| "UTF-8" | Unicode UTF-8 |
| "UTF-16" | Unicode UTF-16 |
| "UTF-32" | Unicode UTF-32 |
| "ASCII" | ASCII |
| "LATIN1" | ISO Latin-1 |
| "LATIN2" | ISO Latin-2 |
| "MAC-ROMAN" | macOS Roman |
| "CP1250" | Windows codepage 1250 |
| "CP1251" | Windows codepage 1251 |
| "CP1252" | Windows codepage 1252 |