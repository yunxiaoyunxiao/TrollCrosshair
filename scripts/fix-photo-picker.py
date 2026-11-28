#!/usr/bin/env python3
from pathlib import Path
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
start = source.find("    NSItemProvider *provider = results.firstObject.itemProvider;", method_start)
end = source.find("\n}\n- (void)loadSavedImage", start)
if start < 0 or end < 0:
    raise SystemExit("Could not locate photo picker loading block")

replacement = r'''    NSItemProvider *provider = results.firstObject.itemProvider;
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
            self.preview.image = image;
            self.status.text = @"已选择图片并保存到本地";
            [[FloatingController shared] showImageAtURL:url];
        });
    }];'''
if "loadDataRepresentationForTypeIdentifier" not in source[start:end]:
    source = source[:start] + replacement + source[end:]

path.write_text(source)
print("Photo picker data-loading fix applied")
