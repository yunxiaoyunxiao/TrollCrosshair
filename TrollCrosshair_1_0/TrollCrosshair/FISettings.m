#import "FISettings.h"

@implementation FISettings
+ (instancetype)shared {
    static FISettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [FISettings new];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        s.x = [d objectForKey:@"fi.x"] ? [d doubleForKey:@"fi.x"] : 0;
        s.y = [d objectForKey:@"fi.y"] ? [d doubleForKey:@"fi.y"] : 0;
        s.width = [d objectForKey:@"fi.width"] ? [d doubleForKey:@"fi.width"] : 180;
        s.height = [d objectForKey:@"fi.height"] ? [d doubleForKey:@"fi.height"] : 180;
        s.alpha = [d objectForKey:@"fi.alpha"] ? [d doubleForKey:@"fi.alpha"] : 0.85;
        s.enabled = [d boolForKey:@"fi.enabled"];
    });
    return s;
}
- (void)save {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:self.x forKey:@"fi.x"]; [d setDouble:self.y forKey:@"fi.y"];
    [d setDouble:self.width forKey:@"fi.width"]; [d setDouble:self.height forKey:@"fi.height"];
    [d setDouble:self.alpha forKey:@"fi.alpha"]; [d setBool:self.enabled forKey:@"fi.enabled"];
}
- (void)reset {
    self.x = 0; self.y = 0; self.width = 180; self.height = 180; self.alpha = 0.85;
    [self save];
}
@end
