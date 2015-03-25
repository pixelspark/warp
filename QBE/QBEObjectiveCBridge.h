#ifndef QBE_QBEObjectiveCBridge_h
#define QBE_QBEObjectiveCBridge_h

#import "CHCSVParser.h"
#import <MBTableGrid/MBTableGrid.h>
#import <MBTableGrid/MBTableGridCell.h>
#import "sqlite3.h"
#import "mysql.h"

#import "ltqnorm.h"

int RegisterExtensionFunctions(sqlite3 *db);

@interface CHCSVParser (QBE)
- (BOOL) _parseRecord;
- (void) _beginDocument;
- (void) _endDocument;
@end

#endif