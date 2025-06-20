/*
  VBoxMouse: VirtualBox Mouse Driver for NEXTSTEP 3.3(Intel)
  (c) 2025, Yoshinori Hayakawa

  Version 0.9 (2025-06-20)
*/

#include <stdio.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/eventProtocols.h>
#import <kernserv/i386/spl.h>
#import <mach/vm_param.h>

#import "VBoxDefines.h"
#import "VBoxMouse.h"
#import "VBoxMousePointer.h"

IOPCIConfigSpace pciConfig;				// PCI Configuration

@implementation VBoxMouse

- (BOOL)mouseInit: deviceDescription {
  IOReturn ret ;
  unsigned long *basePtr = 0 ;
  IOReturn configReturn;			       // Return value from getPCIConfigSpace

  IOLog("VBoxMouse - VirtualBox Mouse Adapter Driver\n");
  IOLog("VBoxMouse - Version 0.91 (built on %s at %s)\n", __DATE__, __TIME__);

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
  IOLog("IRQ:%ld\n",irqlevel) ;
  ret = [deviceDescription setInterruptList:&irqlevel num:1];
  if(ret)
  {
      IOLog("Can\'t set interruptList to IRQ %d (%s)\n", irqlevel,[IODirectDevice stringFromReturn:ret]) ;
      return NO;
  }

  basePtr = pciConfig.BaseAddress ;

#ifdef DEBUG
  IOLog("BAR0:%lx BAR1:%lx BAR2:%lx BAR3:%lx BAR4:%lx BAR5:%lx\n",
  basePtr[0],basePtr[1],basePtr[2],basePtr[3],basePtr[4],basePtr[5]) ;
#endif

  vbox_port = basePtr[0] & 0xFFFFFFFC ;
  IOLog("vbox_port:%lx\n",(unsigned long) vbox_port) ;

  // Page size is 8192, not 4096
  ret = IOMapPhysicalIntoIOTask( basePtr[1] & 0xFFFFFFF0, PAGE_SIZE,  &vbox_vmmdev) ;
  if (ret) {
      IOLog("Can\'t set memory mapping (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
      IOLog("Can\'t obtain physical address for vbox_guest_info (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
      IOLog("Can\'t obtain physical address for vbox_guest_caps (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
    IOLog("Can\'t obtain physical address for vbox_ack_events (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
    IOLog("Can\'t obtain physical address for vbox_mouse_absolute_ex (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
    IOLog("Can\'t obtain physical address for vbox_display_change2 (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
  [self registerDevice];
  ///

  //
  // VMMDevReq_ReportGuestStatus (59)
  //
  vbox_guest_status = IOMalloc(sizeof(struct vbox_guest_status)) ;
  ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t) vbox_guest_status, &vbox_guest_status_phys) ;
  if (ret) {
    IOLog("Can\'t obtain physical address for vbox_guest_status (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
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
    IOLog("Can\'t obtain physical address for vbox_filter_mask (%s)\n", [IODirectDevice stringFromReturn:ret]) ;
    return NO;
  }
  vbox_filter_mask->header.size = sizeof(struct vbox_filter_mask) ;
  vbox_filter_mask->header.version = VBOX_REQUEST_HEADER_VERSION;
  vbox_filter_mask->header.requestType = VBOX_CTL_GUEST_FILETER_MASK;
  vbox_filter_mask->header.rc = -1 ;
  vbox_filter_mask->ormask = (1<<0) | (1<<2) | (1<<9)  ;  // 0: mouse capability 2:display change 9: mouse position
  vbox_filter_mask->notmask = 0 ;
  outl(vbox_port, vbox_filter_mask_phys) ;
#ifdef DEBUG
  IOLog("rc=%ld CTL_GUEST_FILTER_MASK\n",vbox_filter_mask->header.rc) ;
#endif

  // enabling all interrupts
  vbox_vmmdev[3] = 0xFFFFFFFF ;
  [self enableAllInterrupts] ;

  if ([self startIOThread] != IO_R_SUCCESS) {
    IOLog("thread error\n") ;
    return NO ;
  }

  [self readConfigTable:[deviceDescription configTable]];

  IOLog ("VBoxMouse - Initialization successfully done\n");

  return YES;
}

- free {
	IOLog("VBoxMouse - Cleaning up\n");

	IOFree(vbox_mouse, sizeof(struct vbox_mouse_absolute_ex));
	IOFree(guest_info, sizeof(struct vbox_guest_info));
	IOFree(vbox_ack, sizeof(struct vbox_ack_events));
	IOFree(vbox_guest_caps, sizeof(struct vbox_guest_caps));
	IOFree(vbox_guest_status, sizeof(struct vbox_guest_status)) ;
	IOFree(vbox_filter_mask, sizeof(struct vbox_filter_mask));
	IOFree(vbox_display_change2, sizeof(struct vbox_display_change2));

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

  // Todo: I wanted to receive an event only when the screen size changes, but not working...
  if (events & (1<<2)) { // VMMDEV_EVENT_DISPLAY_CHANGE_REQUEST
    vbox_display_change2->header.size = sizeof(struct vbox_display_change2) ;
    vbox_display_change2->header.version = VBOX_REQUEST_HEADER_VERSION;
    vbox_display_change2->header.requestType = VBOX_REQUEST_GET_DISPLAY_CHANGE2 ;
    vbox_display_change2->header.rc = -1 ;
    vbox_display_change2->event_ack = (1<<2) ;

    outl(vbox_port, vbox_display_change2_phys);

    if (vbox_display_change2->xres != 0 && vbox_display_change2->yres != 0) {
      desktopBounds.width = vbox_display_change2->xres ;
      desktopBounds.height = vbox_display_change2->yres ;
      IOLog("display size has changed: %ld %ld\n", vbox_display_change2->xres,vbox_display_change2->yres) ;
    }
  } else {
#if 1
    // obtaining current display size via Bochs VBE Extensions
    // Since this is very inefficient, you can directly write your screen size in Instance0.table
    // and skip this part, if you need smoother cursor movement.
    unsigned short width,height ;
    outw(0x01CE,0x01) ; // XRES
    width = inw(0x01CF) ;
    outw(0x01CE,0x02) ; // YRES
    height = inw(0x01CF) ;

    desktopBounds.width = width ;
    desktopBounds.height = height ;
#endif
     ;
  }

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
    vbox_mouse->x = (vbox_mouse->x * desktopBounds.width / 65535) + desktopBounds.x ;
    vbox_mouse->y = (vbox_mouse->y * desktopBounds.height / 65535) + desktopBounds.y ;
    [target processVBoxMouseInput: vbox_mouse] ; // target is defined in PCPointer.h
  }

  [self enableAllInterrupts] ;
  return ;
}


- (BOOL)readConfigTable:configTable
{
    BOOL	success=YES;
    char	*value=NULL;
    
    if (!configTable)
	return NO;
    
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

    IOLog("config: w=%ld h=%d xofs=%d yofs=%d\n",desktopBounds.width,desktopBounds.height,desktopBounds.x,desktopBounds.y) ;
    
    return success;
}

@end



