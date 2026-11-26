#import "FISettings.h"
#import <notify.h>

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
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    self.x = [d objectForKey:@"fi.x"] ? [d doubleForKey:@"fi.x"] : 0;
    self.y = [d objectForKey:@"fi.y"] ? [d doubleForKey:@"fi.y"] : 0;
    self.sizeScale = [d objectForKey:@"fi.sizeScale"] ? [d doubleForKey:@"fi.sizeScale"] : 100;
    self.alpha = [d objectForKey:@"fi.alpha"] ? [d doubleForKey:@"fi.alpha"] : 0.85;
    self.enabled = [d boolForKey:@"fi.enabled"];
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
