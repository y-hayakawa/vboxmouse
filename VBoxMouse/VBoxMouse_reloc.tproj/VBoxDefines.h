#ifndef __VBOX_DEFINES_H__
#define __VBOX_DEFINES_H__

#define VBOX_VENDOR_ID 0x80EE
#define VBOX_DEVICE_ID 0xCAFE

#define VBOX_VMMDEV_VERSION 0x00010004
#define VBOX_REQUEST_HEADER_VERSION 0x10001

#define VBOX_REQUEST_GET_MOUSE 1
#define VBOX_REQUEST_SET_MOUSE 2
#define VBOX_REQUEST_ACK_EVENTS 41
#define VBOX_CTL_GUEST_FILETER_MASK 42
#define VBOX_REQUEST_GUEST_INFO 50
#define VBOX_REQUEST_GET_DISPLAY_CHANGE2 54
#define VBOX_REQUEST_SET_GUEST_CAPS 55
#define VBOX_REQUEST_REP_GUEST_STATUS 59
#define VBOX_REQUEST_GET_MOUSE_EX 223

#define MOUSE_BUTTON_LEFT   0x0001
#define MOUSE_BUTTON_RIGHT  0x0002
#define MOUSE_BUTTON_MIDDLE 0x0004

struct vbox_header {
  unsigned long size;
  unsigned long version ;
  unsigned long requestType ;
  long rc ;
  unsigned long reserved1 ;
  unsigned long reserved2 ;
};

struct vbox_guest_info {
  struct vbox_header header ;
  unsigned long version ;
  unsigned long ostype ;
} ;

struct vbox_filter_mask {
  struct vbox_header header ;
  unsigned long ormask ;  // events to be added
  unsigned long notmask ;  // events to be removed
};

struct vbox_mouse_absolute {
  struct vbox_header header ;
  unsigned long features;
  long x ;
  long y ;
};

struct vbox_mouse_absolute_ex {
  struct vbox_header header ;
  unsigned long features;
  long x ;
  long y ;
  // extended feature
  long dz ;
  long dw ;
  unsigned long buttons;
};

#define VMMDEV_MOUSE_BUTTON_LEFT  (1<<0)
#define VMMDEV_MOUSE_BUTTON_RIGHT (1<<1)
#define VMMDEV_MOUSE_BUTTON_MIDDLE (1<<2)

struct vbox_guest_caps {
  struct vbox_header header ;
  unsigned long caps ;
};

struct guest_status {
  unsigned long facility ;
  unsigned long status ;
  unsigned long flags ;
} ;

struct vbox_guest_status {
  struct vbox_header header ;
  struct guest_status guest_status ;
};

struct vbox_ack_events {
  struct vbox_header header ;
  unsigned long events ;
} ;

struct vbox_display_change2 {
  struct vbox_header header ;
  unsigned long xres ;
  unsigned long yres ;
  unsigned long bpp ;
  unsigned long event_ack ;
  unsigned long display ;
} ;

#endif // __VBOX_DEFINES_H__
