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
#import <sys/types.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, uid_t);

extern char **environ;
static NSString * const TCFloatingRefreshNotification = @"com.trollcrosshair.refresh";
static NSString * const TCFloatingReadyNotification = @"com.trollcrosshair.ready";

static NSURL *TCHUDImageURL(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"TrollCrosshair.png"]];
}
static NSURL *TCHUDPIDURL(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"];
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

    // Helium loads SpringBoardServices before resolving the private hosting class.
    // Without this framework, objc_getClass may return nil and the HUD remains
    // an ordinary app-local UIWindow instead of a BackBoard-hosted window.
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW | RTLD_GLOBAL);
    Class hostClass = objc_getClass("SBSAccessibilityWindowHostingController");
    SEL contextSelector = sel_registerName("_contextId");
    TCLog(@"HUD host bootstrap uid=%d euid=%d hostClass=%@ windowContext=%d", getuid(), geteuid(), hostClass, [self.window respondsToSelector:contextSelector]);
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
    CFPropertyListRef copiedValue = CFPreferencesCopyAppValue(CFSTR("fi.overlayImageData"), CFSTR("com.trollcrosshair.app"));
    NSData *imageData = copiedValue ? CFBridgingRelease(copiedValue) : nil;
    if (![imageData isKindOfClass:NSData.class] || imageData.length == 0) imageData = [NSUserDefaults.standardUserDefaults dataForKey:@"fi.overlayImageData"];
    UIImage *image = imageData.length ? [UIImage imageWithData:imageData] : nil;
    TCLog(@"HUD image read: dataBytes=%lu decoded=%@", (unsigned long)imageData.length, image ? NSStringFromCGSize(image.size) : @"NO");
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
    // Kept as a compatibility shim; image bytes are now transferred through
    // the shared preferences domain, not a filesystem path.
    (void)url;
    [self refresh];
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
    // Match Helium's launch model: the HUD must run under the platform/root
    // persona so BackBoard accepts its system-level hosted window. A normal
    // app-persona child can launch successfully yet remain confined to the
    // app's ordinary window scene, which looks like "no cross-app overlay".
    posix_spawnattr_t attributes;
    int attrResult = posix_spawnattr_init(&attributes);
    if (attrResult != 0) {
        TCLog(@"HUD spawn attr init failed: %d", attrResult);
        return;
    }
    int personaResult = posix_spawnattr_set_persona_np(&attributes, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int uidResult = posix_spawnattr_set_persona_uid_np(&attributes, 0);
    int gidResult = posix_spawnattr_set_persona_gid_np(&attributes, 0);
    int groupResult = posix_spawnattr_setpgroup(&attributes, 0);
    int flagsResult = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    if (personaResult || uidResult || gidResult || groupResult || flagsResult) {
        TCLog(@"HUD persona setup failed persona=%d uid=%d gid=%d pgroup=%d flags=%d",
              personaResult, uidResult, gidResult, groupResult, flagsResult);
        posix_spawnattr_destroy(&attributes);
        return;
    }
    char *argv[] = {(char *)executable.UTF8String, "-hud", NULL};
    pid_t pid = 0;
    int result = posix_spawn(&pid, executable.fileSystemRepresentation, NULL, &attributes, argv, environ);
    posix_spawnattr_destroy(&attributes);
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
