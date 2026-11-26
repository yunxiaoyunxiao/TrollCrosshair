#import "AppDelegate.h"
#import "RootViewController.h"
#import "FISettings.h"
#import "FloatingController.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [RootViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if (![url.scheme.lowercaseString isEqualToString:@"trollcrosshair"]) return NO;

    NSString *command = url.host.lowercaseString;
    if (command.length == 0) command = url.path.lowercaseString;
    FloatingController *floating = [FloatingController shared];

    if ([command isEqualToString:@"show"] || [command isEqualToString:@"on"]) {
        NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *imageURL = [directory URLByAppendingPathComponent:@"TrollCrosshair.png"];
        if ([NSFileManager.defaultManager fileExistsAtPath:imageURL.path]) {
            [floating showImageAtURL:imageURL];
            [floating setEnabled:YES];
        }
    } else if ([command isEqualToString:@"hide"] || [command isEqualToString:@"off"]) {
        [floating setEnabled:NO];
    } else if ([command isEqualToString:@"toggle"]) {
        BOOL nextValue = !FISettings.shared.isEnabled;
        if (nextValue) {
            NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *imageURL = [directory URLByAppendingPathComponent:@"TrollCrosshair.png"];
            if ([NSFileManager.defaultManager fileExistsAtPath:imageURL.path]) [floating showImageAtURL:imageURL];
        }
        [floating setEnabled:nextValue];
    } else {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TrollCrosshairStateChanged" object:nil];
    return YES;
}
@end
