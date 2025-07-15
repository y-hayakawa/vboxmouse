

#import <appkit/appkit.h>

#import "IconView.h"

@implementation IconView

- initFrame:(const NXRect *)newFrame
{
    [super initFrame:newFrame];
    return self ;
}

- setImage:(NXImage *) image 
{
    iconImage = image ;
    return self ;
}

- drawSelf:(const NXRect *)rects :(int)rectCount
{
    NXPoint pt = {0.0, 0.0};
    // NXSetColor(NX_COLORWHITE);
    // NXRectFill(rects);
    [iconImage composite:NX_SOVER toPoint: &pt];

    return self ;
}

@end
