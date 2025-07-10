/*
  VBoxMouse: VirtualBox Mouse Driver for NEXTSTEP 3.3(Intel)
  (c) 2025, Yoshinori Hayakawa

  Version 0.92 (2025-07-08)
*/

#ifndef __VBOXMOUSE_H__
#define __VBOXMOUSE_H__

#import "VBoxDefines.h"

#import "VBMouseConfig.h"

#define DRIVER_PRIVATE
#import "PCPointer.h"
#undef DRIVER_PRIVATE

#import <driverkit/i386/IOPCIDirectDevice.h>
#import <mach/mach_types.h>

#define PARAMETER_NAME "VBoxClipboardData"

struct rect {
    short   x;
    short   y;
    short   width;
    short   height;
    id lock ;
} ;

struct pb_data {
    // buffer for VBox --> NS33
    unsigned char *pb_read_buffer ;
    unsigned long pb_read_buffer_len ;
    unsigned int pb_read_buffer_phys ;
    // buffer for NS --> VBox
    unsigned char *pb_write_buffer ;
    unsigned long pb_write_buffer_len ;
    unsigned int pb_write_buffer_phys ;
    int pb_got_new_data_to_write ;
    long int client_id ;
    unsigned int count ;
    IOEISAPortAddress vbox_port ;
    volatile BOOL terminate ;
    id lock ;
} ;

// 64k seems to be the maximum
// string length in pasteboard is limited up to a half of this number
#define MAX_BUFFER_LEN 65536

#define CHAR_MAJOR 21
 
@interface VBoxMouse : PCPointer {
    struct vbox_mouse_absolute_ex *vbox_mouse;
    unsigned int vbox_mouse_phys ;

    struct vbox_guest_info *guest_info ;
    unsigned int guest_info_phys ;

    struct vbox_ack_events *vbox_ack ;
    unsigned int vbox_ack_phys ;

    struct vbox_guest_caps *vbox_guest_caps ;
    unsigned int vbox_guest_caps_phys ;

    struct vbox_guest_status *vbox_guest_status ;
    unsigned int vbox_guest_status_phys ;

    struct vbox_filter_mask *vbox_filter_mask;
    unsigned int vbox_filter_mask_phys ;

    struct vbox_display_change2 *vbox_display_change2;
    unsigned int vbox_display_change2_phys ;

    unsigned long * vbox_vmmdev ;
    unsigned int irqlevel ;
    IOEISAPortAddress vbox_port ;

    struct hgcm_connect * hgcm_connect ;
    unsigned int hgcm_connect_phys ;

    struct hgcm_disconnect * hgcm_disconnect ;
    unsigned int hgcm_disconnect_phys ;

    struct hgcm_call * hgcm_call ;
    unsigned int hgcm_call_phys ;

    struct hgcm_call * hgcm_write_call ;
    unsigned int hgcm_write_call_phys ;

    struct hgcm_cancel * hgcm_cancel ;
    unsigned int hgcm_cancel_phys ;

    struct rect desktopBounds;      
}

- (BOOL)mouseInit: deviceDescription;
- free;
- (void)interruptOccurred;

- (BOOL)initHGCM ;
- (BOOL)connectHGCM ;
- (BOOL)disconnectHGCM ;
- (void)freeHGCM ;
- (BOOL)setPBFormat;

- (BOOL)readConfigTable:configTable;

- (IOReturn)getIntValues:(unsigned int *)array forParameter:(IOParameterName)parameter count:(unsigned int *)count ;

@end

#endif	// __VBOXMOUSE_H__
