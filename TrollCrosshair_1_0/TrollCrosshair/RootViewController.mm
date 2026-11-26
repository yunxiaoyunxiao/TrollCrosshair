#import "RootViewController.h"
#import <notify.h>
#import "TCLogger.h"
#import "FISettings.h"
#import "FloatingController.h"

@interface RootViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
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
    // Use UIKit's long-established photo-library controller here. The previous
    // PHPicker + NSItemProvider file-representation chain was the only new,
    // asynchronous path introduced immediately before the reported crash.
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image"];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    self.status.text = self.imageURL ? @"图片已就绪" : @"请选择图片";
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSURL *originalURL = info[UIImagePickerControllerImageURL];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!image) {
            self.status.text = @"没有取得图片，请重新选择";
            TCLog(@"UIImagePicker returned no original UIImage; info keys=%@", info.allKeys);
            return;
        }
        TCLog(@"UIImagePicker selected image size=%@ url=%@", NSStringFromCGSize(image.size), originalURL);
        [self processSelectedImage:image];
    }];
}

- (void)processSelectedImage:(UIImage *)image {
    if (!image) {
        self.status.text = @"图片解码失败，请重新选择";
        TCLog(@"processSelectedImage received nil image");
        return;
    }

    self.status.text = @"正在处理图片…";
    // Work off the main thread. Normalize UIImage orientation and cap large
    // camera-roll images before PNG encoding to avoid a memory spike on iPad.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            UIImage *normalized = image;
            CGFloat longest = MAX(image.size.width, image.size.height);
            CGFloat factor = longest > 2048.0 ? 2048.0 / longest : 1.0;
            if (factor < 1.0 || image.imageOrientation != UIImageOrientationUp) {
                CGSize target = CGSizeMake(MAX(1.0, floor(image.size.width * factor)),
                                           MAX(1.0, floor(image.size.height * factor)));
                UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
                format.scale = 1.0;
                format.opaque = NO;
                UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
                normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                    [image drawInRect:(CGRect){CGPointZero, target}];
                }];
            }

            NSData *pngData = UIImagePNGRepresentation(normalized);
            if (!pngData.length) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.status.text = @"图片编码失败，请换一张图片";
                    TCLog(@"UIImagePNGRepresentation returned empty data");
                });
                return;
            }

            NSString *supportPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
            NSError *writeError = nil;
            BOOL directoryReady = [[NSFileManager defaultManager] createDirectoryAtPath:supportPath
                                                              withIntermediateDirectories:YES
                                                                               attributes:nil
                                                                                    error:&writeError];
            BOOL isDirectory = NO;
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:supportPath isDirectory:&isDirectory];
            if ((!directoryReady && !exists) || !isDirectory) {
                NSString *message = [NSString stringWithFormat:@"无法创建图片保存目录：%@（%@）", supportPath, writeError.localizedDescription ?: @"未知错误"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.status.text = message;
                    TCLog(@"Create Application Support directory failed path=%@ error=%@", supportPath, writeError);
                });
                return;
            }

            NSURL *savedURL = [NSURL fileURLWithPath:[supportPath stringByAppendingPathComponent:@"TrollCrosshair.png"]];
            if (![pngData writeToURL:savedURL options:NSDataWritingAtomic error:&writeError]) {
                NSString *message = [NSString stringWithFormat:@"图片写入失败：%@", writeError.localizedDescription ?: @"未知错误"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.status.text = message;
                    TCLog(@"Writing selected image failed path=%@ bytes=%lu error=%@", savedURL.path, (unsigned long)pngData.length, writeError);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                RootViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.imageURL = savedURL;
                strongSelf.preview.image = normalized;
                [strongSelf updatePreview];
                // Deliberately do not signal or launch the separate HUD process
                // as part of photo selection. The overlay starts only when the
                // user taps the explicit enable button.
                strongSelf.status.text = @"图片已保存，点击“开启悬浮”启动";
                [strongSelf updateToggleTitle];
                TCLog(@"Selected image saved successfully size=%@ bytes=%lu",
                      NSStringFromCGSize(normalized.size), (unsigned long)pngData.length);
            });
        }
    });
}

- (void)loadSavedOrDefaultImage {
    NSString *supportPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    [[NSFileManager defaultManager] createDirectoryAtPath:supportPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *savedURL = [NSURL fileURLWithPath:[supportPath stringByAppendingPathComponent:@"TrollCrosshair.png"]];
    UIImage *image = [UIImage imageWithContentsOfFile:savedURL.path];

    if (!image) {
        NSString *resourcePath = [NSBundle.mainBundle pathForResource:@"IMG_9324.png" ofType:@"b64"];
        NSString *encoded = resourcePath ? [NSString stringWithContentsOfFile:resourcePath encoding:NSUTF8StringEncoding error:nil] : nil;
        NSData *pngData = encoded ? [[NSData alloc] initWithBase64EncodedString:[encoded stringByReplacingOccurrencesOfString:@"\n" withString:@""] options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
        image = pngData.length ? [UIImage imageWithData:pngData] : nil;
        if (image) {
            NSString *supportPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
            [[NSFileManager defaultManager] createDirectoryAtPath:supportPath withIntermediateDirectories:YES attributes:nil error:nil];
            NSURL *defaultURL = [NSURL fileURLWithPath:[supportPath stringByAppendingPathComponent:@"TrollCrosshair.png"]];
            [pngData writeToURL:defaultURL options:NSDataWritingAtomic error:nil];
            savedURL = defaultURL;
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
