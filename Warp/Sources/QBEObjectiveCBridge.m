#import <Foundation/Foundation.h>
#import "QBEObjectiveCBridge.h"

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
