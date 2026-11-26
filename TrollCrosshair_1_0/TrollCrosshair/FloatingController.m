#import "FloatingController.h"
#import "TCLogger.h"
#import "FISettings.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>
#import <notify.h>
#import <spawn.h>
#import <signal.h>
#import <unistd.h>
#import <dlfcn.h>

extern char **environ;
static NSString * const TCFloatingRefreshNotification = @"com.trollcrosshair.refresh";
static NSString * const TCFloatingReadyNotification = @"com.trollcrosshair.ready";

static NSURL *TCHUDImageURL(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TrollCrosshairData"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"TrollCrosshair.png"]];
}
static NSURL *TCHUDPIDURL(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TrollCrosshairData"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"TrollCrosshair-HUD.pid"]];
}

@interface TCHUDWindow : UIWindow
@end
@implementation TCHUDWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return YES; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
@end

@interface TCHUDProcessDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,strong) id hostingController;
- (void)reloadOverlay;
@end

@implementation TCHUDProcessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[TCHUDWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.windowLevel = (UIWindowLevel)10000010.0;
    self.window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    self.imageView = [UIImageView new];
    self.imageView.backgroundColor = UIColor.clearColor;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.userInteractionEnabled = NO;
    [root.view addSubview:self.imageView];
    self.window.rootViewController = root;
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    Class hostClass = objc_getClass("SBSAccessibilityWindowHostingController");
    SEL contextSelector = sel_registerName("_contextId");
    if (!hostClass || ![self.window respondsToSelector:contextSelector]) {
        TCLog(@"HUD hosting unavailable: hostClass=%@ contextSelector=%d", hostClass, [self.window respondsToSelector:contextSelector]);
        return YES;
    }
    self.hostingController = [[hostClass alloc] init];
    unsigned int contextID = ((unsigned int (*)(id, SEL))objc_msgSend)(self.window, contextSelector);
    double level = self.window.windowLevel;
    @try {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.hostingController];
        [invocation setSelector:sel_registerName("registerWindowWithContextID:atLevel:")];
        [invocation setArgument:&contextID atIndex:2];
        [invocation setArgument:&level atIndex:3];
        [invocation invoke];
        TCLog(@"HUD window registered with BackBoard context=%u level=%.1f", contextID, level);
    } @catch (NSException *exception) {
        TCLog(@"HUD window registration exception: %@", exception);
    }

    int token = 0;
    notify_register_dispatch(TCFloatingRefreshNotification.UTF8String, &token, dispatch_get_main_queue(), ^(int t) {
        [self reloadOverlay];
    });
    [self reloadOverlay];
    notify_post(TCFloatingReadyNotification.UTF8String);
    return YES;
}
- (void)reloadOverlay {
    [FISettings.shared reload];
    UIImage *image = [UIImage imageWithContentsOfFile:TCHUDImageURL().path];
    self.imageView.image = image;
    if (!image) {
        self.imageView.hidden = YES;
        return;
    }
    self.imageView.hidden = NO;
    FISettings *s = FISettings.shared;
    CGSize source = image.size;
    CGFloat longest = MAX(source.width, source.height);
    CGFloat factor = longest > 0 ? (180.0 * (s.sizeScale / 100.0)) / longest : 1.0;
    CGFloat width = MAX(1.0, source.width * factor);
    CGFloat height = MAX(1.0, source.height * factor);
    CGRect screen = self.window.bounds;
    UIEdgeInsets safe = self.window.safeAreaInsets;
    CGRect usable = UIEdgeInsetsInsetRect(screen, safe);
    self.imageView.bounds = CGRectMake(0, 0, width, height);
    self.imageView.center = CGPointMake(CGRectGetMidX(usable) + s.x, CGRectGetMidY(usable) + s.y);
    self.imageView.alpha = MIN(1.0, MAX(0.0, s.alpha));
    self.window.hidden = !s.enabled;
}
@end

@interface TCHUDApplication : UIApplication
@end
@implementation TCHUDApplication
@end

@interface UIApplication (TCHUDPrivate)
- (void)_accessibilityInit;
- (void)__completeAndRunAsPlugin;
- (void)terminateWithSuccess;
@end

@interface FloatingController ()
@property(nonatomic,strong) NSURL *imageURL;
@property(nonatomic,assign) pid_t hudPID;
@end

@implementation FloatingController
+ (instancetype)shared {
    static FloatingController *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [FloatingController new]; });
    return c;
}
- (BOOL)isOverlayReady {
    pid_t pid = self.hudPID;
    if (pid <= 0) {
        NSString *saved = [NSString stringWithContentsOfURL:TCHUDPIDURL() encoding:NSUTF8StringEncoding error:nil];
        pid = (pid_t)saved.intValue;
    }
    return pid > 0 && kill(pid, 0) == 0;
}
- (void)showImageAtURL:(NSURL *)url {
    if (!url) return;
    self.imageURL = url;
    TCLog(@"HUD image selected: %@", url.path);
    notify_post(TCFloatingRefreshNotification.UTF8String);
}
- (void)refresh {
    notify_post(TCFloatingRefreshNotification.UTF8String);
}
- (void)startHUDProcess {
    if (self.isOverlayReady) {
        notify_post(TCFloatingRefreshNotification.UTF8String);
        return;
    }
    NSString *executable = NSBundle.mainBundle.executablePath;
    if (!executable.length) {
        TCLog(@"Cannot start HUD: executable path missing");
        return;
    }
    char *argv[] = {(char *)executable.UTF8String, "-hud", NULL};
    pid_t pid = 0;
    int result = posix_spawn(&pid, executable.fileSystemRepresentation, NULL, NULL, argv, environ);
    if (result != 0) {
        TCLog(@"posix_spawn HUD failed: %d", result);
        return;
    }
    self.hudPID = pid;
    [[NSString stringWithFormat:@"%d", pid] writeToURL:TCHUDPIDURL() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TCLog(@"HUD process spawned pid=%d", pid);
}
- (void)stopHUDProcess {
    pid_t pid = self.hudPID;
    if (pid <= 0) {
        NSString *saved = [NSString stringWithContentsOfURL:TCHUDPIDURL() encoding:NSUTF8StringEncoding error:nil];
        pid = (pid_t)saved.intValue;
    }
    if (pid > 0 && kill(pid, 0) == 0) {
        kill(pid, SIGTERM);
        TCLog(@"HUD process stopped pid=%d", pid);
    }
    self.hudPID = 0;
    [NSFileManager.defaultManager removeItemAtURL:TCHUDPIDURL() error:nil];
}
- (void)setEnabled:(BOOL)enabled {
    FISettings.shared.enabled = enabled;
    [FISettings.shared save];
    if (enabled) [self startHUDProcess]; else [self stopHUDProcess];
    TCLog(@"Floating enabled=%d HUD process ready=%d", enabled, self.isOverlayReady);
}
@end

static void *TCHUDSymbol(const char *name, const char *frameworkPath) {
    void *handle = dlopen(frameworkPath, RTLD_NOW);
    void *symbol = dlsym(handle ?: RTLD_DEFAULT, name);
    if (!symbol) symbol = dlsym(RTLD_DEFAULT, name);
    return symbol;
}

int TCHUDMain(void) {
    @autoreleasepool {
        TCLog(@"HUD helper process starting");
        [UIScreen initialize];
        CFRunLoopGetCurrent();

        typedef void (*VoidFunction)(void);
        typedef void (*InstantiateFunction)(id);
        VoidFunction gs = (VoidFunction)TCHUDSymbol("GSInitialize", "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices");
        VoidFunction bks = (VoidFunction)TCHUDSymbol("BKSDisplayServicesStart", "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices");
        VoidFunction ui = (VoidFunction)TCHUDSymbol("UIApplicationInitialize", "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore");
        InstantiateFunction instantiate = (InstantiateFunction)TCHUDSymbol("UIApplicationInstantiateSingleton", "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore");
        if (!gs || !bks || !ui || !instantiate) {
            TCLog(@"HUD bootstrap symbols missing GS=%d BKS=%d UI=%d instantiate=%d", gs != NULL, bks != NULL, ui != NULL, instantiate != NULL);
            return EXIT_FAILURE;
        }
        gs(); bks(); ui();
        instantiate(TCHUDApplication.class);
        UIApplication *app = UIApplication.sharedApplication;
        // UIApplication's delegate is not guaranteed to be retained; keep the
        // helper delegate alive for the entire hosted-window process lifetime.
        static TCHUDProcessDelegate *delegate = nil;
        delegate = [TCHUDProcessDelegate new];
        [app setDelegate:delegate];
        [app _accessibilityInit];

        typedef void (*GSEventInitializeFunction)(Boolean);
        typedef void (*GSEventPushRunLoopModeFunction)(CFStringRef);
        GSEventInitializeFunction eventInitialize = (GSEventInitializeFunction)TCHUDSymbol("GSEventInitialize", "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices");
        GSEventPushRunLoopModeFunction pushRunLoopMode = (GSEventPushRunLoopModeFunction)TCHUDSymbol("GSEventPushRunLoopMode", "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices");
        if (eventInitialize) eventInitialize(0);
        if (pushRunLoopMode) pushRunLoopMode(kCFRunLoopDefaultMode);

        [app __completeAndRunAsPlugin];
        CFRunLoopRun();
        return EXIT_SUCCESS;
    }
}
