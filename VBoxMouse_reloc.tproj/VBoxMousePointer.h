#define	DRIVER_PRIVATE
#import "EventSrcPCPointer.h"
#undef DRIVER_PRIVATE

#import "VBoxDefines.h"

@interface EventSrcPCPointer(VBoxMousePointer)
- processVBoxMouseInput:(struct vbox_mouse_absolute_ex *)input;
@end
