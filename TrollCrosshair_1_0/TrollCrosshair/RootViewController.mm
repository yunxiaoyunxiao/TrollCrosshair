#import "RootViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <notify.h>
#import "TCLogger.h"
#import "FISettings.h"
#import "FloatingController.h"

@interface RootViewController () <PHPickerViewControllerDelegate>
@property(nonatomic,strong) UIView *previewContainer;
@property(nonatomic,strong) UIImageView *preview;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *toggleButton;
@property(nonatomic,strong) NSURL *imageURL;
@property(nonatomic,strong) NSMutableArray<UISlider *> *sliders;
@property(nonatomic,strong) UIStackView *contentStack;
@property(nonatomic,assign) int readyNotifyToken;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.sliders = [NSMutableArray array];
    [self buildUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shortcutStateChanged) name:@"TrollCrosshairStateChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(overlayReady) name:@"TCFloatingOverlayReadyNotification" object:nil];
    int readyToken = 0;
    notify_register_dispatch("com.trollcrosshair.ready", &readyToken, dispatch_get_main_queue(), ^(int token) {
        self.status.text = @"悬浮已开启";
        [self updateToggleTitle];
    });
    self.readyNotifyToken = readyToken;
    [self loadSavedOrDefaultImage];
    [self syncControls];
    if (FISettings.shared.isEnabled && self.imageURL) {
        [[FloatingController shared] showImageAtURL:self.imageURL];
        [[FloatingController shared] setEnabled:YES];
        self.status.text = @"正在启动悬浮…";
    }
}

- (UILabel *)label:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    return label;
}

- (void)buildUI {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18]
    ]];

    UIStackView *stack = [UIStackView new];
    self.contentStack = stack;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];

    UILabel *title = [self label:@"图片悬浮"];
    title.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBold];
    [stack addArrangedSubview:title];

    self.status = [self label:@"正在准备图片…"];
    self.status.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:self.status];

    UIStackView *actions = [UIStackView new];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 12;
    UIButton *pick = [UIButton buttonWithType:UIButtonTypeSystem];
    [pick setTitle:@"选择图片" forState:UIControlStateNormal];
    [pick addTarget:self action:@selector(pickImage) forControlEvents:UIControlEventTouchUpInside];
    [actions addArrangedSubview:pick];

    UIButton *copyLog = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyLog setTitle:@"复制日志" forState:UIControlStateNormal];
    [copyLog addTarget:self action:@selector(copyDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    [actions addArrangedSubview:copyLog];
    [stack addArrangedSubview:actions];

    self.previewContainer = [UIView new];
    self.previewContainer.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.previewContainer.layer.cornerRadius = 12;
    self.previewContainer.clipsToBounds = YES;
    self.previewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.previewContainer.heightAnchor constraintEqualToConstant:230].active = YES;
    [stack addArrangedSubview:self.previewContainer];

    self.preview = [UIImageView new];
    self.preview.contentMode = UIViewContentModeScaleToFill;
    self.preview.userInteractionEnabled = NO;
    [self.previewContainer addSubview:self.preview];

    [self addSlider:@"X 位置" min:-2048 max:2048 value:FISettings.shared.x];
    [self addSlider:@"Y 位置" min:-2048 max:2048 value:FISettings.shared.y];
    [self addSlider:@"图片大小" min:25 max:300 value:FISettings.shared.sizeScale];
    [self addSlider:@"透明度" min:0.05 max:1 value:FISettings.shared.alpha];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [self.toggleButton addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.toggleButton];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"重置参数" forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(resetValues) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:reset];
}

- (void)addSlider:(NSString *)name min:(float)min max:(float)max value:(float)value {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 3;
    [row addArrangedSubview:[self label:name]];
    UISlider *slider = [UISlider new];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:slider];
    [self.sliders addObject:slider];
    [self.contentStack addArrangedSubview:row];
}

- (void)pickImage {
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) {
        self.status.text = @"未选择图片";
        return;
    }

    NSMutableArray<NSString *> *types = [provider.registeredTypeIdentifiers mutableCopy];
    NSArray *priority = @[@"public.png", @"public.jpeg", @"public.heic", @"public.jpg", @"public.image"];
    [types sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ai = [priority indexOfObject:a];
        NSUInteger bi = [priority indexOfObject:b];
        if (ai == NSNotFound) ai = NSUIntegerMax;
        if (bi == NSNotFound) bi = NSUIntegerMax;
        return ai < bi ? NSOrderedAscending : (ai > bi ? NSOrderedDescending : NSOrderedSame);
    }];
    TCLog(@"Picker representations: %@", types);
    self.status.text = @"正在读取图片…";
    [self loadImageFromProvider:provider types:types index:0];
}

- (void)loadImageFromProvider:(NSItemProvider *)provider types:(NSArray<NSString *> *)types index:(NSUInteger)index {
    if (index >= types.count) {
        self.status.text = @"图片读取失败";
        TCLog(@"All image representations failed: %@", types);
        return;
    }

    NSString *type = types[index];
    if (![provider hasItemConformingToTypeIdentifier:type]) {
        [self loadImageFromProvider:provider types:types index:index + 1];
        return;
    }

    [provider loadDataRepresentationForTypeIdentifier:type completionHandler:^(NSData *data, NSError *error) {
        UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
        TCLog(@"Image representation %@: bytes=%lu error=%@", type, (unsigned long)data.length, error);
        if (image) {
            [self savePickedImage:image];
        } else {
            [self loadImageFromProvider:provider types:types index:index + 1];
        }
    }];
}

- (void)savePickedImage:(UIImage *)image {
    NSData *data = UIImagePNGRepresentation(image);
    if (!data.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = @"图片转换失败"; });
        return;
    }
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = @"无法保存图片"; });
        TCLog(@"Create image directory failed: %@", error);
        return;
    }
    NSURL *url = [directory URLByAppendingPathComponent:@"TrollCrosshair.png"];
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = @"图片保存失败"; });
        TCLog(@"Save image failed: %@", error);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.imageURL = url;
        self.preview.image = image;
        [self updatePreview];
        [[FloatingController shared] showImageAtURL:url];
        [[FloatingController shared] setEnabled:YES];
        self.status.text = @"正在启动悬浮…";
        [self updateToggleTitle];
    });
    TCLog(@"Picked image saved: %lu bytes", (unsigned long)data.length);
}

- (void)loadSavedOrDefaultImage {
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *savedURL = [directory URLByAppendingPathComponent:@"TrollCrosshair.png"];
    UIImage *image = [UIImage imageWithContentsOfFile:savedURL.path];

    if (!image) {
        NSString *resourcePath = [NSBundle.mainBundle pathForResource:@"IMG_9324.png" ofType:@"b64"];
        NSString *encoded = resourcePath ? [NSString stringWithContentsOfFile:resourcePath encoding:NSUTF8StringEncoding error:nil] : nil;
        NSData *pngData = encoded ? [[NSData alloc] initWithBase64EncodedString:[encoded stringByReplacingOccurrencesOfString:@"\n" withString:@""] options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
        image = pngData.length ? [UIImage imageWithData:pngData] : nil;
        if (image) {
            [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
            [pngData writeToURL:savedURL options:NSDataWritingAtomic error:nil];
            TCLog(@"Installed bundled default image");
        } else {
            TCLog(@"Bundled default image could not be loaded");
        }
    } else {
        TCLog(@"Restored user-selected image");
    }

    if (image) {
        self.imageURL = savedURL;
        self.preview.image = image;
        [[FloatingController shared] showImageAtURL:savedURL];
        self.status.text = @"图片已就绪";
    } else {
        self.status.text = @"请选择图片";
    }
}

- (void)copyDiagnostics {
    NSURL *url = TCLogFileURL();
    NSString *log = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (log.length == 0) log = @"暂无诊断日志";
    UIPasteboard.generalPasteboard.string = log;
    self.status.text = @"日志已复制";
}

- (void)sliderChanged:(UISlider *)slider {
    NSInteger index = [self.sliders indexOfObject:slider];
    FISettings *settings = FISettings.shared;
    switch (index) {
        case 0: settings.x = slider.value; break;
        case 1: settings.y = slider.value; break;
        case 2: settings.sizeScale = slider.value; break;
        case 3: settings.alpha = slider.value; break;
    }
    [settings save];
    [self updatePreview];
    [[FloatingController shared] refresh];
    TCLog(@"Setting changed: %ld X=%.1f Y=%.1f size=%.1f%% alpha=%.2f", (long)index, settings.x, settings.y, settings.sizeScale, settings.alpha);
}

- (void)updatePreview {
    if (!self.preview || !self.previewContainer || !self.preview.image) return;
    FISettings *settings = FISettings.shared;
    CGRect bounds = self.previewContainer.bounds;
    if (CGRectIsEmpty(bounds)) return;
    CGSize source = self.preview.image.size;
    CGFloat longest = MAX(source.width, source.height);
    CGFloat maxSide = MIN(190.0, MIN(bounds.size.width - 24.0, bounds.size.height - 24.0));
    CGFloat previewScale = longest > 0 ? maxSide / longest : 1.0;
    CGFloat width = MAX(1.0, source.width * previewScale * (settings.sizeScale / 100.0));
    CGFloat height = MAX(1.0, source.height * previewScale * (settings.sizeScale / 100.0));
    self.preview.bounds = CGRectMake(0, 0, width, height);
    CGFloat offsetX = settings.x * bounds.size.width / MAX(1.0, UIScreen.mainScreen.bounds.size.width);
    CGFloat offsetY = settings.y * bounds.size.height / MAX(1.0, UIScreen.mainScreen.bounds.size.height);
    self.preview.center = CGPointMake(CGRectGetMidX(bounds) + offsetX,
                                      CGRectGetMidY(bounds) + offsetY);
    self.preview.alpha = MIN(1.0, MAX(0.0, settings.alpha));
}

- (void)syncControls {
    FISettings *settings = FISettings.shared;
    NSArray *values = @[@(settings.x), @(settings.y), @(settings.sizeScale), @(settings.alpha)];
    for (NSUInteger i = 0; i < MIN(values.count, self.sliders.count); i++) self.sliders[i].value = [values[i] floatValue];
    [self updatePreview];
    [self updateToggleTitle];
}

- (void)shortcutStateChanged { [self updateToggleTitle]; [self updatePreview]; }

- (void)overlayReady {
    self.status.text = FISettings.shared.isEnabled ? @"悬浮已开启" : @"图片已就绪";
    [self updateToggleTitle];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.readyNotifyToken > 0) notify_cancel(self.readyNotifyToken);
}

- (void)updateToggleTitle {
    [self.toggleButton setTitle:(FISettings.shared.isEnabled ? @"关闭悬浮" : @"开启悬浮") forState:UIControlStateNormal];
}

- (void)toggle {
    if (!self.imageURL && !FISettings.shared.isEnabled) {
        self.status.text = @"请先选择图片";
        return;
    }
    BOOL enabled = !FISettings.shared.isEnabled;
    [[FloatingController shared] setEnabled:enabled];
    self.status.text = enabled ? @"正在启动悬浮…" : @"悬浮已关闭";
    [self updateToggleTitle];
    TCLog(@"Floating toggle: %d overlayReady=%d", enabled, [FloatingController shared].isOverlayReady);
}

- (void)resetValues {
    [FISettings.shared reset];
    [self syncControls];
    [[FloatingController shared] refresh];
}

- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self updatePreview]; }

@end
