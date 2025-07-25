/* Generated by Project Builder */

#import <objc/Object.h>

@interface VBoxPB:Object
{
	id statusScrollView;
    id text ;
    id window ;
    id infoPanel ;

    DPSTimedEntry pasteboardTE ;

    IODeviceMaster  *master;
    IOObjectNumber  objectNumber;
    Pasteboard      *pboard;
    int             lastCountNS;
    int             lastCountVB ;
    int kanjiMode ;
    int vboxBufferLength;
    int fd ;
}

- init;
- connect;
- (void)checkNsClipboard;
- (void)checkVBoxClipboard;
- (void)setMode:(int)kanjiMode;

- showInfo:sender ;

- appendToText:(const char*) val ;
- initStatusScrollView ;

- startTE:sender ;
- stopTE:sender ;

@end

@interface VBoxPB(ApplicationDelegate)
- appDidInit:sender ;
@end
