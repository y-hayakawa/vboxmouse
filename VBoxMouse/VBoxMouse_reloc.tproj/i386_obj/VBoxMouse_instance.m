#import <driverkit/IODevice.h>
#import <kernserv/kern_server_types.h>

kern_server_t VBoxMouse_instance;

@interface VBoxMouseKernelServerInstance : Object
{}
+ (kern_server_t *)kernelServerInstance;
@end

@implementation VBoxMouseKernelServerInstance
+ (kern_server_t *)kernelServerInstance
{
	return &VBoxMouse_instance;
}
@end

@interface VBoxMouseVersion : IODevice
{}
+ (int)driverKitVersionForVBoxMouse;
@end

@implementation VBoxMouseVersion
+ (int)driverKitVersionForVBoxMouse
{
	return IO_DRIVERKIT_VERSION;
}
@end

