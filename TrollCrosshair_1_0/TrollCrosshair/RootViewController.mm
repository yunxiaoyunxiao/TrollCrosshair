#import "RootViewController.h"
#import <PhotosUI/PhotosUI.h>
#import "FISettings.h"
#import "FloatingController.h"

@interface RootViewController () <PHPickerViewControllerDelegate>
@property(nonatomic,strong) UIView *previewContainer;
@property(nonatomic,strong) UIImageView *preview;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *toggleButton;
@property(nonatomic,strong) NSURL *imageURL;
@property(nonatomic,strong) NSMutableArray<UISlider *> *sliders;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.sliders = [NSMutableArray array];
    [self buildUI];
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
    UIStackView *stack = [[UIStackView alloc] init]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    UILabel *title = [self label:@"TrollCrosshair 1.0"]; title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold]; [stack addArrangedSubview:title];
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
    UILabel *note = [self label:@"开发说明：当前悬浮层仅为前台场景内的高层级窗口实验，不代表已实现跨 App 常驻或系统级触摸穿透。需要在 iPadOS 17.0 + TrollStore 实机验证。"]; note.numberOfLines = 0; note.textColor = UIColor.secondaryLabelColor; [stack addArrangedSubview:note];
}
- (void)addSlider:(NSString *)name min:(float)min max:(float)max value:(float)value {
    UILabel *l = [self label:name]; [self.view addSubview:l]; // label is placed in a compact vertical row below
    [l removeFromSuperview];
    UIStackView *row = [UIStackView new]; row.axis = UILayoutConstraintAxisVertical; row.spacing = 4;
    [row addArrangedSubview:l];
    UISlider *slider = [UISlider new]; slider.minimumValue = min; slider.maximumValue = max; slider.value = value; [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:slider]; [self.sliders addObject:slider];
    // Insert into the main stack (the scroll view's vertical stack).
    UIScrollView *scroll = (UIScrollView *)self.view.subviews.firstObject;
    UIStackView *stack = (UIStackView *)scroll.subviews.firstObject;
    [stack addArrangedSubview:row];
}
- (void)pickImage {
    PHPickerConfiguration *config = [PHPickerConfiguration new]; config.filter = PHPickerFilter.imagesFilter; config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) return;
    [provider loadObjectOfClass:UIImage.class completionHandler:^(UIImage *image, NSError *error) {
        if (!image || error) return;
        NSData *data = UIImagePNGRepresentation(image); NSURL *dir = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *url = [dir URLByAppendingPathComponent:@"TrollCrosshair.png"];
        if ([data writeToURL:url atomically:YES]) dispatch_async(dispatch_get_main_queue(), ^{
            self.imageURL = url; self.preview.image = image; self.status.text = @"已选择图片并保存到本地";
            [[FloatingController shared] showImageAtURL:url];
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
- (void)updateToggleTitle { [self.toggleButton setTitle:(FISettings.shared.isEnabled ? @"关闭悬浮" : @"开启悬浮") forState:UIControlStateNormal]; }
- (void)toggle {
    if (!self.imageURL && !FISettings.shared.isEnabled) { self.status.text = @"请先选择一张图片"; return; }
    [[FloatingController shared] setEnabled:!FISettings.shared.isEnabled]; [self updateToggleTitle];
}
- (void)resetValues {
    [FISettings.shared reset]; [self syncControls]; [[FloatingController shared] refresh];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self updatePreview]; }
@end
