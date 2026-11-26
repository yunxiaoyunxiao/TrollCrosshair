#import "RootViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
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
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.sliders = [NSMutableArray array];
    [self buildUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shortcutStateChanged) name:@"TrollCrosshairStateChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(overlayReady) name:@"TCFloatingOverlayReadyNotification" object:nil];
    [self loadSavedImage];
    [self syncControls];
}
- (UILabel *)label:(NSString *)text {
    UILabel *l = [UILabel new]; l.text = text; l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; return l;
}
- (void)buildUI {
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    UIStackView *stack = [[UIStackView alloc] init]; self.contentStack = stack; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    UILabel *title = [self label:@"TrollCrosshair Beta 1"]; title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold]; [stack addArrangedSubview:title];
    self.status = [self label:@"尚未选择图片"]; [stack addArrangedSubview:self.status];
    UIButton *pick = [UIButton buttonWithType:UIButtonTypeSystem]; [pick setTitle:@"选择图片" forState:UIControlStateNormal]; [pick addTarget:self action:@selector(pickImage) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:pick];
    self.previewContainer = [UIView new];
    self.previewContainer.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.previewContainer.layer.cornerRadius = 12;
    self.previewContainer.clipsToBounds = YES;
    self.previewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.previewContainer.heightAnchor constraintEqualToConstant:260].active = YES;
    [stack addArrangedSubview:self.previewContainer];

    self.preview = [UIImageView new];
    self.preview.contentMode = UIViewContentModeScaleToFill;
    self.preview.userInteractionEnabled = NO;
    self.preview.frame = CGRectZero;
    [self.previewContainer addSubview:self.preview];
    [self addSlider:@"X（水平，中心点）" min:-600 max:600 value:FISettings.shared.x];
    [self addSlider:@"Y（垂直，中心点）" min:-900 max:900 value:FISettings.shared.y];
    [self addSlider:@"宽度" min:20 max:900 value:FISettings.shared.width];
    [self addSlider:@"高度" min:20 max:1200 value:FISettings.shared.height];
    [self addSlider:@"透明度" min:0.05 max:1 value:FISettings.shared.alpha];
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]; [self.toggleButton addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:self.toggleButton];
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem]; [reset setTitle:@"重置五项参数" forState:UIControlStateNormal]; [reset addTarget:self action:@selector(resetValues) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:reset];
    UILabel *note = [self label:@"Beta 测试版：全局显示与触摸穿透依赖 TrollStore 私有系统接口，请在 iPadOS 17.0 实机验证。图片显示层不接收触摸事件。"]; note.numberOfLines = 0; note.textColor = UIColor.secondaryLabelColor; [stack addArrangedSubview:note];
}
- (void)addSlider:(NSString *)name min:(float)min max:(float)max value:(float)value {
    UILabel *l = [self label:name];
    UIStackView *row = [UIStackView new]; row.axis = UILayoutConstraintAxisVertical; row.spacing = 4;
    [row addArrangedSubview:l];
    UISlider *slider = [UISlider new]; slider.minimumValue = min; slider.maximumValue = max; slider.value = value; [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:slider]; [self.sliders addObject:slider];
    [self.contentStack addArrangedSubview:row];
}
- (void)pickImage {
    PHPickerConfiguration *config = [PHPickerConfiguration new]; config.filter = PHPickerFilter.imagesFilter; config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) {
        self.status.text = @"未选择图片";
        return;
    }
    self.status.text = @"正在读取所选图片…";
    NSString *imageType = nil;
    for (NSString *identifier in provider.registeredTypeIdentifiers) {
        UTType *type = [UTType typeWithIdentifier:identifier];
        if (type && [type conformsToType:UTType.image]) {
            imageType = identifier;
            break;
        }
    }
    if (!imageType) {
        self.status.text = @"无法识别图片格式，请换一张图片";
        return;
    }

    // iOS 17 上部分 PHPicker 项目无法通过 loadObjectOfClass: 解码 public.png；
    // 直接读取提供者声明的图片类型数据，再由 UIImage 解码。
    [provider loadDataRepresentationForTypeIdentifier:imageType completionHandler:^(NSData *imageData, NSError *error) {
        UIImage *image = imageData.length ? [UIImage imageWithData:imageData] : nil;
        if (!image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = [NSString stringWithFormat:@"读取图片失败：%@", error.localizedDescription ?: @"图片数据为空或无法解码"];
            });
            NSLog(@"[TrollCrosshair] PHPicker data load failed, type=%@ error=%@", imageType, error);
            return;
        }
        NSData *data = UIImagePNGRepresentation(image);
        if (data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ self.status.text = @"图片转换失败，请重新选择"; });
            return;
        }
        NSURL *dir = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSError *directoryError = nil;
        if (![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = [NSString stringWithFormat:@"无法创建图片存储目录：%@", directoryError.localizedDescription ?: @"未知错误"];
            });
            return;
        }
        NSURL *url = [dir URLByAppendingPathComponent:@"TrollCrosshair.png"];
        NSError *writeError = nil;
        if (![data writeToURL:url options:NSDataWritingAtomic error:&writeError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = [NSString stringWithFormat:@"保存图片失败：%@", writeError.localizedDescription ?: @"未知错误"];
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageURL = url;
            self.preview.image = image;
            [self updatePreview];
            [[FloatingController shared] showImageAtURL:url];
            [[FloatingController shared] setEnabled:YES];
            self.status.text = [FloatingController shared].isOverlayReady
                ? @"图片已载入，悬浮已开启"
                : @"图片已保存并开启；系统悬浮窗口尚未连接";
            [self updateToggleTitle];
            NSLog(@"[TrollCrosshair] Selected image saved (%lu bytes), type=%@ overlayReady=%d",
                  (unsigned long)data.length, imageType, [FloatingController shared].isOverlayReady);
        });
    }];
}
- (void)loadSavedImage {
    NSURL *dir = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *url = [dir URLByAppendingPathComponent:@"TrollCrosshair.png"];
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    if (image) { self.imageURL = url; self.preview.image = image; self.status.text = @"已载入上次选择的图片"; [[FloatingController shared] showImageAtURL:url]; }
}
- (void)sliderChanged:(UISlider *)slider {
    NSInteger i = [self.sliders indexOfObject:slider]; FISettings *s = FISettings.shared;
    switch (i) { case 0: s.x = slider.value; break; case 1: s.y = slider.value; break; case 2: s.width = slider.value; break; case 3: s.height = slider.value; break; case 4: s.alpha = slider.value; break; }
    [s save]; [self updatePreview]; [[FloatingController shared] refresh];
}
- (void)updatePreview {
    if (!self.preview || !self.previewContainer || !self.preview.image) return;
    FISettings *s = FISettings.shared;
    CGRect bounds = self.previewContainer.bounds;
    if (CGRectIsEmpty(bounds)) return;

    CGFloat maxPreviewSide = MIN(220.0, MIN(bounds.size.width - 24.0, bounds.size.height - 24.0));
    CGFloat largestSide = MAX(s.width, s.height);
    CGFloat scale = largestSide > 0 ? MIN(1.0, maxPreviewSide / largestSide) : 1.0;
    CGFloat width = MAX(1.0, s.width * scale);
    CGFloat height = MAX(1.0, s.height * scale);

    self.preview.bounds = CGRectMake(0, 0, width, height);
    self.preview.center = CGPointMake(CGRectGetMidX(bounds) + s.x * 0.15,
                                      CGRectGetMidY(bounds) + s.y * 0.15);
    self.preview.alpha = MIN(1.0, MAX(0.0, s.alpha));
}
- (void)syncControls {
    FISettings *s = FISettings.shared;
    NSArray *v = @[@(s.x),@(s.y),@(s.width),@(s.height),@(s.alpha)];
    for (NSUInteger i=0; i<MIN(v.count,self.sliders.count); i++) self.sliders[i].value = [v[i] floatValue];
    [self updatePreview]; [self updateToggleTitle];
}
- (void)shortcutStateChanged { [self updateToggleTitle]; [self updatePreview]; }
- (void)overlayReady {
    self.status.text = FISettings.shared.isEnabled ? @"系统悬浮窗口已连接，悬浮已开启" : @"系统悬浮窗口已连接，悬浮当前关闭";
    [self updateToggleTitle];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)updateToggleTitle { [self.toggleButton setTitle:(FISettings.shared.isEnabled ? @"关闭悬浮" : @"开启悬浮") forState:UIControlStateNormal]; }
- (void)toggle {
    if (!self.imageURL && !FISettings.shared.isEnabled) { self.status.text = @"请先选择一张图片"; return; }
    BOOL next = !FISettings.shared.isEnabled;
    [[FloatingController shared] setEnabled:next];
    self.status.text = next ? ([FloatingController shared].isOverlayReady ? @"悬浮已开启" : @"已开启，但系统悬浮窗口尚未连接") : @"悬浮已关闭";
    [self updateToggleTitle];
}
- (void)resetValues {
    [FISettings.shared reset]; [self syncControls]; [[FloatingController shared] refresh];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self updatePreview]; }
@end
