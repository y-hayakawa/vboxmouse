/*
  Yoshinori Hayakawa
  2025-07-14
*/

#import <appkit/appkit.h>
#import <appkit/Pasteboard.h>
#import <appkit/errors.h>
#import <driverkit/IODeviceMaster.h>
#import <foundation/NSArray.h>
#include <unistd.h>  // for usleep
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <bsd/libc.h>
#include <stdarg.h>

#include "jconv.h"

static const IOParameterName kClipboardParam = "VBoxClipboardData";
#define VBMOUSE_DEV_NAME "VBoxMouse"
#undef DEBUG
#define VBOXPB_DEV_PATH "/dev/vboxpb"

#import "VBoxPB.h"
#import "PrefsController.h"

@implementation VBoxPB

void PRINT_LOG(void* data, const char *fmt, ...)
{
    char buf[1024];
    id obj = (id) data ;
    va_list ap;
    va_start(ap, fmt);
    vsprintf(buf, fmt, ap);
    va_end(ap);
    [obj appendToText: buf] ;
}

- init
{
    return [super init] ;
}

- connect
{
  int ret ;
  IOObjectNumber tag;
  IOString kind;
  int param_buf[16],len ;

  master = [[IODeviceMaster new] retain];

  PRINT_LOG(self,"Starting VBoxPB...\n");

  ret = [master lookUpByDeviceName:VBMOUSE_DEV_NAME objectNumber:&tag deviceKind:&kind] ;
  if (ret!=0) {
      PRINT_LOG(self,"Failed to open device %s",VBMOUSE_DEV_NAME);
      return nil ;
  }

  objectNumber = tag ;
    
  pboard = [[Pasteboard new] retain];
  [pboard declareTypes:&NXAsciiPboardType num:1 owner:self];
  lastCountNS = [pboard changeCount];
  lastCountVB = 0 ;

  len=2 ;
  ret = [master getIntValues:param_buf
                forParameter:kClipboardParam
                objectNumber:objectNumber
                count:&len];

  vboxBufferLength=0 ;
  if (ret==IO_R_SUCCESS) {
      if (len>=2) {
          if (param_buf[1]>=8192) {
              vboxBufferLength = param_buf[1] ;
              PRINT_LOG(self,"Buffer length=%d\n",vboxBufferLength) ;
          } else {
              PRINT_LOG(self,"VBoxMouse driver seems not working properly %d\n",param_buf[1]) ;
              return nil ;
          }
      } else {
          PRINT_LOG(self,"Cound not obtain the buffer length from VBoxMouse driver\n") ;
          return nil ;
      }
  } else {
      PRINT_LOG(self,"Failed to communicate with VBoxMouse driver\n") ;
      return nil ;
  }

  fd = open(VBOXPB_DEV_PATH, O_RDWR) ;
  if (fd<0) {
      PRINT_LOG(self,"Error opening %s (errno=%d)\n",VBOXPB_DEV_PATH,errno) ;
      return nil ;
  }

  return self;
}

- (void) setMode:(int)mode {
    kanjiMode = mode ;
    PRINT_LOG(self,"kanjiMode=%d\n",mode) ;
}

- (void)checkNsClipboard {
    int cnt ;
    char *outbuf ;
    int  outbuf_len ;
    IOReturn ret ;
    NXAtom *types;
    char *data ;
    int len ;
    id ret_pb ;
    int param_buf[10] ;

    cnt = [pboard changeCount] ;

    if (cnt > lastCountNS) {
      lastCountNS = cnt;
      types = [pboard types];
      ret_pb = nil ;
      len = 0 ;
      while (*types) {
          if (*types == NXAsciiPboardType) {
              ret_pb = [pboard readType:*types
                               data:&data 
                               length:&len ] ;
              break ;
          }
          types++;
      }
      if (ret_pb != nil && len>0) {
          int res = 0 ;
          if (kanjiMode==MODE_UTF8) { 
              res = eucjp_to_utf8(data, len, &outbuf, &outbuf_len) ;
              outbuf = (unsigned char *) realloc(outbuf,outbuf_len+1) ;
              outbuf[outbuf_len] = 0 ; // must be NULL terminated
              outbuf_len = outbuf_len + 1 ;
          } else if (kanjiMode==MODE_UTF16LE) {
              res = eucjp_to_utf16le(data, len, &outbuf, &outbuf_len) ;
              outbuf = (unsigned char *) realloc(outbuf,outbuf_len+2) ;
              outbuf[outbuf_len]   = 0 ; // must be NULL terminated
              outbuf[outbuf_len+1] = 0 ; 
              outbuf_len = outbuf_len + 2 ;
          } else {
              outbuf = (unsigned char*) malloc(len+1) ;
              strncpy(outbuf, data, len-1) ;
              outbuf[len] = 0 ; // must be NULL terminated
              outbuf_len = len+1 ;
          }
          ret = write(fd,outbuf,outbuf_len) ;
          PRINT_LOG(self,"Sent %d characters to VirtualBox\n",outbuf_len) ;
          if (res==0) free(outbuf) ;
      }
    }
}

- (void)checkVBoxClipboard {
    char *inbuf ;
    int  inbuf_len ;
    char *outbuf ;
    int  outbuf_len ;
    int len;
    int param_buf[10] ;
    IOReturn ret ;

    len = 2 ;
    ret = [master getIntValues:param_buf
                  forParameter:kClipboardParam
                  objectNumber:objectNumber
                  count:&len];

    if (ret==IO_R_SUCCESS) {
        inbuf = (char *) malloc(vboxBufferLength) ;
        if (param_buf[0] > lastCountVB) { // got new data
            lastCountVB = param_buf[0] ; // update count
            inbuf_len = read(fd,inbuf,vboxBufferLength) ;
            if (inbuf_len < 0) {
                PRINT_LOG(self,"Error while reading data errno=%d\n",errno) ;
            } 
            if (inbuf_len > 0 && inbuf_len <= vboxBufferLength) {
                int res = 0 ;
                if (kanjiMode==MODE_UTF8) { 
                    res = utf8_to_eucjp(inbuf, inbuf_len, &outbuf, &outbuf_len) ;
                } else if (kanjiMode==MODE_UTF16LE) {
                    res = utf16le_to_eucjp(inbuf, inbuf_len, &outbuf, &outbuf_len) ;
                } else {
                    outbuf = (unsigned char*) malloc(inbuf_len) ;
                    outbuf_len = inbuf_len ;
                    strncpy(outbuf,inbuf,inbuf_len) ;
                }
                // delete null at the tail
                while (outbuf_len>0 && outbuf[outbuf_len-1]==0) outbuf_len-- ;

                PRINT_LOG(self,"Recieved %d characters from VirtualBox\n",outbuf_len) ;

                NX_DURING
                    [pboard declareTypes:&NXAsciiPboardType num:1 owner:self];
                    ret = [pboard writeType:NXAsciiPboardType
                                  data:outbuf
                                  length:outbuf_len] ;
                NX_HANDLER
                    switch(NXLocalHandler.code) {
                    case NX_pasteboardComm:
                        PRINT_LOG(self,"PBDaemon: pasteboard comm error\n") ;
                    }
                NX_ENDHANDLER
                lastCountNS = [pboard changeCount] ; // don't write back this to VBox
                if (res==0) free(outbuf) ;
            }
        }
        free(inbuf) ;
    }
}

- showInfo:sender
{
    if (!infoPanel) {
        [NXApp loadNibSection:"Info.nib" owner:self withNames:NO];
    }
    [infoPanel makeKeyAndOrderFront:sender];
    return self ;
}

void pb_handler(DPSTimedEntry teNumber, double now, void *data) {
    id obj = (id) data ;
    [obj checkNsClipboard];
    [obj checkVBoxClipboard];
}

- startTE:sender
{
    pasteboardTE = DPSAddTimedEntry(0.5, (DPSTimedEntryProc)pb_handler, self, NX_BASETHRESHOLD) ;
    return self ;
}

- stopTE:sender
{
    DPSRemoveTimedEntry(pasteboardTE) ;
    return self ;
}

- appendToText:(const char*) val
{
    int length = [text textLength] ;
    [window setDocEdited:YES] ;
    [text setSel:length :length] ;
    [text replaceSel:val] ;
    [text scrollSelToVisible] ;
    [text display] ;
    return self ;
}

- initStatusScrollView
{
    text = [statusScrollView docView] ;
    [text setDelegate:self] ;
    [text setCharFilter:NXFieldFilter] ;
    [text selectAll:self] ;
    return self ;
}

@end



@implementation VBoxPB(ApplicationDelegate)
- appDidInit:sender
{
    id ret ;
    [self initStatusScrollView] ;
    ret = [self connect] ;
    if (ret != nil) {
        [self setMode:MODE_UTF16LE];
        [self startTE:self];
        if (strcmp(NXGetDefaultValue([NXApp appName],"NXAutoLaunch"),"YES")==0) {
            [NXApp hide:self] ;
        } ;
    }
    return self ;
}
@end


