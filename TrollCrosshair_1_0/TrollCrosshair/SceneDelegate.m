#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "TCLogger.h"
#import "RootViewController.h"

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [RootViewController new];
    self.window = window;
    [window makeKeyAndVisible];
    TCLog(@"Settings scene connected: %@", session.persistentIdentifier);

    // Handle a Shortcuts URL when the app is launched from a terminated state.
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    for (UIOpenURLContext *context in connectionOptions.URLContexts) {
        [appDelegate application:UIApplication.sharedApplication openURL:context.URL options:@{}];
    }
}
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    for (UIOpenURLContext *context in URLContexts) {
        [appDelegate application:UIApplication.sharedApplication openURL:context.URL options:context.options];
    }
}
@end
