/*
  Add a method to handle input coming from VBoxMouse and dispatch it to the EventDriver 
  
  Most of this code is taken from VMMouse by Jens Heise (2006) for VMWare.
*/


#import <driverkit/generalFuncs.h>
#import <driverkit/eventProtocols.h>
#import <bsd/dev/evsio.h>
#import <bsd/dev/ev_types.h>

#import "VBoxMousePointer.h"

@implementation EventSrcPCPointer(VBoxMousePointer)

- processVBoxMouseInput:(struct vbox_mouse_absolute_ex *)input
{
    int		buttons;
    Point	position;
    
    [deviceLock lock];
    
    buttons = 0;
    if (input->buttons & VMMDEV_MOUSE_BUTTON_LEFT)
	buttons |= EV_LB;
    if (input->buttons & VMMDEV_MOUSE_BUTTON_RIGHT)
	buttons |= EV_RB;
    if (input->buttons & VMMDEV_MOUSE_BUTTON_MIDDLE)
	buttons |= (EV_LB | EV_RB);

    if (buttonMode == NX_OneButton)
    {
	if ((buttons & (EV_LB|EV_RB)) != 0)
	    buttons = EV_LB;
    }
    else if (buttonMode == NX_LeftButton)
    {
	int	temp=0;
	if (buttons & EV_LB)
	    temp = EV_RB;
	if (buttons & EV_RB)
	    temp |= EV_LB;
	buttons = temp;
    }
    
    position.x = input->x ;
    position.y = input->y ;
    
    [deviceLock unlock];
    
    [[self owner] absolutePointerEvent:buttons at:&position inProximity:YES];
    
    return self;
} 

@end
