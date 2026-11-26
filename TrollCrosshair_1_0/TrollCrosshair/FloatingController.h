#import <UIKit/UIKit.h>

@interface FloatingController : NSObject
+ (instancetype)shared;
@property(nonatomic,readonly,getter=isOverlayReady) BOOL overlayReady;
- (void)refresh;
- (void)setEnabled:(BOOL)enabled;
@end

// Entry point used by main.m when this executable is relaunched as the HUD process.
int TCHUDMain(void);
