#import "AppDelegate.h"
#import "TCLogger.h"
#import "RootViewController.h"
#import "SceneDelegate.h"
#import "FISettings.h"
#import "FloatingController.h"
#import <objc/message.h>
#import <dlfcn.h>

@interface AppDelegate ()
@property(nonatomic,strong) id floatingSceneBinder;
@property(nonatomic,assign) BOOL floatingSceneStarted;
@end

@implementation AppDelegate

- (void)createFloatingScene {
    if (self.floatingSceneStarted) return;
    self.floatingSceneStarted = YES;
    TCLog(@"[TrollCrosshair] Starting FrontBoard overlay initialization after main scene connection");
    NSString *frameworkPath = @"/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices";
    void *framework = dlopen(frameworkPath.UTF8String, RTLD_NOW);
    if (!framework) {
        TCLog(@"[TrollCrosshair] Unable to load FrontBoardServices: %s", dlerror());
        return;
    }

    typedef void (*FBSystemShellInitializeFunction)(id);
    FBSystemShellInitializeFunction initialize = (FBSystemShellInitializeFunction)dlsym(framework, "FBSystemShellInitialize");
    if (!initialize) {
        TCLog(@"[TrollCrosshair] FBSystemShellInitialize is unavailable");
        return;
    }

    __weak typeof(self) weakSelf = self;
    initialize(^(id context) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        @try {
            Class managerClass = NSClassFromString(@"FBSceneManager");
            Class definitionClass = NSClassFromString(@"FBSMutableSceneDefinition");
            Class identityClass = NSClassFromString(@"FBSSceneIdentity");
            Class clientIdentityClass = NSClassFromString(@"FBSSceneClientIdentity");
            Class specificationClass = NSClassFromString(@"UIApplicationSceneSpecification");
            Class parametersClass = NSClassFromString(@"FBSMutableSceneParameters");
            Class settingsClass = NSClassFromString(@"UIMutableApplicationSceneSettings");
            Class clientSettingsClass = NSClassFromString(@"UIMutableApplicationSceneClientSettings");
            Class binderClass = NSClassFromString(@"UIRootWindowScenePresentationBinder");

            if (!managerClass || !definitionClass || !identityClass || !clientIdentityClass ||
                !specificationClass || !parametersClass || !settingsClass || !clientSettingsClass || !binderClass) {
                TCLog(@"[TrollCrosshair] Required FrontBoard classes are unavailable");
                return;
            }

            id (*send0)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id (*send1)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
            id (*send2)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;

            id manager = send0(managerClass, sel_registerName("sharedInstance"));
            id definition = send0(definitionClass, sel_registerName("definition"));
            id identity = send1(identityClass, sel_registerName("identityForIdentifier:"), @"com.trollcrosshair.app.overlay");
            id clientIdentity = send0(clientIdentityClass, sel_registerName("localIdentity"));
            id specification = send0(specificationClass, sel_registerName("specification"));
            id parameters = send1(parametersClass, sel_registerName("parametersForSpecification:"), specification);

            id displayConfiguration = send0(UIScreen.mainScreen, sel_registerName("displayConfiguration"));
            CGRect (*sendCGRect0)(id, SEL) = (CGRect (*)(id, SEL))objc_msgSend;
            CGRect referenceBounds = sendCGRect0(UIScreen.mainScreen, sel_registerName("_referenceBounds"));
            if (CGRectIsEmpty(referenceBounds)) referenceBounds = UIScreen.mainScreen.bounds;

            id settings = send0(settingsClass, @selector(new));
            [settings setValue:displayConfiguration forKey:@"displayConfiguration"];
            [settings setValue:[NSValue valueWithCGRect:referenceBounds] forKey:@"frame"];
            [settings setValue:@1 forKey:@"level"];
            [settings setValue:@YES forKey:@"foreground"];
            [settings setValue:@(UIApplication.sharedApplication.statusBarOrientation) forKey:@"interfaceOrientation"];
            [settings setValue:@YES forKey:@"deviceOrientationEventsEnabled"];
            id ignoreReasons = send0(settings, sel_registerName("ignoreOcclusionReasons"));
            [ignoreReasons addObject:@"SystemApp"];

            id clientSettings = send0(clientSettingsClass, @selector(new));
            [clientSettings setValue:@(UIApplication.sharedApplication.statusBarOrientation) forKey:@"interfaceOrientation"];
            [clientSettings setValue:@0 forKey:@"statusBarStyle"];

            [definition setValue:identity forKey:@"identity"];
            [definition setValue:clientIdentity forKey:@"clientIdentity"];
            [definition setValue:specification forKey:@"specification"];
            [parameters setValue:settings forKey:@"settings"];
            [parameters setValue:clientSettings forKey:@"clientSettings"];

            id scene = send2(manager, sel_registerName("createSceneWithDefinition:initialParameters:"), definition, parameters);
            if (!scene) {
                TCLog(@"[TrollCrosshair] FrontBoard did not create the overlay scene");
                return;
            }

            id (*initBinder)(id, SEL, int, id) = (id (*)(id, SEL, int, id))objc_msgSend;
            id binder = initBinder([binderClass alloc], sel_registerName("initWithPriority:displayConfiguration:"), 0, displayConfiguration);
            ((void (*)(id, SEL, id))objc_msgSend)(binder, sel_registerName("addScene:"), scene);
            self.floatingSceneBinder = binder;
            TCLog(@"[TrollCrosshair] Global overlay scene created");
        } @catch (NSException *exception) {
            TCLog(@"[TrollCrosshair] FrontBoard setup failed: %@", exception);
        }
    });
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // The primary UIWindowScene must connect first. SceneDelegate starts the
    // FrontBoard overlay after its main window is visible.
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
