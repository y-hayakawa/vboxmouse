/*
  VBoxMouse: VirtualBox Mouse Driver for NEXTSTEP 3.3(Intel)
  (c) 2025, Yoshinori Hayakawa

  Version 0.91 (2025-06-20)
*/

#ifndef __VBOXMOUSE_H__
#define __VBOXMOUSE_H__

#import "VBoxDefines.h"

#import "VBMouseConfig.h"

#define DRIVER_PRIVATE
#import "PCPointer.h"
#undef DRIVER_PRIVATE

#import <driverkit/i386/IOPCIDirectDevice.h>

struct rect {
  short   x;
  short   y;
  short   width;
  short   height;
  id lock ;
} ;
 
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

  @private
  struct rect desktopBounds;      
}

- (BOOL)mouseInit: deviceDescription;
- free;
- (void)interruptOccurred;
- (BOOL)readConfigTable:configTable;

@end

#endif	// __VBOXMOUSE_H__
