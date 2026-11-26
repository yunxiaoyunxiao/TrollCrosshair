#import <UIKit/UIKit.h>

@interface FloatingController : NSObject
+ (instancetype)shared;
@property(nonatomic,readonly,getter=isOverlayReady) BOOL overlayReady;
- (void)refresh;
- (void)setEnabled:(BOOL)enabled;
// Executes a Shortcuts command in-process without opening the app's UI.
- (BOOL)performShortcutCommand:(NSString *)command;
@end

// Entry point used by main.m when this executable is relaunched as the HUD process.
int TCHUDMain(void);
