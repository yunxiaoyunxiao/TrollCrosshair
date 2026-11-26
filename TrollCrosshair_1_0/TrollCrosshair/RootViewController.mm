#import "RootViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <notify.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
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
    // PHPicker is a system-mediated picker. Do not touch PHPhotoLibrary or PHAsset:
    // the picker already grants this app access to the selected representation.
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;

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

    NSMutableArray<NSString *> *imageTypes = [NSMutableArray array];
    UTType *genericImageType = [UTType typeWithIdentifier:@"public.image"];
    for (NSString *identifier in provider.registeredTypeIdentifiers) {
        UTType *type = [UTType typeWithIdentifier:identifier];
        if (type && genericImageType && [type conformsToType:genericImageType]) {
            [imageTypes addObject:identifier];
        }
    }

    // Prefer common lossless/standard representations, then try every remaining
    // image representation actually advertised by this provider.
    NSArray<NSString *> *priority = @[@"public.png", @"public.jpeg", @"public.heic", @"public.image"];
    [imageTypes sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ai = [priority indexOfObject:a];
        NSUInteger bi = [priority indexOfObject:b];
        if (ai == NSNotFound) ai = NSUIntegerMax;
        if (bi == NSNotFound) bi = NSUIntegerMax;
        return ai < bi ? NSOrderedAscending : (ai > bi ? NSOrderedDescending : NSOrderedSame);
    }];

    TCLog(@"Picker image representations: %@", imageTypes);
    self.status.text = @"正在读取图片…";
    if (imageTypes.count == 0) {
        self.status.text = @"系统没有提供可读取的图片格式";
        TCLog(@"Picker provider advertised no image representations");
        return;
    }
    [self loadImageFromProvider:provider types:imageTypes index:0];
}

- (void)loadImageFromProvider:(NSItemProvider *)provider types:(NSArray<NSString *> *)types index:(NSUInteger)index {
    if (index >= types.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.status.text = @"图片读取失败：系统提供的图片文件无法解码，请尝试重新选择";
        });
        TCLog(@"All advertised image representations failed");
        return;
    }

    NSString *typeIdentifier = types[index];
    TCLog(@"Requesting picker file representation: %@", typeIdentifier);
    __weak typeof(self) weakSelf = self;
    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier completionHandler:^(NSURL *fileURL, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        UIImage *image = nil;
        if (fileURL) {
            // The URL is temporary and is deleted as soon as this completion
            // handler returns. Decode it here, before leaving the callback.
            NSDictionary *options = @{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @2048
            };
            CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
            if (source) {
                CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
                if (thumbnail) {
                    image = [UIImage imageWithCGImage:thumbnail];
                    CGImageRelease(thumbnail);
                }
                CFRelease(source);
            }
        }

        if (image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                TCLog(@"Picker image decoded successfully from %@", typeIdentifier);
                [self processSelectedImage:image];
            });
            return;
        }

        TCLog(@"Picker representation failed type=%@ error=%@", typeIdentifier, error);
        [self loadImageFromProvider:provider types:types index:index + 1];
    }];
}

- (void)processSelectedImage:(UIImage *)image {
    if (!image) {
        self.status.text = @"图片解码失败，请重新选择";
        TCLog(@"processSelectedImage received nil image");
        return;
    }

    // The ImageIO picker path has already applied orientation and capped the
    // longest edge at 2048 px. Avoid a second UIGraphicsImageRenderer pass:
    // it is unnecessary and can trigger UIKit rendering failures for some
    // provider-backed images on older iOS releases.
    @try {
        NSData *pngData = UIImagePNGRepresentation(image);
        if (!pngData.length) {
            self.status.text = @"图片编码失败，请换一张图片";
            TCLog(@"UIImagePNGRepresentation returned empty data size=%@", NSStringFromCGSize(image.size));
            return;
        }

        NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                                  inDomains:NSUserDomainMask].firstObject;
        NSError *writeError = nil;
        if (![NSFileManager.defaultManager createDirectoryAtURL:directory
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:&writeError]) {
            self.status.text = @"无法保存图片";
            TCLog(@"Create Application Support directory failed: %@", writeError);
            return;
        }

        NSURL *savedURL = [directory URLByAppendingPathComponent:@"TrollCrosshair.png"];
        if (![pngData writeToURL:savedURL options:NSDataWritingAtomic error:&writeError]) {
            self.status.text = @"图片保存失败";
            TCLog(@"Writing selected image failed: %@", writeError);
            return;
        }

        self.imageURL = savedURL;
        self.preview.image = image;
        [self updatePreview];
        [[FloatingController shared] showImageAtURL:savedURL];
        self.status.text = @"图片已保存，点击“开启悬浮”启动";
        [self updateToggleTitle];
        TCLog(@"Selected image saved successfully size=%@ bytes=%lu",
              NSStringFromCGSize(image.size), (unsigned long)pngData.length);
    } @catch (NSException *exception) {
        self.status.text = @"处理图片时发生异常，请重新选择";
        TCLog(@"Image processing exception: %@ %@", exception.name, exception.reason);
    }
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
