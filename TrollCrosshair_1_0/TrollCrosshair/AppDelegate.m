#import "AppDelegate.h"
#import "TCLogger.h"
#import "RootViewController.h"
#import "SceneDelegate.h"
#import "FISettings.h"
#import "FloatingController.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    TCLog(@"TrollCrosshair settings app launched");
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = SceneDelegate.class;
    return configuration;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if (![url.scheme.lowercaseString isEqualToString:@"trollcrosshair"]) return NO;
    NSString *command = url.host.lowercaseString;
    if (command.length == 0) command = url.path.lowercaseString;
    FloatingController *floating = FloatingController.shared;
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
        BOOL next = !FISettings.shared.isEnabled;
        NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *imageURL = [directory URLByAppendingPathComponent:@"TrollCrosshair.png"];
        if (next && [NSFileManager.defaultManager fileExistsAtPath:imageURL.path]) [floating showImageAtURL:imageURL];
        [floating setEnabled:next];
    } else {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TrollCrosshairStateChanged" object:nil];
    return YES;
}
@end
