#ifndef QBE_QBEObjectiveCBridge_h
#define QBE_QBEObjectiveCBridge_h

#import "CHCSVParser.h"
#import "TCMXMLWriter.h"
#import <MBTableGrid/MBTableGrid.h>
#import <MBTableGrid/MBTableGridHeaderView.h>
#import <MBTableGrid/MBTableGridFooterView.h>
#import <MBTableGrid/MBTableGridCell.h>

#import "sqlite3.h"
#import "mysql.h"
#import "ltqnorm.h"
#import "libpq-fe.h"

/** This function registers the SQLite user-defined functions (UDF) for mathematical operations, as implemented in
 extension-functions.c. It needs to be defined here so it can be called from Swift. **/
int RegisterExtensionFunctions(sqlite3 *db);

/** These functions allow for the creation of Swift user-defined functions in SQLite. The functions are implemented in
QBEObjectiveCBridge.m. **/
typedef void (^SQLiteUDF)(sqlite3_context * context, int argc, sqlite3_value ** argv);
int SQLiteCreateFunction(sqlite3 * handle, const char * name, int argc, BOOL deterministic, SQLiteUDF callback);

@interface CHCSVParser (QBE)
- (BOOL) _parseRecord;
- (void) _beginDocument;
- (void) _endDocument;
@end

#endif