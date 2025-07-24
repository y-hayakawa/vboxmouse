/*
  VBoxMouse: VirtualBox Mouse Driver for NEXTSTEP 3.3(Intel)
  (c) 2025, Yoshinori Hayakawa

  Version 0.94 (2025-07-24)
*/

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


// string length in pasteboard is limited up to a half of this number
#define VBOX_PAGE_SIZE 4096
#define MAX_BUFFER_LEN 65536
// NDIV_BUFFER = MAX_BUFFER_LEN / VBOX_PAGE_SIZE
#define NDIV_BUFFER 16

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

#define VBOX_REQUEST_HGCM_CONNECT 60
#define VBOX_REQUEST_HGCM_DISCONNECT 61
#define VBOX_REQUEST_HGCM_CALL32 62
#define VBOX_REQUEST_HGCM_CALL64 63
#define VBOX_REQUEST_HGCM_CANCEL 64

#define VBOX_SHCL_FMT_UNICODETEXT (1<<0)


struct hgcm_header {
    struct vbox_header header ;
    unsigned long flags ;  // done=1, cancelled=2
    unsigned long result ;
} ;

struct hgcm_connect {
    struct hgcm_header header ;
    int type ;             // 1:additional lib 2:predefined lib
    char host_name[128] ;  // "VBoxSharedClipboard"
    unsigned long client_id ;
} ;

struct hgcm_disconnect {
    struct hgcm_header header ;
    unsigned long client_id ;
} ;

// function_code
#define VBOX_SHCL_GUEST_FN_MSG_OLD_GET_WAIT 1
#define VBOX_SHCL_GUEST_FN_REPORT_FORMATS 2
#define VBOX_SHCL_GUEST_FN_DATA_READ 3
#define VBOX_SHCL_GUEST_FN_DATA_WRITE 4
#define VBOX_SHCL_GUEST_FN_REPORT_FEATURES 6
#define VBOX_SHCL_GUEST_FN_MSG_PEEK_NOWAIT 8
#define VBOX_SHCL_GUEST_FN_MSG_PEEK_WAIT 9
#define VBOX_SHCL_GUEST_FN_MSG_GET 10
#define VBOX_SHCL_GUEST_FN_MSG_CANCEL 26

// message id from host
#define VBOX_SHCL_HOST_MSG_QUIT 1
#define VBOX_SHCL_HOST_MSG_READ_DATA 2
#define VBOX_SHCL_HOST_MSG_FORMATS_REPORT 3
#define VBOX_SHCL_HOST_MSG_CANCELED 4
#define VBOX_SHCL_HOST_MSG_READ_DATA_CID 5

// 12 bytes
struct hgcm_param32 {
    unsigned long type ; // 1:32bit value 4:linear address  10:page list
    unsigned long value0 ; // value0 | buffer length 
    unsigned long value1 ; // value1 | relative pos to page list
} ;

// 16 bytes
struct hgcm_param64 {
    unsigned long type ; // 2:64bit value 4:linear address 10:page list
    unsigned long value0 ; // value0 | buffer length 
    unsigned long value1 ; // value1 | relative pos to page list
    unsigned long value2 ; //        | 0
} ;

struct page_list_info {
    unsigned int flags ;  // direction 1:to_host 2:from_guest 3:both
    unsigned short offset ; // bytes from the top of "struct hgcm_call" to "struct page_list_info"
    unsigned short cpages ;
    unsigned long long pages[NDIV_BUFFER] ; 
} ;

struct hgcm_call {
    struct hgcm_header header ;
    unsigned long client_id ;
    unsigned long function_code ;
    unsigned long cparams ;
    struct hgcm_param32 params[4] ;
    struct page_list_info page_list_info ;
} ;

struct hgcm_call64 {
    struct hgcm_header header ;
    unsigned long client_id ;
    unsigned long function_code ;
    unsigned long cparams ;
    struct hgcm_param64 params[4] ;
    struct page_list_info page_list_info ;
} ;

#define PAGE_LIST_INFO_OFFSET32 (sizeof(struct hgcm_header) + 4*3 + sizeof(struct hgcm_param32)*4)
#define PAGE_LIST_INFO_OFFSET64 (sizeof(struct hgcm_header) + 4*3 + sizeof(struct hgcm_param64)*4)

#define SIZEOF_HGCM_CALL32(n) (sizeof(struct hgcm_header) + 4*3 + sizeof(struct hgcm_param32)*(n))
#define SIZEOF_HGCM_CALL32_WITH_PAGE_LIST_INFO \
      (sizeof(struct hgcm_header) + 4*3 + sizeof(struct hgcm_param32)*4 + sizeof(struct page_list_info))
#define SIZEOF_HGCM_CALL64(n) (sizeof(struct hgcm_header) + 4*3 + sizeof(struct hgcm_param64)*(n))
#define SIZEOF_HGCM_CALL64_WITH_PAGE_LIST_INFO \
      (sizeof(struct hgcm_header) + 4*3 + sizeof(struct hgcm_param64)*4 + sizeof(struct page_list_info))

struct hgcm_cancel {
    struct hgcm_header header ;
} ;

#endif // __VBOX_DEFINES_H__
