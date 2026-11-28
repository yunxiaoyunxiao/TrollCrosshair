#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fix-photo-picker.py path/to/RootViewController.mm")

path = Path(sys.argv[1])
source = path.read_text()

import_line = "#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>"
if import_line not in source:
    photos_import = "#import <PhotosUI/PhotosUI.h>"
    if photos_import not in source:
        raise SystemExit("PhotosUI import not found")
    source = source.replace(photos_import, photos_import + "\n" + import_line, 1)

method_start = source.find("- (void)picker:")
if method_start < 0:
    raise SystemExit("PHPicker delegate method not found")
open_brace = source.find("{", method_start)
if open_brace < 0:
    raise SystemExit("PHPicker delegate method body not found")

depth = 0
method_end = -1
for index in range(open_brace, len(source)):
    if source[index] == "{":
        depth += 1
    elif source[index] == "}":
        depth -= 1
        if depth == 0:
            method_end = index + 1
            break
if method_end < 0:
    raise SystemExit("Could not find end of PHPicker delegate method")

preview_match = re.search(r'@property\s*\([^)]*\)\s*UIImageView\s*\*\s*(\w+)', source)
preview_property = preview_match.group(1) if preview_match else None

replacement = r'''- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) {
        self.status.text = @"未能从照片选择器获取图片";
        return;
    }

    NSString *imageType = UTTypeImage.identifier;
    if (![provider hasItemConformingToTypeIdentifier:imageType]) {
        self.status.text = @"所选项目不是受支持的图片";
        return;
    }

    [provider loadDataRepresentationForTypeIdentifier:imageType completionHandler:^(NSData *data, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (!image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = error.localizedDescription ?: @"读取所选图片失败";
            });
            return;
        }

        NSData *pngData = UIImagePNGRepresentation(image);
        if (!pngData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = @"无法将图片转换为 PNG";
            });
            return;
        }

        NSURL *dir = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSError *directoryError = nil;
        [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&directoryError];
        if (directoryError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = directoryError.localizedDescription;
            });
            return;
        }

        NSURL *url = [dir URLByAppendingPathComponent:@"FloatImage.png"];
        NSError *writeError = nil;
        if (![pngData writeToURL:url options:NSDataWritingAtomic error:&writeError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = writeError.localizedDescription ?: @"保存图片失败";
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageURL = url;
            self.status.text = @"已选择图片并保存到本地";
            [[FloatingController shared] showImageAtURL:url];
        });
    }];
}'''
if preview_property:
    replacement = replacement.replace(
        '            self.status.text = @"已选择图片并保存到本地";',
        f'            self.{preview_property}.image = image;\n            self.status.text = @"已选择图片并保存到本地";',
        1
    )

source = source[:method_start] + replacement + source[method_end:]
path.write_text(source)
print("Photo picker data-loading fix applied")
