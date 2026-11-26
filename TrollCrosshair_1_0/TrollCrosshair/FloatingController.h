#import <UIKit/UIKit.h>

@interface FloatingController : NSObject
+ (instancetype)shared;
- (void)attachOverlayWindow:(UIWindow *)window;
- (void)showImageAtURL:(NSURL *)url;
- (void)refresh;
- (void)setEnabled:(BOOL)enabled;
@end
