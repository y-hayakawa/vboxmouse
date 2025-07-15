

#import <appkit/appkit.h>

@interface IconView:View
{
    NXImage *iconImage ;
}

- setImage:(NXImage *) image;
- drawSelf:(const NXRect *)rects :(int)rectCount;

@end
