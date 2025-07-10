/*
  VBoxMouse: VirtualBox Mouse Driver for NEXTSTEP 3.3(Intel)
  (c) 2025, Yoshinori Hayakawa

  Version 0.92 (2025-07-08)
*/

#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/eventProtocols.h>
#import <kernserv/i386/spl.h>
#import <kernserv/prototypes.h>
#import <mach/vm_param.h>

#import <sys/conf.h>

#import "VBoxDefines.h"
#import "VBoxMouse.h"
#import "VBoxMousePointer.h"

static void pb_thread(struct pb_data *data) ;
static void timer_callback(struct rect *rect) ;

IOPCIConfigSpace pciConfig;				// PCI Configuration
struct pb_data pbData;
static int buffer_length_allocated = 0 ; 

extern int pb_open() ;
extern int pb_read() ;
extern int pb_write() ;
extern int nulldev() ;
extern int nodev() ;

#undef DEBUG

@implementation VBoxMouse

- (BOOL)mouseInit: deviceDescription {
    IOReturn ret ;
    unsigned long *basePtr = 0 ;
    IOReturn configReturn;			       // Return value from getPCIConfigSpace

    IOLog("VBoxMouse - VirtualBox Mouse Adapter Driver\n");
    IOLog("VBoxMouse - Version 0.92 (built on %s at %s)\n", __DATE__, __TIME__);

    ret = [VBoxMouse addToCdevswFromDescription: deviceDescription
                     open: (IOSwitchFunc) pb_open
                     close: (IOSwitchFunc) nulldev
                     read: (IOSwitchFunc) pb_read
                     write: (IOSwitchFunc) pb_write
                     ioctl: (IOSwitchFunc) nodev
                     stop: (IOSwitchFunc) nodev
                     reset: (IOSwitchFunc) nulldev
                     select: (IOSwitchFunc) nulldev
                     mmap: (IOSwitchFunc) nodev
                     getc: (IOSwitchFunc) nodev
                     putc: (IOSwitchFunc) nodev ] ;
    if (ret != YES) {
        IOLog("VBoxMouse - Failed to add CDEVSW\n");
    } else {
        IOLog("VBoxMouse - Character major number = %ld\n",[VBoxMouse characterMajor]) ;
    }

    // Get the PCI configuration
    configReturn = [VBoxMouse getPCIConfigSpace: &pciConfig withDeviceDescription: deviceDescription];
    if (configReturn != IO_R_SUCCESS ) {
        IOLog("VBoxMouse - Failed to get PCI config data - Error: '%s'\n", [self stringFromReturn:configReturn]);
        return NO;
    }

    // Check if the vendor is correct
    if (pciConfig.VendorID != VBOX_VENDOR_ID) {
        IOLog("VBoxMouse - Invalid vendor '%04x'!\n", pciConfig.VendorID);
        return NO;
    }

    // Check if the device is correct
    if (pciConfig.DeviceID != VBOX_DEVICE_ID) {
        IOLog("VBoxMouse - Invalid device '%04x'!\n", pciConfig.DeviceID);
        return NO;
    }
    IOLog ("VBoxMouse - PCI Vendor: '%04x' Device: '%04x'\n", pciConfig.DeviceID, pciConfig.VendorID);

    IOLog ("VBoxMouse - Initializing...\n");

    irqlevel = (unsigned int) pciConfig.InterruptLine;
    IOLog("VBoxMouse - IRQ=%ld\n",irqlevel) ;
    ret = [deviceDescription setInterruptList:&irqlevel num:1];
    if(ret)
        {
            IOLog("VBoxMouse - Can\'t set interruptList to IRQ %d (%s)\n", irqlevel,[IODirectDevice stringFromReturn:ret]) ;
            return NO;
        }

    basePtr = pciConfig.BaseAddress ;

#ifdef DEBUG
    IOLog("BAR0:%lx BAR1:%lx BAR2:%lx BAR3:%lx BAR4:%lx BAR5:%lx\n",
          basePtr[0],basePtr[1],basePtr[2],basePtr[3],basePtr[4],basePtr[5]) ;
#endif

    vbox_port = basePtr[0] & 0xFFFFFFFC ;
    IOLog("VBoxMouse - vbox_port=0x%lx\n",(unsigned long) vbox_port) ;

    // Page size is 8192, not 4096
    ret = IOMapPhysicalIntoIOTask( basePtr[1] & 0xFFFFFFF0, PAGE_SIZE,  &vbox_vmmdev) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t set memory mapping (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
#ifdef DEBUG
    IOLog("%d vbox_vmmdev:%lx  siz:%ld\n",ret,(unsigned long) vbox_vmmdev,PAGE_SIZE) ;
    IOLog("VMMDEV=%lx %lx %lx %lx\n",vbox_vmmdev[0],vbox_vmmdev[1],vbox_vmmdev[2],vbox_vmmdev[3]) ;
#endif

    // ---- Now to prepare VMMDev packets ----

    //
    // VMMDevReq_ReportGuestInfo (50)
    //
    guest_info = IOMalloc(sizeof(struct vbox_guest_info)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) guest_info, &guest_info_phys) ;
    if (ret) {
        IOLog("VBoxMouse - can\'t obtain physical address for vbox_guest_info (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
#ifdef DEBUG
    IOLog("%d guest_info_phys:%lx\n", ret, (unsigned long) guest_info_phys) ;
#endif
    guest_info->header.size = sizeof(struct vbox_guest_info) ;
    guest_info->header.version = VBOX_REQUEST_HEADER_VERSION;
    guest_info->header.requestType = VBOX_REQUEST_GUEST_INFO ;
    guest_info->header.rc = -1 ;
    guest_info->header.reserved1 = 0;
    guest_info->header.reserved2 = 0;
    guest_info->version = VBOX_VMMDEV_VERSION ;
    guest_info->ostype = 0 ;

    outl(vbox_port, guest_info_phys);

#ifdef DEBUG
    IOLog("rc=%ld REQUEST_GUEST_INFO\n",guest_info->header.rc) ;
    IOLog("ostype=%ld\n",guest_info->ostype) ;
#endif

    //
    // VMMDevReq_ReportGuestCapability (55) 
    //
    vbox_guest_caps = IOMalloc(sizeof(struct vbox_guest_caps)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_guest_caps, &vbox_guest_caps_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for vbox_guest_caps (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
#ifdef DEBUG
    IOLog("%d vbox_guest_caps_phys:%lx\n", ret, (unsigned long) vbox_guest_caps_phys) ;
#endif
    vbox_guest_caps->header.size = sizeof(struct vbox_guest_caps) ;
    vbox_guest_caps->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_guest_caps->header.requestType = VBOX_REQUEST_SET_GUEST_CAPS ;
    vbox_guest_caps->header.rc = -1 ;
    vbox_guest_caps->header.reserved1 = 0;
    vbox_guest_caps->header.reserved2 = 0;
    vbox_guest_caps->caps = (1<<2) ; // GUEST_SUPPORTS_GRAPHICS
    outl(vbox_port, vbox_guest_caps_phys);
#ifdef DEBUG
    IOLog("rc=%ld REQUEST_SET_GUEST_CAPS\n",vbox_guest_caps->header.rc) ;
#endif

    //
    // VMMDevReq_AcknowlegeEvents (41)
    //
    vbox_ack = IOMalloc(sizeof(struct vbox_ack_events)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_ack, &vbox_ack_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for vbox_ack_events (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
#ifdef DEBUG
    IOLog("%d vbox_ack_phys:%lx\n", ret, (unsigned long) vbox_ack_phys) ;
#endif
    vbox_ack->header.size = sizeof(struct vbox_ack_events) ;
    vbox_ack->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_ack->header.requestType = VBOX_REQUEST_ACK_EVENTS;
    vbox_ack->header.rc = -1 ;
    vbox_ack->header.reserved1 = 0;
    vbox_ack->header.reserved2 = 0;
    vbox_ack->events = 0 ;

    //
    // VMMDevReq_GetMouseStatus (1), VMMDevReq_SetMouseStatus (2)
    //
    vbox_mouse = IOMalloc(sizeof(struct vbox_mouse_absolute_ex)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_mouse, &vbox_mouse_phys) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for vbox_mouse_absolute_ex (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
#ifdef DEBUG
    IOLog("vbox_mouse_phys:%lx\n",(unsigned long) vbox_mouse_phys) ;
#endif
    vbox_mouse->header.size = sizeof(struct vbox_mouse_absolute) ;
    vbox_mouse->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_mouse->header.requestType = VBOX_REQUEST_SET_MOUSE;
    vbox_mouse->header.rc = -1 ;
    vbox_mouse->header.reserved1 = 0 ;
    vbox_mouse->header.reserved2 = 0 ;
    vbox_mouse->x = 0 ;
    vbox_mouse->y = 0 ;
    vbox_mouse->features = (1<<0) | (1<<4) | (1<<7) ;
  
    outl(vbox_port, vbox_mouse_phys);
#ifdef DEBUG
    IOLog("rc=%ld REQUEST_SET_MOUSE\n",guest_info->header.rc) ;
    IOLog("features:%lx\n",vbox_mouse->features) ;
#endif

#ifdef DEBUG
    vbox_mouse->header.rc = -1 ;
    vbox_mouse->header.size = sizeof(struct vbox_mouse_absolute_ex) ;
    vbox_mouse->header.requestType = VBOX_REQUEST_GET_MOUSE_EX;  
    outl(vbox_port, vbox_mouse_phys);
    IOLog("rc=%ld  REQUEST_GET_MOUSE_EX\n",guest_info->header.rc) ;
    IOLog("features:%lx\n",vbox_mouse->features) ;
#endif

    //
    // VMMDevReq_GetDisplayChangeRequest2 (54)
    //
    vbox_display_change2 = IOMalloc(sizeof(struct vbox_display_change2)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_display_change2, &vbox_display_change2_phys) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for vbox_display_change2 (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
#ifdef DEBUG
    IOLog("vbox_display_change2_phys:%lx\n",(unsigned long) vbox_display_change2_phys) ;
#endif
    vbox_display_change2->header.size = sizeof(struct  vbox_display_change2) ;
    vbox_display_change2->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_display_change2->header.requestType = VBOX_REQUEST_GET_DISPLAY_CHANGE2 ;
    vbox_display_change2->header.rc = -1 ;
    vbox_display_change2->event_ack = 0 ;

    ///
    [self setName:VBMOUSE_DEV_NAME] ;
    [self setDeviceKind:"VBoxMouse"] ;
    [self registerDevice];
    ///

    //
    // VMMDevReq_ReportGuestStatus (59)
    //
    vbox_guest_status = IOMalloc(sizeof(struct vbox_guest_status)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_guest_status, &vbox_guest_status_phys) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for vbox_guest_status (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
    vbox_guest_status->header.size = sizeof(struct vbox_guest_status) ;
    vbox_guest_status->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_guest_status->header.requestType = VBOX_REQUEST_REP_GUEST_STATUS;
    vbox_guest_status->header.rc = -1 ;
    vbox_guest_status->guest_status.facility = 20 ;
    vbox_guest_status->guest_status.status = 50 ;
    vbox_guest_status->guest_status.flags = 0 ;
    outl(vbox_port, vbox_guest_status_phys) ;
#ifdef DEBUG
    IOLog("rc=%ld REP_GUEST_STATUS\n",vbox_guest_status->header.rc) ;
#endif

    //
    // VMMDevReq_CtlGuestFilterMask (42)
    //
    vbox_filter_mask = IOMalloc(sizeof(struct vbox_filter_mask)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_filter_mask, &vbox_filter_mask_phys) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for vbox_filter_mask (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
    vbox_filter_mask->header.size = sizeof(struct vbox_filter_mask) ;
    vbox_filter_mask->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_filter_mask->header.requestType = VBOX_CTL_GUEST_FILETER_MASK;
    vbox_filter_mask->header.rc = -1 ;
    // 0:mouse capability 1:HGCM event  2:display change 9: mouse position
    vbox_filter_mask->ormask = (1<<0) | (1<<1) | (1<<2) | (1<<9)  ;  
    vbox_filter_mask->notmask = 0 ;
    outl(vbox_port, vbox_filter_mask_phys) ;
#ifdef DEBUG
    IOLog("rc=%ld CTL_GUEST_FILTER_MASK\n",vbox_filter_mask->header.rc) ;
#endif

    // enabling all interrupts
    vbox_vmmdev[3] = 0xFFFFFFFF ;
    [self enableAllInterrupts] ;
  
    desktopBounds.lock = [NXLock new] ;

    [self readConfigTable:[deviceDescription configTable]];

    if ([self startIOThread] != IO_R_SUCCESS) {
        IOLog("VBoxMouse - Cannot start IOThread...\n") ;
        return NO ;
    }

    IOScheduleFunc((IOThreadFunc) timer_callback, &desktopBounds, 1) ;

    pbData.lock = [NXLock new] ;

    ret = [self initHGCM] ;
    if (ret != YES) {
        IOLog ("VBoxMouse - HGCM Initialization error\n");
    } else {
        ret = [self connectHGCM] ;
    }

    IOLog ("VBoxMouse - Initialization successfully done\n");

    return YES;
}

- free {
	IOLog("VBoxMouse - Cleaning up\n");

	[pbData.lock unlock] ;
	pbData.terminate = YES ;

	[desktopBounds.lock unlock] ;

	IOUnscheduleFunc((IOThreadFunc)timer_callback, &desktopBounds) ;

	[desktopBounds.lock free] ;

	IOFree(vbox_mouse, sizeof(struct vbox_mouse_absolute_ex));
	IOFree(guest_info, sizeof(struct vbox_guest_info));
	IOFree(vbox_ack, sizeof(struct vbox_ack_events));
	IOFree(vbox_guest_caps, sizeof(struct vbox_guest_caps));
	IOFree(vbox_guest_status, sizeof(struct vbox_guest_status)) ;
	IOFree(vbox_filter_mask, sizeof(struct vbox_filter_mask));
	IOFree(vbox_display_change2, sizeof(struct vbox_display_change2));

	[self freeHGCM] ;

	return [super free];
}

- (void)interruptOccurred
{
    unsigned long events = 0 ;

    if (vbox_vmmdev[2]==0) {
        [self enableAllInterrupts] ;
        return ;
    }

    if (vbox_vmmdev[1]==1) { // VERSION 1.04
        events = inl(vbox_port+8) ;  // 8:VMMDEV_PORT_OFF_REQUEST_FAST
    } else {
        events = vbox_vmmdev[2] ;
        vbox_ack->header.rc = -1 ;
        vbox_ack->events = events ;
        outl(vbox_port, vbox_ack_phys) ;
    }

    if (events & (1<<2)) { // VMMDEV_EVENT_DISPLAY_CHANGE_REQUEST
        vbox_display_change2->header.size = sizeof(struct vbox_display_change2) ;
        vbox_display_change2->header.version = VBOX_REQUEST_HEADER_VERSION;
        vbox_display_change2->header.requestType = VBOX_REQUEST_GET_DISPLAY_CHANGE2 ;
        vbox_display_change2->header.rc = -1 ;
        vbox_display_change2->event_ack = (1<<2) ;

        outl(vbox_port, vbox_display_change2_phys);

        if (vbox_display_change2->xres != 0 && vbox_display_change2->yres != 0) {
#if 0            
            [desktopBounds.lock lock] ;
            desktopBounds.width = vbox_display_change2->xres ;
            desktopBounds.height = vbox_display_change2->yres ;
            [desktopBounds.lock unlock] ;
#endif
            IOLog("VBoxMouse - display size has changed: %ld %ld\n", vbox_display_change2->xres,vbox_display_change2->yres) ;
        }
    } else if (events & (1<<1)) { // HGCM event
        if (hgcm_connect->header.flags==1) { // connected to HGCM
            hgcm_connect->header.flags=0 ;
            pbData.client_id = hgcm_connect->client_id ;
            IOLog("VBoxMouse - HGCM client_id= %ld\n",pbData.client_id) ;
            pbData.count = 0 ;
            IOForkThread((IOThreadFunc)pb_thread, &pbData) ;
        } 
    } else { // mouse pointer changed
        vbox_mouse->header.size = sizeof(struct vbox_mouse_absolute_ex) ;
        vbox_mouse->header.version = VBOX_REQUEST_HEADER_VERSION;
        vbox_mouse->header.requestType = VBOX_REQUEST_GET_MOUSE_EX;
        vbox_mouse->header.rc = -1 ;
        vbox_mouse->header.reserved1 = 0 ;
        vbox_mouse->header.reserved2 = 0 ;
        vbox_mouse->x = 0 ;
        vbox_mouse->y = 0 ;
        vbox_mouse->features = 0 ;

        outl(vbox_port, vbox_mouse_phys);

        if (target != nil) {
            [desktopBounds.lock lock] ;
            vbox_mouse->x = (vbox_mouse->x * desktopBounds.width / 65535) + desktopBounds.x ;
            vbox_mouse->y = (vbox_mouse->y * desktopBounds.height / 65535) + desktopBounds.y ;
            [desktopBounds.lock unlock] ;
            [target processVBoxMouseInput: vbox_mouse] ; // target is defined in PCPointer.h
        }
    }

    [self enableAllInterrupts] ;
    return ;
}

- (BOOL) initHGCM
{
    int ret ;

    // need to use low memory to get a continuous range
    pbData.pb_read_buffer = (char *) IOMallocLow(MAX_BUFFER_LEN) ;
    if (pbData.pb_read_buffer == NULL) {
        IOLog("VBoxMouse - Can\'t allocate read buffer\n") ;
        return NO ;
    }
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) pbData.pb_read_buffer, &pbData.pb_read_buffer_phys);
    IOLog("VBoxMouse - PB_READ_BUFFER addr=0x%lx phys=0x%lx\n", pbData.pb_read_buffer, pbData.pb_read_buffer_phys) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for pb_read_buffer (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
    pbData.pb_read_buffer_len = 0 ;

    pbData.pb_write_buffer = (char *) IOMallocLow(MAX_BUFFER_LEN) ;
    if (pbData.pb_write_buffer == NULL) {
        IOLog("VBoxMouse - Can\'t allocate write buffer\n") ;
        return NO ;
    }
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) pbData.pb_write_buffer, &pbData.pb_write_buffer_phys);
    IOLog("VBoxMouse - PB_WRITE_BUFFER addr=0x%lx phys=0x%lx\n", pbData.pb_write_buffer, pbData.pb_write_buffer_phys) ;
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for pb_write_buffer (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }
    pbData.pb_write_buffer_len = 0 ;

    // now both buffers are ready to use
    buffer_length_allocated = MAX_BUFFER_LEN ;

    hgcm_connect = IOMalloc(sizeof(struct hgcm_connect)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) hgcm_connect, &hgcm_connect_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for hgcm_connect (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }

    hgcm_disconnect = IOMalloc(sizeof(struct hgcm_disconnect)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) hgcm_disconnect, &hgcm_disconnect_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for hgcm_disconnect (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }

    hgcm_call = IOMalloc(sizeof(struct hgcm_call)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) hgcm_call, &hgcm_call_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for hgcm_call (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }

    hgcm_write_call = IOMalloc(sizeof(struct hgcm_call)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) hgcm_write_call, &hgcm_write_call_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for hgcm_write_call (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }

    hgcm_cancel = IOMalloc(sizeof(struct hgcm_cancel)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) hgcm_cancel, &hgcm_cancel_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for hgcm_cancel (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
        return NO;
    }

    pbData.client_id = -1 ;
    pbData.vbox_port = vbox_port ;

    return YES ;
}

- (BOOL) connectHGCM 
{
    hgcm_connect->header.header.size = sizeof(struct hgcm_connect) ;
    hgcm_connect->header.header.version = VBOX_REQUEST_HEADER_VERSION;
    hgcm_connect->header.header.requestType = VBOX_REQUEST_HGCM_CONNECT;
    hgcm_connect->header.header.rc = -1 ;
    hgcm_connect->header.flags = 0 ;
    hgcm_connect->header.result = 0 ;
    hgcm_connect->type = 2 ;  // use predefined library
    strcpy(hgcm_connect->host_name,"VBoxSharedClipboard") ;
    hgcm_connect->client_id = -1 ;

    outl(vbox_port, hgcm_connect_phys);

#ifdef DEBUG
    IOLog("rc=%ld flags=%lx clientid=%ld\n",hgcm_connect->header.header.rc, hgcm_connect->header.flags, hgcm_connect->client_id) ;
#endif

    if (hgcm_connect->header.header.rc < 0) return NO ;

    return YES ;
}

- (BOOL) disconnectHGCM 
{
    if (pbData.client_id <0) return NO ;

    hgcm_disconnect->header.header.size = sizeof(struct hgcm_disconnect) ;
    hgcm_disconnect->header.header.version = VBOX_REQUEST_HEADER_VERSION;
    hgcm_disconnect->header.header.requestType = VBOX_REQUEST_HGCM_DISCONNECT;
    hgcm_disconnect->header.header.rc = -1 ;
    hgcm_disconnect->header.flags = 0 ;
    hgcm_disconnect->header.result = 0 ;

    outl(vbox_port, hgcm_disconnect_phys);

    if (hgcm_disconnect->header.header.rc < 0) return NO ;

    pbData.client_id = -1 ;

    return YES ;
}

- (void) freeHGCM
{
    int ret ;
    if (pbData.client_id >=0 ) ret = [self disconnectHGCM] ;

    IOFreeLow(pbData.pb_read_buffer,MAX_BUFFER_LEN) ;
    IOFreeLow(pbData.pb_write_buffer,MAX_BUFFER_LEN) ;
    IOFree(hgcm_connect, sizeof(struct hgcm_connect)) ;
    IOFree(hgcm_disconnect, sizeof(struct hgcm_disconnect)) ;
    IOFree(hgcm_call, sizeof(hgcm_call)) ;
    IOFree(hgcm_cancel, sizeof(hgcm_cancel)) ;
}

- (BOOL) setPBFormat
{
    hgcm_call->header.header.size = SIZEOF_HGCM_CALL32(1) ;
    hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
    hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
    hgcm_call->header.header.rc = -1 ;
    hgcm_call->client_id = pbData.client_id ;
    hgcm_call->function_code = VBOX_SHCL_GUEST_FN_REPORT_FORMATS ;
    hgcm_call->cparams = 1 ;
    hgcm_call->params[0].type = 1 ;        // 32bit value
    hgcm_call->params[0].value0 = (1<<0) ; // UNICODETEXT
    hgcm_call->params[0].value1 = 0 ;

    outl(vbox_port, hgcm_call_phys);

    if ( hgcm_call->header.header.rc < 0 ) {
        return NO ;
    } else {  
        return YES ;
    }
}

- (BOOL)readConfigTable:configTable
{
    BOOL	success=YES;
    char	*value=NULL;
    
    if (!configTable)
        return NO;
    [desktopBounds.lock lock] ;
    if ((value = (char*)[configTable valueForStringKey:VBM_XOFFSET]) != NULL)
        {
            desktopBounds.x = PCPatoi(value);
            [configTable freeString:value];
        }
    else desktopBounds.x = VBM_DEF_XOFFSET;
    
    if ((value = (char*)[configTable valueForStringKey:VBM_YOFFSET]) != NULL)
        {
            desktopBounds.y = PCPatoi(value);
            [configTable freeString:value];
        }
    else desktopBounds.y = VBM_DEF_YOFFSET;
    
    if ((value = (char*)[configTable valueForStringKey:VBM_XSIZE]) != NULL)
        {
            desktopBounds.width= PCPatoi(value);
            [configTable freeString:value];
        }
    else desktopBounds.width = VBM_DEF_XSIZE;
	
    if ((value = (char*)[configTable valueForStringKey:VBM_YSIZE]) != NULL)
        {
            desktopBounds.height = PCPatoi(value);
            [configTable freeString:value];
        }
    else desktopBounds.height = VBM_DEF_YSIZE;
    [desktopBounds.lock unlock] ;

    IOLog("VBoxMouse - Config: w=%d h=%d xofs=%d yofs=%d\n",desktopBounds.width,desktopBounds.height,desktopBounds.x,desktopBounds.y) ;
    
    return success;
}


- (IOReturn)getIntValues:(unsigned int *)array forParameter:(IOParameterName)parameter
                   count:(unsigned int *)count
{
    if(strcmp(parameter, PARAMETER_NAME) != 0) {
        return [super getIntValues:array forParameter:parameter count:count];
    }

    [pbData.lock lock] ;
    array[0] = pbData.count ;
    array[1] = buffer_length_allocated ;
    *count = 2 ;
    [pbData.lock unlock] ;

    return 0 ;
}

@end

static void timer_callback(struct rect *rect) {
    unsigned short width,height ;
    outw(0x01CE,0x01) ; // XRES
    width = inw(0x01CF) ;
    outw(0x01CE,0x02) ; // YRES
    height = inw(0x01CF) ;
    [rect->lock lock] ;
    rect->width = width ;
    rect->height = height ;
    [rect->lock unlock] ;
    IOScheduleFunc((IOThreadFunc)timer_callback, (void *) rect, 1) ; // 1 sec
}


static void pb_thread(struct pb_data *data) {
    struct hgcm_call *hgcm_call ;
    unsigned int hgcm_call_phys ;
    unsigned int msg_id, msg_fmt ;
    int ret,len,cnt,nloop ;

    hgcm_call = IOMalloc(sizeof(struct hgcm_call)) ;
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) hgcm_call, &hgcm_call_phys);
    if (ret) {
        IOLog("VBoxMouse - Can\'t obtain physical address for hgcm_call (%s) in pb_thread\n", [IODirectDevice stringFromReturn:ret]) ;
        goto TERMINATE ;
    }

    msg_fmt=0 ;
    nloop=0 ;
    while(1) {
        nloop++ ;

        if (data->pb_got_new_data_to_write>0) {
            hgcm_call->header.header.size = SIZEOF_HGCM_CALL32(1) ;
            hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
            hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
            hgcm_call->header.header.rc = -1 ;
            hgcm_call->client_id = data->client_id ;
            hgcm_call->function_code = VBOX_SHCL_GUEST_FN_REPORT_FORMATS ;
            hgcm_call->cparams = 1 ;
            hgcm_call->params[0].type = 1 ;        // 32bit value
            hgcm_call->params[0].value0 = (1<<0) ; // UNICODETEXT
            hgcm_call->params[0].value1 = 0 ;
            outl(data->vbox_port, hgcm_call_phys);
            cnt=0 ;
            do {
                IOSleep(10) ; 
            } while(hgcm_call->header.flags == 0 && cnt++<10) ;
            if (hgcm_call->header.header.rc >=0) {
                [data->lock lock] ;
                data->pb_write_buffer_len = data->pb_got_new_data_to_write ;
                data->pb_got_new_data_to_write = 0 ;
                [data->lock unlock] ;
            }
        }

        hgcm_call->header.header.size = SIZEOF_HGCM_CALL32(2) ;
        hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
        hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
        hgcm_call->header.header.rc = -1 ;
        hgcm_call->header.flags = 0 ;
        hgcm_call->header.result = 0 ;
        hgcm_call->client_id = data->client_id ;
        hgcm_call->function_code = VBOX_SHCL_GUEST_FN_MSG_PEEK_NOWAIT ;
        hgcm_call->cparams = 2 ;
        hgcm_call->params[0].type = 1 ;   // 32bit value
        hgcm_call->params[0].value0 = 0 ; // msgId ; VBOX_SHCL_HOST_MSG_READ_DATA or VBOX_SHCL_HOST_MSG_FORMATS_REPORT ; 
        hgcm_call->params[0].value1 = 0 ;
        hgcm_call->params[1].type = 1 ;   
        hgcm_call->params[1].value0 = 0 ; // #params
        hgcm_call->params[1].value1 = 0 ;
        hgcm_call->params[2].type = 1 ;   
        hgcm_call->params[2].value0 = 0 ; // #params
        hgcm_call->params[2].value1 = 0 ;
        outl(data->vbox_port, hgcm_call_phys);
        cnt=0 ;
        do {
            IOSleep(200) ; // 200m sec
        } while(hgcm_call->header.flags == 0 && cnt++<5) ;

        if (hgcm_call->header.header.rc < 0) continue ;

#if 0
        if (hgcm_call->params[1].value0 == 1 && hgcm_call->params[2].value0 != 0xFFFFFFFB) {  // parameter size(4 bytes) is represented as ~4U
            IOLog("pb_thread: unexpected values rc=%ld p1=%ld p2=%lx\n",
                  hgcm_call->header.header.rc, hgcm_call->params[1].value0,hgcm_call->params[2].value0) ;
            continue ;
        }
#endif

        msg_id = hgcm_call->params[0].value0 ;
        if (msg_id == 0) continue ;

#ifdef DEBUG
        IOLog("pb_thread(PEEK): rc:%ld,flags:%ld result:%ld  p0:%ld p1:%ld p2:%lx\n",
              hgcm_call->header.header.rc, hgcm_call->header.flags, hgcm_call->header.result,
              hgcm_call->params[0].value0,hgcm_call->params[1].value0, hgcm_call->params[2].value0) ;
#endif

        if (msg_id == VBOX_SHCL_HOST_MSG_FORMATS_REPORT) {

            hgcm_call->header.header.size = SIZEOF_HGCM_CALL32(2) ;
            hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
            hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
            hgcm_call->header.header.rc = -1 ;
            hgcm_call->header.flags = 0 ;
            hgcm_call->client_id = data->client_id ;
            hgcm_call->function_code = VBOX_SHCL_GUEST_FN_MSG_GET ;
            hgcm_call->cparams = 2 ;
            hgcm_call->params[0].type = 1 ;        // 32bit value
            hgcm_call->params[0].value0 = VBOX_SHCL_HOST_MSG_FORMATS_REPORT ; 
            hgcm_call->params[0].value1 = 0 ;
            hgcm_call->params[1].type = 1 ;        // 32bit value
            hgcm_call->params[1].value0 = 0 ;      
            hgcm_call->params[1].value1 = 0 ;
            outl(data->vbox_port, hgcm_call_phys);
            cnt=0 ;
            do {
                IOSleep(10) ; // 10m sec
            } while(hgcm_call->header.flags == 0 && cnt++<100) ;
#ifdef DEBUG
            IOLog("pb_thread(FN_MSG_GET 3): rc=%ld flag=%ld result=%ld p0=%ld p1=%ld cnt=%ld\n",
                  hgcm_call->header.header.rc, hgcm_call->header.flags, hgcm_call->header.result, 
                  hgcm_call->params[0].value0,hgcm_call->params[1].value0,cnt) ;
#endif
            if (hgcm_call->header.header.rc < 0) continue ;

            msg_fmt = hgcm_call->params[1].value0 & (1<<0) ; // (1<<0): UNICODETEXT
            if (msg_fmt != (1<<0)) continue ;
#ifdef DEBUG
            IOLog("pb_thread: got msg_fmt=%lx\n",msg_fmt) ;
#endif
            hgcm_call->header.header.size = SIZEOF_HGCM_CALL32_WITH_PAGE_LIST_INFO ;
            hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
            hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
            hgcm_call->header.header.rc = -1 ;
            hgcm_call->header.flags = 0 ;
            hgcm_call->client_id = data->client_id ;
            hgcm_call->function_code = VBOX_SHCL_GUEST_FN_DATA_READ ;
            hgcm_call->cparams = 3 ;
            hgcm_call->params[0].type = 1 ;        // 32bit value
            hgcm_call->params[0].value0 = msg_fmt ; // UNICODETEXT   
            hgcm_call->params[0].value1 = 0 ;
            hgcm_call->params[1].type = 10 ;        // 3:phys addrr(deprecated), 10:page list
            hgcm_call->params[1].value0 = MAX_BUFFER_LEN ;   
            hgcm_call->params[1].value1 = PAGE_LIST_INFO_OFFSET32 ;
            hgcm_call->params[2].type = 1 ;        // 32bit value
            hgcm_call->params[2].value0 = 0 ;      // length will be returened
            hgcm_call->params[2].value1 = 0 ;
            hgcm_call->page_list_info.flags = 3 ;
            hgcm_call->page_list_info.offset = 0 ;
            hgcm_call->page_list_info.cpages = 1 ;
            hgcm_call->page_list_info.pages[0] = data->pb_read_buffer_phys ;
            outl(data->vbox_port, hgcm_call_phys);
            cnt=0 ;
            do {
                IOSleep(20) ; // 20m sec
            } while(hgcm_call->header.flags == 0 && ++cnt<50) ;
#ifdef DEBUG
            IOLog("pb_thread(FN_DATA_READ): rc=%ld res=%ld p0=%ld p1=%ld p2=%ld cnt=%d\n",
                  hgcm_call->header.header.rc, hgcm_call->header.result, 
                  hgcm_call->params[0].value0, hgcm_call->params[1].value0, hgcm_call->params[2].value0,cnt) ;
#endif
            if (hgcm_call->header.header.rc < 0) continue ;

            if (hgcm_call->params[0].value0 != (1<<0)) continue ; // skip data other than UNICODETEXT

            len = hgcm_call->params[2].value0 ;  // actual data length
            if (len == 0 || len>MAX_BUFFER_LEN) {
                data->pb_read_buffer_len = 0 ; 
                continue ;  // skip very large data
            }

            [data->lock lock] ;
#ifdef DEBUG
            IOLog("pb_thread: got PB data (%d bytes)\n",len) ;
#endif
            data->pb_read_buffer_len = len ;
            data->count += 1 ;
            [data->lock unlock] ;

        } else if (msg_id == VBOX_SHCL_HOST_MSG_READ_DATA) { // HOST WANTS DATA

            hgcm_call->header.header.size = SIZEOF_HGCM_CALL32(2) ;
            hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
            hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
            hgcm_call->header.header.rc = -1 ;
            hgcm_call->header.flags = 0 ;
            hgcm_call->client_id = data->client_id ;
            hgcm_call->function_code = VBOX_SHCL_GUEST_FN_MSG_GET ;
            hgcm_call->cparams = 2 ;
            hgcm_call->params[0].type = 1 ;        // 32bit value
            hgcm_call->params[0].value0 = VBOX_SHCL_HOST_MSG_READ_DATA ;
            hgcm_call->params[0].value1 = 0 ;
            hgcm_call->params[1].type = 1 ;        // 32bit value
            hgcm_call->params[1].value0 = 0 ; 
            hgcm_call->params[1].value1 = 0 ;
            outl(data->vbox_port, hgcm_call_phys);
            cnt=0 ;
            do {
                IOSleep(10) ; // 10m sec
            } while(hgcm_call->header.flags == 0 && cnt++<100) ;
#ifdef DEBUG
            IOLog("pb_thread(FN_MSG_GET 2): rc=%ld p0=%ld p1=%ld\n",
                  hgcm_call->header.header.rc, hgcm_call->params[0].value0, hgcm_call->params[1].value0) ;
#endif
            if (hgcm_call->header.header.rc < 0) continue ;

            msg_fmt = hgcm_call->params[1].value0 ;

            if (data->pb_write_buffer_len > 0 && (msg_fmt & (1<<0))) {
                hgcm_call->header.header.size = SIZEOF_HGCM_CALL32_WITH_PAGE_LIST_INFO ;
                hgcm_call->header.header.version = VBOX_REQUEST_HEADER_VERSION;
                hgcm_call->header.header.requestType = VBOX_REQUEST_HGCM_CALL32 ;
                hgcm_call->header.header.rc = -1 ;
                hgcm_call->header.flags = 0 ;
                hgcm_call->client_id = data->client_id ;
                hgcm_call->function_code = VBOX_SHCL_GUEST_FN_DATA_WRITE ;
                hgcm_call->cparams = 2 ;
                hgcm_call->params[0].type = 1 ;        // 32bit value
                hgcm_call->params[0].value0 = (1<<0) ; // UNICODE TEXT
                hgcm_call->params[0].value1 = 0 ;
                hgcm_call->params[1].type = 10 ;        // 3:phys addr(deprecated), 10:page list
                hgcm_call->params[1].value0 = data->pb_write_buffer_len ;
                hgcm_call->params[1].value1 = PAGE_LIST_INFO_OFFSET32 ;
                hgcm_call->page_list_info.flags = 3 ;
                hgcm_call->page_list_info.offset = 0 ;
                hgcm_call->page_list_info.cpages = 1 ;
                hgcm_call->page_list_info.pages[0] = data->pb_write_buffer_phys ;
                [data->lock lock] ;
                outl(data->vbox_port, hgcm_call_phys);
                cnt=0 ;
                do {
                    IOSleep(10) ; // 10m sec
                } while(hgcm_call->header.flags == 0 && cnt++<100) ;
                [data->lock unlock] ;
#ifdef DEBUG
                IOLog("pb_thread(FN_DATA_WRITE): rc=%ld p0=%ld p1=%ld cnt=%ld\n",
                      hgcm_call->header.header.rc, hgcm_call->params[0].value0, hgcm_call->params[1].value0,cnt) ;
#endif
                data->pb_write_buffer_len = 0 ; // sent
            } 
            ; 
        } else if (msg_id == VBOX_SHCL_HOST_MSG_QUIT ) {
            // IOLog("VBoxMouse - pb_thread(FN_MSG_QUIT)\n") ;
            goto TERMINATE ;
        } 

        if (data->terminate) goto TERMINATE ;
    }

 TERMINATE:
    IOLog("VBoxMouse - pb_thread terminating..\n") ;
    IOFree(hgcm_call,sizeof(struct hgcm_call)) ;
    IOExitThread() ;
}

