#ifndef QBE_QBEObjectiveCBridge_h
#define QBE_QBEObjectiveCBridge_h

#import "CHCSVParser.h"
#import <MBTableGrid/MBTableGrid.h>
#import "sqlite3.h"
#endif

@interface CHCSVParser (QBE)
- (BOOL) _parseRecord;
- (void) _beginDocument;
- (void) _endDocument;
@end