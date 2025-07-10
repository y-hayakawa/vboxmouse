/*
  Yoshinori Hayakawa
  2025-07-08
*/

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

#include "jconv.h"

static const IOParameterName kClipboardParam = "VBoxClipboardData";

#define VBMOUSE_DEV_NAME "VBoxMouse"

#undef DEBUG

#define VBOXPB_DEV_PATH "/dev/vboxpb"

@interface PasteboardDaemon : Object {
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
- (void)checkNsClipboard;
- (void)checkVBoxClipboard;
- (void)setMode:(int)kanjiMode;
@end

@implementation PasteboardDaemon

- init {
  int ret ;
  IOObjectNumber tag;
  IOString kind;
  int param_buf[16],len ;

  self = [super init];
  master = [[IODeviceMaster new] retain];

  ret = [master lookUpByDeviceName:VBMOUSE_DEV_NAME objectNumber:&tag deviceKind:&kind] ;
  if (ret!=0) {
    NSLog(@"PBDaemon - Failed to open device %s",VBMOUSE_DEV_NAME);
    exit(1);
  }

  objectNumber = tag ;
    
  pboard = [[Pasteboard new] retain];
  [pboard declareTypes:&NXAsciiPboardType num:1 owner:self];
  lastCountNS = [pboard changeCount];
  lastCountVB = -1 ;

  len=2 ;
  ret = [master getIntValues:param_buf
                forParameter:kClipboardParam
                objectNumber:objectNumber
                count:&len];

  if (ret==IO_R_SUCCESS) {
      if (len>=2) {
          if (param_buf[1]>=8192) {
              vboxBufferLength = param_buf[1] ;
              NSLog(@"PBDaemon - Buffer length=%d\n",vboxBufferLength) ;
          } else {
              NSLog(@"PBDaemon - VBoxMouse driver seems not working properly\n") ;
              exit(1) ;
          }
      } else {
          NSLog(@"PBDaemon - Cound not obtain the buffer length from VBoxMouse driver\n") ;
          exit(1) ;
      }
  } else {
      NSLog(@"PBDaemon - Failed to communicate with VBoxMouse driver\n") ;
      exit(1) ;
  }

  fd = open(VBOXPB_DEV_PATH, O_RDWR) ;
  if (fd<0) {
      NSLog(@"PBDaemon - Error opening %s (errno=%d)\n",VBOXPB_DEV_PATH,errno) ;
      exit(1) ;
  }

  return self;
}

- (void) setMode:(int)mode {
    kanjiMode = mode ;
    NSLog(@"PBDaemon - kanjiMode=%d\n",mode) ;
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
#ifdef DEBUG
          fprintf(stderr,"wrote %d bytes out of %d\n",ret,outbuf_len) ;
#endif
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
    int cnt ;
    IOReturn ret ;

    len = 2 ;
    ret = [master getIntValues:param_buf
                  forParameter:kClipboardParam
                  objectNumber:objectNumber
                  count:&len];

    if (ret==IO_R_SUCCESS) {
        inbuf = (char *) malloc(vboxBufferLength) ;
#ifdef DEBUG
        fprintf(stderr,"count VB %ld  daemon %ld\n",param_buf[0],lastCountVB) ;
#endif
        if (param_buf[0] > lastCountVB) { // got new data
            lastCountVB = param_buf[0] ; // update count
            inbuf_len = read(fd,inbuf,vboxBufferLength) ;
#ifdef DEBUG
            fprintf(stderr,"inbuf_len=%ld\n",inbuf_len) ;
#endif
            if (inbuf_len < 0) {
                NSLog(@"PBDaemon - Error while reading data errno=%d\n",errno) ;
            } 
            if (inbuf_len > 0 && inbuf_len < vboxBufferLength) {
                int res = 0 ;
#ifdef DEBUG
                fprintf(stderr,"GOT %ld bytes\n",inbuf_len) ;
#endif
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
                if (outbuf[outbuf_len-1]==0) outbuf_len-- ;

                NX_DURING
                    [pboard declareTypes:&NXAsciiPboardType num:1 owner:self];
                    ret = [pboard writeType:NXAsciiPboardType
                                  data:outbuf
                                  length:outbuf_len] ;
                NX_HANDLER
                    switch(NXLocalHandler.code) {
                    case NX_pasteboardComm:
                        NSLog(@"PBDaemon: pasteboard comm error\n") ;
                    }
                NX_ENDHANDLER
                lastCountNS = [pboard changeCount] ; // don't write back this to VBox
                if (res==0) free(outbuf) ;
            }
        }
        free(inbuf) ;
    }
}

@end


static void usage(const char *prog) {
  fprintf(stderr,
	  "Usage: %s [ -u8 | -u16 | -d]\n"
	  "  -u8      VirtualBox host uses UTF-8\n"
	  "  -u16     VirtualBox host uses UTF-16LE(default)\n"
	  "  -d       Daemonize\n",          
	  prog);
  exit(1);
}

int main(int argc, char *argv[]) {
    PasteboardDaemon *daemon ;
    int opt;
    int kanji_mode  = MODE_UTF16LE;
    size_t in_len;
    unsigned char *in_buf ;
    unsigned char *out_buf;
    size_t out_buf_len;
    int r ;
    int daemon_mode = 0 ;
  
    while ((opt = getopt(argc, argv, "u:d")) != -1) {
        switch (opt) {
        case 'u':
            if (strcmp(optarg, "8") == 0)       kanji_mode = MODE_UTF8;
            else if (strcmp(optarg, "16") == 0) kanji_mode = MODE_UTF16LE;
            else usage(argv[0]);
            break;
        case 'd':
            daemon_mode = 1;
            break;
        default:
            usage(argv[0]);
        }
    }

    if (daemon_mode) {
        int pid = fork();
        if (pid < 0) {
            perror("fork");
            exit(1);
        }

        if (pid > 0) {
            exit(0);
        }

        if (setpgrp(0,0) < 0) {
            perror("setpgrp");
            exit(1) ;
        } 
        chdir("/");  
        umask(0);    
        close(0);
        close(1);
        close(2);
    }

    daemon = [[PasteboardDaemon new] retain];

    [daemon setMode:kanji_mode] ;
    while (1) {
        [daemon checkNsClipboard];
        [daemon checkVBoxClipboard];
        usleep(500 * 1000);  // 0.5 sec
    }
    return 0;
}
