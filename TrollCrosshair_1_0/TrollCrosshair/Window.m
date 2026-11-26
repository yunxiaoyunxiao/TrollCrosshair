#import "Window.h"

@implementation Window
// TrollStore/FrontBoard overlay window: let all touch events pass to the app below.
- (BOOL)_ignoresHitTest {
    return YES;
}
@end
