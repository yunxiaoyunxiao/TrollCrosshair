#import "RootViewController.h"
#import <notify.h>
#import "TCLogger.h"
#import "FISettings.h"
#import "FloatingController.h"
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <dlfcn.h>

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


static NSString *TCProbeDirectory(NSString *directory) {
    if (!directory.length) return @"目录路径为空";
    struct stat st = {0};
    int statResult = stat(directory.fileSystemRepresentation, &st);
    int statError = statResult == 0 ? 0 : errno;
    struct statfs fs = {0};
    int statfsResult = statfs(directory.fileSystemRepresentation, &fs);
    int statfsError = statfsResult == 0 ? 0 : errno;
    int accessResult = access(directory.fileSystemRepresentation, W_OK | X_OK);
    int accessError = accessResult == 0 ? 0 : errno;
    int dirFD = open(directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY);
    int dirOpenError = dirFD >= 0 ? 0 : errno;
    if (dirFD >= 0) close(dirFD);

    NSString *probeName = [NSString stringWithFormat:@".tc-write-probe-%d-%u", getpid(), arc4random()];
    NSString *probePath = [directory stringByAppendingPathComponent:probeName];
    int fd = open(probePath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
    int createError = fd >= 0 ? 0 : errno;
    int writeError = 0, syncError = 0, closeError = 0, readOpenError = 0, readError = 0, unlinkError = 0;
    BOOL wrote = NO, readBack = NO;
    if (fd >= 0) {
        const char payload[] = "TCOK";
        ssize_t n = write(fd, payload, sizeof(payload) - 1);
        if (n == (ssize_t)(sizeof(payload) - 1)) wrote = YES;
        else writeError = n < 0 ? errno : EIO;
        if (fsync(fd) != 0) syncError = errno;
        if (close(fd) != 0) closeError = errno;
        int readFD = open(probePath.fileSystemRepresentation, O_RDONLY);
        if (readFD < 0) readOpenError = errno;
        else {
            char buffer[8] = {0};
            ssize_t nread = read(readFD, buffer, sizeof(buffer));
            if (nread == 4 && memcmp(buffer, "TCOK", 4) == 0) readBack = YES;
            else readError = nread < 0 ? errno : EIO;
            close(readFD);
        }
        if (unlink(probePath.fileSystemRepresentation) != 0) unlinkError = errno;
    }
    NSString *statText = statResult == 0
        ? [NSString stringWithFormat:@"uid=%d gid=%d mode=%o", st.st_uid, st.st_gid, st.st_mode]
        : [NSString stringWithFormat:@"errno=%d(%s)", statError, strerror(statError)];
    NSString *fsText = statfsResult == 0
        ? [NSString stringWithFormat:@"flags=0x%lx readOnly=%@", (unsigned long)fs.f_flags, (fs.f_flags & MNT_RDONLY) ? @"YES" : @"NO"]
        : [NSString stringWithFormat:@"errno=%d(%s)", statfsError, strerror(statfsError)];
    return [NSString stringWithFormat:
        @"目录: %@\nstat: %@\nstatfs: %@\naccess(W_OK|X_OK): %@\nopen(directory): %@\nopen(create): %@\nwrite: %@\nfsync: %@\nclose: %@\nopen(read): %@\nread/verify: %@\nunlink: %@",
        directory, statText, fsText,
        accessResult == 0 ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", accessError, strerror(accessError)],
        dirOpenError == 0 ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", dirOpenError, strerror(dirOpenError)],
        fd >= 0 ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", createError, strerror(createError)],
        wrote ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", writeError, strerror(writeError)],
        (fd >= 0 && syncError == 0) ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", syncError, strerror(syncError)],
        (fd >= 0 && closeError == 0) ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", closeError, strerror(closeError)],
        (fd >= 0 && readOpenError == 0) ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", readOpenError, strerror(readOpenError)],
        readBack ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", readError, strerror(readError)],
        (fd >= 0 && unlinkError == 0) ? @"OK" : [NSString stringWithFormat:@"errno=%d(%s)", unlinkError, strerror(unlinkError)]];
}

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
    if (FISettings.shared.isEnabled && self.preview.image) {
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
    // Let the preview image extend beyond the preview card. Later slider rows
    // are explicitly raised above this view so their tracks/thumbs stay usable.
    self.previewContainer.clipsToBounds = NO;
    self.previewContainer.layer.masksToBounds = NO;
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

    UILabel *shortcutTitle = [self label:@"快捷指令"];
    shortcutTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:shortcutTitle];

    UILabel *shortcutHint = [self label:@"在「快捷指令」中新建快捷指令，添加“打开 URL”动作，填入下方地址即可控制悬浮。"];
    shortcutHint.font = [UIFont systemFontOfSize:12];
    shortcutHint.textColor = UIColor.secondaryLabelColor;
    shortcutHint.numberOfLines = 0;
    [stack addArrangedSubview:shortcutHint];

    UIStackView *shortcutActions = [UIStackView new];
    shortcutActions.axis = UILayoutConstraintAxisHorizontal;
    shortcutActions.distribution = UIStackViewDistributionFillEqually;
    shortcutActions.spacing = 8;
    NSArray<NSString *> *shortcutNames = @[@"复制开关", @"复制开启", @"复制关闭"];
    for (NSUInteger i = 0; i < shortcutNames.count; i++) {
        UIButton *shortcut = [UIButton buttonWithType:UIButtonTypeSystem];
        [shortcut setTitle:shortcutNames[i] forState:UIControlStateNormal];
        shortcut.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        shortcut.tag = (NSInteger)i;
        [shortcut addTarget:self action:@selector(copyShortcutURL:) forControlEvents:UIControlEventTouchUpInside];
        [shortcutActions addArrangedSubview:shortcut];
    }
    [stack addArrangedSubview:shortcutActions];

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
    // Keep each parameter slider above the preview image, even when the image
    // visually overflows the preview card and reaches this part of the screen.
    row.layer.zPosition = 100.0;
    slider.layer.zPosition = 101.0;
    [self.contentStack addArrangedSubview:row];
}

- (void)copyShortcutURL:(UIButton *)sender {
    NSArray<NSString *> *urls = @[@"trollcrosshair://toggle", @"trollcrosshair://on", @"trollcrosshair://off"];
    if (sender.tag < 0 || sender.tag >= (NSInteger)urls.count) return;
    UIPasteboard.generalPasteboard.string = urls[(NSUInteger)sender.tag];
    NSArray<NSString *> *names = @[@"开关", @"开启", @"关闭"];
    self.status.text = [NSString stringWithFormat:@"已复制悬浮%@链接；在快捷指令中添加“打开 URL”动作即可。", names[(NSUInteger)sender.tag]];
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

- (void)reportImageSaveFailure:(NSString *)message {
    NSString *home = NSHomeDirectory() ?: @"(nil)";
    NSString *temporary = NSTemporaryDirectory() ?: @"(nil)";
    struct stat homeStat = {0};
    struct stat tempStat = {0};
    int homeStatOK = stat(home.fileSystemRepresentation, &homeStat) == 0;
    int tempStatOK = stat(temporary.fileSystemRepresentation, &tempStat) == 0;
    void *securityHandle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW);
    id (*createTask)(CFAllocatorRef) = securityHandle ? (id (*)(CFAllocatorRef))dlsym(securityHandle, "SecTaskCreateFromSelf") : NULL;
    CFTypeRef (*copyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *) = securityHandle ? (CFTypeRef (*)(CFTypeRef, CFStringRef, CFErrorRef *))dlsym(securityHandle, "SecTaskCopyValueForEntitlement") : NULL;
    id task = createTask ? createTask(kCFAllocatorDefault) : nil;
    NSMutableArray<NSString *> *entitlementLines = [NSMutableArray array];
    NSArray<NSString *> *keys = @[@"com.apple.private.security.no-sandbox", @"platform-application", @"get-task-allow"];
    for (NSString *key in keys) {
        CFTypeRef value = (task && copyEntitlement) ? copyEntitlement((__bridge CFTypeRef)task, (__bridge CFStringRef)key, NULL) : NULL;
        [entitlementLines addObject:[NSString stringWithFormat:@"%@: %@", key, value ? CFBridgingRelease(value) : @"<missing/unavailable>"]];
    }
    void *sandboxHandle = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW);
    int (*sandboxCheck)(pid_t, const char *, int, ...) = sandboxHandle ? (int (*)(pid_t, const char *, int, ...))dlsym(sandboxHandle, "sandbox_check") : NULL;
    int homeCreateCheck = sandboxCheck ? sandboxCheck(0, "file-write-create", 1, home.fileSystemRepresentation) : -999;
    int tempCreateCheck = sandboxCheck ? sandboxCheck(0, "file-write-create", 1, temporary.fileSystemRepresentation) : -999;
    int tempDataCheck = sandboxCheck ? sandboxCheck(0, "file-write-data", 1, temporary.fileSystemRepresentation) : -999;
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"(nil)";
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject ?: @"(nil)";
    NSString *directoryProbes = [@[TCProbeDirectory(temporary), TCProbeDirectory(documents), TCProbeDirectory(caches)] componentsJoinedByString:@"\n\n------------------------------\n\n"];
    NSString *diagnostics = [NSString stringWithFormat:
        @"TrollCrosshair 图片保存失败\n%@\n\n运行环境诊断：\nUID: %d\nEUID: %d\nHOME: %@\nNSTemporaryDirectory: %@\nDocuments: %@\nCaches: %@\nHOME 可写: %@\n临时目录可写: %@\nHOME stat: %@\nHOME owner/mode: %d/%o\ntmp stat: %@\ntmp owner/mode: %d/%o\nsandbox_check file-write-create HOME: %d\nsandbox_check file-write-create tmp: %d\nsandbox_check file-write-data tmp: %d\n\n实际 POSIX 目录写入测试：\n%@\n\n运行时 Entitlements:\n%@\n",
        message ?: @"未知错误",
        getuid(), geteuid(), home, temporary, documents, caches,
        [[NSFileManager defaultManager] isWritableFileAtPath:home] ? @"YES" : @"NO",
        [[NSFileManager defaultManager] isWritableFileAtPath:temporary] ? @"YES" : @"NO",
        homeStatOK ? @"OK" : [NSString stringWithUTF8String:strerror(errno)],
        homeStatOK ? homeStat.st_uid : -1, homeStatOK ? homeStat.st_mode : 0,
        tempStatOK ? @"OK" : [NSString stringWithUTF8String:strerror(errno)],
        tempStatOK ? tempStat.st_uid : -1, tempStatOK ? tempStat.st_mode : 0,
        homeCreateCheck, tempCreateCheck, tempDataCheck, directoryProbes,
        [entitlementLines componentsJoinedByString:@"\n"]];
    UIPasteboard.generalPasteboard.string = diagnostics;
    self.status.text = @"保存失败，完整错误信息已复制到剪切板";
    TCLog(@"%@", diagnostics);
}

- (void)processSelectedImage:(UIImage *)image {
    if (!image) {
        self.status.text = @"图片解码失败，请重新选择";
        TCLog(@"processSelectedImage received nil image");
        return;
    }

    self.status.text = @"正在处理图片…";
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
                    [weakSelf reportImageSaveFailure:@"图片编码失败：UIImagePNGRepresentation 返回空数据"];
                });
                return;
            }

            // The device currently denies direct POSIX access to all three app
            // container directories despite sandbox_check reporting allow.
            // Store the image through cfprefsd/NSUserDefaults instead of open().
            CFStringRef appID = CFSTR("com.trollcrosshair.app");
            CFPreferencesSetAppValue(CFSTR("fi.overlayImageData"), (__bridge CFPropertyListRef)pngData, appID);
            BOOL synchronized = CFPreferencesAppSynchronize(appID);
            CFPropertyListRef copiedValue = CFPreferencesCopyAppValue(CFSTR("fi.overlayImageData"), appID);
            NSData *readBack = copiedValue ? CFBridgingRelease(copiedValue) : nil;
            BOOL verified = [readBack isKindOfClass:NSData.class] && readBack.length == pngData.length && [readBack isEqualToData:pngData];
            [NSUserDefaults.standardUserDefaults setObject:pngData forKey:@"fi.overlayImageData"];
            [NSUserDefaults.standardUserDefaults synchronize];
            if (!verified) {
                NSString *message = [NSString stringWithFormat:
                    @"图片数据保存失败：NSUserDefaults 回读校验未通过；原始数据=%lu bytes；回读数据=%lu bytes；synchronize=%@",
                    (unsigned long)pngData.length, (unsigned long)readBack.length,
                    synchronized ? @"YES" : @"NO"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf reportImageSaveFailure:message];
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                RootViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.imageURL = nil;
                strongSelf.preview.image = normalized;
                [strongSelf updatePreview];
                [[FloatingController shared] refresh];
                strongSelf.status.text = @"图片已保存，点击“开启悬浮”启动";
                [strongSelf updateToggleTitle];
                TCLog(@"Selected image stored in preferences size=%@ bytes=%lu",
                      NSStringFromCGSize(normalized.size), (unsigned long)pngData.length);
            });
        }
    });
}

- (void)loadSavedOrDefaultImage {
    CFPropertyListRef copiedValue = CFPreferencesCopyAppValue(CFSTR("fi.overlayImageData"), CFSTR("com.trollcrosshair.app"));
    NSData *savedData = copiedValue ? CFBridgingRelease(copiedValue) : nil;
    if (![savedData isKindOfClass:NSData.class] || savedData.length == 0) savedData = [NSUserDefaults.standardUserDefaults dataForKey:@"fi.overlayImageData"];
    UIImage *image = savedData.length ? [UIImage imageWithData:savedData] : nil;

    if (image) {
        TCLog(@"Restored selected image from preferences (%lu bytes)", (unsigned long)savedData.length);
    } else {
        NSString *resourcePath = [NSBundle.mainBundle pathForResource:@"IMG_9324.png" ofType:@"b64"];
        NSString *encoded = resourcePath ? [NSString stringWithContentsOfFile:resourcePath encoding:NSUTF8StringEncoding error:nil] : nil;
        NSData *pngData = encoded ? [[NSData alloc] initWithBase64EncodedString:[encoded stringByReplacingOccurrencesOfString:@"\n" withString:@""] options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
        image = pngData.length ? [UIImage imageWithData:pngData] : nil;
        if (image && pngData.length) {
            [NSUserDefaults.standardUserDefaults setObject:pngData forKey:@"fi.overlayImageData"];
            [NSUserDefaults.standardUserDefaults synchronize];
            TCLog(@"Loaded bundled default image into preferences");
        } else {
            TCLog(@"Bundled default image could not be loaded");
        }
    }

    if (image) {
        self.imageURL = nil;
        self.preview.image = image;
        [[FloatingController shared] refresh];
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
    self.preview.hidden = NO;
    self.preview.contentMode = UIViewContentModeScaleAspectFit;
    self.preview.bounds = CGRectMake(0, 0, width, height);
    CGFloat offsetX = settings.x * bounds.size.width / MAX(1.0, UIScreen.mainScreen.bounds.size.width);
    CGFloat offsetY = settings.y * bounds.size.height / MAX(1.0, UIScreen.mainScreen.bounds.size.height);
    self.preview.center = CGPointMake(CGRectGetMidX(bounds) + offsetX,
                                      CGRectGetMidY(bounds) + offsetY);
    self.preview.alpha = MIN(1.0, MAX(0.0, settings.alpha));
    // The image is the second layer: it can overflow the preview card,
    // while the parameter slider rows (zPosition 100) remain above it.
    self.preview.layer.zPosition = 1.0;
    [self.previewContainer bringSubviewToFront:self.preview];
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
    // imageURL is no longer used: selected image bytes are persisted in
    // NSUserDefaults under fi.overlayImageData. Checking imageURL here made
    // every freshly saved image look "missing", so tapping Enable reopened
    // the photo picker instead of starting the HUD.
    NSData *savedImageData = [NSUserDefaults.standardUserDefaults dataForKey:@"fi.overlayImageData"];
    UIImage *savedImage = savedImageData.length ? [UIImage imageWithData:savedImageData] : nil;
    if (!savedImage && !FISettings.shared.isEnabled) {
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
