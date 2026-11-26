#import "SceneDelegate.h"
#import "TCLogger.h"
#import "AppDelegate.h"
#import "RootViewController.h"
#import "FloatingController.h"
#import "FISettings.h"
#import "Window.h"

static NSString * const TCFloatingSceneIdentifier = @"com.trollcrosshair.app.overlay";

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    TCLog(@"[TrollCrosshair] Scene connecting: persistentIdentifier=%@ role=%@", session.persistentIdentifier, session.role);

    if ([session.persistentIdentifier isEqualToString:TCFloatingSceneIdentifier]) {
        Window *overlay = [[Window alloc] initWithWindowScene:windowScene];
        overlay.frame = windowScene.coordinateSpace.bounds;
        overlay.windowLevel = 10000.0;
        overlay.backgroundColor = UIColor.clearColor;
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = UIColor.clearColor;
        overlay.rootViewController = root;
        self.window = overlay;
        [overlay setHidden:NO];
        [[FloatingController shared] attachOverlayWindow:overlay];
        overlay.hidden = !FISettings.shared.isEnabled;
        return;
    }

    UIWindow *mainWindow = [[UIWindow alloc] initWithWindowScene:windowScene];
    mainWindow.rootViewController = [RootViewController new];
    self.window = mainWindow;
    [mainWindow makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        [(AppDelegate *)UIApplication.sharedApplication.delegate createFloatingScene];
    });
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    for (UIOpenURLContext *context in URLContexts) {
        [appDelegate application:UIApplication.sharedApplication openURL:context.URL options:context.options];
    }
}

- (void)windowScene:(UIWindowScene *)windowScene didUpdateCoordinateSpace:(id< UICoordinateSpace >)previousCoordinateSpace interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection *)previousTraitCollection {
    if ([windowScene.session.persistentIdentifier isEqualToString:TCFloatingSceneIdentifier]) {
        self.window.frame = windowScene.coordinateSpace.bounds;
        [[FloatingController shared] refresh];
    }
}

@end
