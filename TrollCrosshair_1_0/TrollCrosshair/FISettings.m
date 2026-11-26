#import "FISettings.h"
#import <notify.h>

static id FIReadMobilePreference(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)key,
                                                     CFSTR("com.trollcrosshair.app"),
                                                     CFSTR("mobile"),
                                                     kCFPreferencesAnyHost);
    if (!value) {
        value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.trollcrosshair.app"));
    }
    return value ? CFBridgingRelease(value) : nil;
}

static NSString * const TCFloatingRefreshNotification = @"com.trollcrosshair.refresh";

@implementation FISettings
+ (instancetype)shared {
    static FISettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [FISettings new];
        [s reload];
    });
    return s;
}
- (void)reload {
    id x = FIReadMobilePreference(@"fi.x");
    id y = FIReadMobilePreference(@"fi.y");
    id size = FIReadMobilePreference(@"fi.sizeScale");
    id alpha = FIReadMobilePreference(@"fi.alpha");
    id enabled = FIReadMobilePreference(@"fi.enabled");
    self.x = x ? [x doubleValue] : 0;
    self.y = y ? [y doubleValue] : 0;
    self.sizeScale = size ? [size doubleValue] : 100;
    self.alpha = alpha ? [alpha doubleValue] : 0.85;
    self.enabled = enabled ? [enabled boolValue] : NO;
}
- (void)save {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:self.x forKey:@"fi.x"];
    [d setDouble:self.y forKey:@"fi.y"];
    [d setDouble:self.sizeScale forKey:@"fi.sizeScale"];
    [d setDouble:self.alpha forKey:@"fi.alpha"];
    [d setBool:self.enabled forKey:@"fi.enabled"];
    [d synchronize];
    notify_post(TCFloatingRefreshNotification.UTF8String);
}
- (void)reset {
    self.x = 0; self.y = 0; self.sizeScale = 100; self.alpha = 0.85;
    [self save];
}
@end
