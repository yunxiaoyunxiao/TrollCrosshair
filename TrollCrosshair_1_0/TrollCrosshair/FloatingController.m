#import "FloatingController.h"
#import "FISettings.h"

NSNotificationName const TCFloatingOverlayReadyNotification = @"TCFloatingOverlayReadyNotification";

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
- (BOOL)isOverlayReady { return self.overlayWindow != nil && self.imageView != nil; }

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
    self.imageView.backgroundColor = UIColor.clearColor;
    [self.overlayWindow.rootViewController.view addSubview:self.imageView];

    if (self.imageURL) self.imageView.image = [UIImage imageWithContentsOfFile:self.imageURL.path];
    [self refresh];
    self.overlayWindow.hidden = !FISettings.shared.isEnabled;
    NSLog(@"[TrollCrosshair] Overlay window attached; enabled=%d image=%@", FISettings.shared.isEnabled, self.imageURL.path);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TCFloatingOverlayReadyNotification object:self];
    });
}

- (void)showImageAtURL:(NSURL *)url {
    if (!url) return;
    self.imageURL = url;
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    if (!image) {
        NSLog(@"[TrollCrosshair] Failed to load image at %@", url.path);
        return;
    }
    // Do not create a normal app UIWindow here. That only overlays this app and
    // prevents the real FrontBoard scene from owning the image window.
    if (self.imageView) {
        self.imageView.image = image;
        [self refresh];
    }
    NSLog(@"[TrollCrosshair] Image loaded; global overlay ready=%d", self.isOverlayReady);
}

- (void)refresh {
    if (!self.overlayWindow || !self.imageView) return;
    FISettings *s = FISettings.shared;
    CGRect bounds = self.overlayWindow.bounds;
    UIEdgeInsets insets = self.overlayWindow.safeAreaInsets;
    CGRect usableBounds = UIEdgeInsetsInsetRect(bounds, insets);
    CGFloat cx = CGRectGetMidX(usableBounds) + s.x;
    CGFloat cy = CGRectGetMidY(usableBounds) + s.y;
    self.imageView.bounds = CGRectMake(0, 0, MAX(1, s.width), MAX(1, s.height));
    self.imageView.center = CGPointMake(cx, cy);
    self.imageView.alpha = MIN(1, MAX(0, s.alpha));
}

- (void)setEnabled:(BOOL)enabled {
    FISettings.shared.enabled = enabled;
    [FISettings.shared save];
    if (enabled && self.imageURL && self.imageView) {
        self.imageView.image = [UIImage imageWithContentsOfFile:self.imageURL.path];
        [self refresh];
    }
    self.overlayWindow.hidden = !enabled;
    NSLog(@"[TrollCrosshair] Floating enabled=%d overlayReady=%d", enabled, self.isOverlayReady);
}
@end
