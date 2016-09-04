/** Copyright (c) 2014-2016 Pixelspark, Tommy van der Vorst

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
#import <WarpConduit/WarpConduit.h>

void SQLiteUDFCaller(sqlite3_context * context, int argc, sqlite3_value ** argv) {
	((__bridge SQLiteUDF)sqlite3_user_data(context))(context, argc, argv);
}

void SQLiteUDFDestroy(void* context) {
	CFBridgingRelease(context);
}

sqlite3_destructor_type sqlite3_transient_destructor = SQLITE_TRANSIENT;

/** Create a SQLite user-defined function with the given (Swift) callback as implementing function. We actually register
 SQLiteUDFCaller as the function handler with SQLite. SQLiteUDFCaller will look up the Swift callback (to which a pointer
 has been stored as 'user data' in the SQLite function context) and execute it.

 This trick was 'borrowed' from Stephen Celis' SQLite.swift.
 See https://github.com/stephencelis/SQLite.swift/blob/master/SQLite/SQLite-Bridging.c
 **/
int SQLiteCreateFunction(sqlite3 * handle, const char * name, int argc, BOOL deterministic, SQLiteUDF callback) {
	if (callback) {
		int flags = SQLITE_UTF8;
		if (deterministic) {
			flags |= SQLITE_DETERMINISTIC;
		}
		return sqlite3_create_function_v2(handle, name, argc, flags, (__bridge_retained void*)(callback), &SQLiteUDFCaller, 0, 0, &SQLiteUDFDestroy);
	}
	else {
		return sqlite3_create_function_v2(handle, name, 0, 0, 0, 0, 0, 0, 0);
	}
}
