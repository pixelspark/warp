/* Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT double WarpConduitVersionNumber;
FOUNDATION_EXPORT const unsigned char WarpConduitVersionString[];

#include "shapefil.h"
#import "sqlite3.h"
#import "mysql.h"
#import "libpq-fe.h"
#import "CHCSVParser.h"
#import "TCMXMLWriter.h"

/** This function registers the SQLite user-defined functions (UDF) for mathematical operations, as implemented in
 extension-functions.c. It needs to be defined here so it can be called from Swift. **/
int RegisterExtensionFunctions(sqlite3 *db);

sqlite3_destructor_type sqlite3_transient_destructor;

/** These functions allow for the creation of Swift user-defined functions in SQLite. The functions are implemented in
 QBEObjectiveCBridge.m. **/
typedef void (^SQLiteUDF)(sqlite3_context * context, int argc, sqlite3_value ** argv);
int SQLiteCreateFunction(sqlite3 * handle, const char * name, int argc, BOOL deterministic, SQLiteUDF callback);

@interface CHCSVParser (QBE)
- (BOOL) _parseRecord;
- (void) _beginDocument;
- (void) _endDocument;
@end
