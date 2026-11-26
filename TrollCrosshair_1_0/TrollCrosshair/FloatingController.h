#import <UIKit/UIKit.h>

@interface FloatingController : NSObject
+ (instancetype)shared;
- (void)showImageAtURL:(NSURL *)url;
- (void)refresh;
- (void)setEnabled:(BOOL)enabled;
@end
