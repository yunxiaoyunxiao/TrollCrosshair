#import "FloatingController.h"
#import "FISettings.h"

@interface FloatingController ()
@property(nonatomic,strong) UIWindow *overlayWindow;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,strong) NSURL *imageURL;
@end

@implementation FloatingController
+ (instancetype)shared {
    static FloatingController *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [FloatingController new]; });
    return c;
}
- (void)attachOverlayWindow:(UIWindow *)window {
    if (!window) return;
    self.overlayWindow = window;
    self.overlayWindow.backgroundColor = UIColor.clearColor;
    if (!self.overlayWindow.rootViewController) self.overlayWindow.rootViewController = [UIViewController new];
    self.overlayWindow.rootViewController.view.backgroundColor = UIColor.clearColor;

    [self.imageView removeFromSuperview];
    self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.imageView.contentMode = UIViewContentModeScaleToFill;
    self.imageView.userInteractionEnabled = NO;
    [self.overlayWindow.rootViewController.view addSubview:self.imageView];

    if (self.imageURL) {
        self.imageView.image = [UIImage imageWithContentsOfFile:self.imageURL.path];
        [self refresh];
    }
    self.overlayWindow.hidden = !FISettings.shared.isEnabled;
}

- (void)showImageAtURL:(NSURL *)url {
    self.imageURL = url;
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    if (!image) return;
    if (!self.overlayWindow) {
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
        }
        if (!scene) return;
        self.overlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
        self.overlayWindow.frame = scene.coordinateSpace.bounds;
        self.overlayWindow.windowLevel = UIWindowLevelAlert + 1;
        self.overlayWindow.backgroundColor = UIColor.clearColor;
        self.overlayWindow.rootViewController = [UIViewController new];
        self.overlayWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
        self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.imageView.contentMode = UIViewContentModeScaleToFill;
        self.imageView.userInteractionEnabled = NO;
        [self.overlayWindow.rootViewController.view addSubview:self.imageView];
    }
    self.imageView.image = image;
    [self refresh];
    self.overlayWindow.hidden = !FISettings.shared.isEnabled;
}
- (void)refresh {
    if (!self.overlayWindow || !self.imageView) return;
    FISettings *s = FISettings.shared;
    CGRect bounds = self.overlayWindow.bounds;
    UIEdgeInsets insets = self.overlayWindow.safeAreaInsets;
    CGRect usableBounds = UIEdgeInsetsInsetRect(bounds, insets);
    CGFloat cx = CGRectGetMidX(usableBounds) + s.x, cy = CGRectGetMidY(usableBounds) + s.y;
    self.imageView.bounds = CGRectMake(0, 0, MAX(1, s.width), MAX(1, s.height));
    self.imageView.center = CGPointMake(cx, cy);
    self.imageView.alpha = MIN(1, MAX(0, s.alpha));
}
- (void)setEnabled:(BOOL)enabled {
    FISettings.shared.enabled = enabled; [FISettings.shared save];
    if (enabled && self.imageURL) [self showImageAtURL:self.imageURL];
    self.overlayWindow.hidden = !enabled;
}
@end
