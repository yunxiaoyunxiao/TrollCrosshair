#import <Foundation/Foundation.h>

static inline NSURL *TCLogFileURL(void) {
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory URLByAppendingPathComponent:@"TrollCrosshair-Diagnostics.log"];
}

static inline void TCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [[NSISO8601DateFormatter new] stringFromDate:NSDate.date], message];
    NSLog(@"%@", message);
    @synchronized (TCLogFileURL().path) {
        NSURL *url = TCLogFileURL();
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            [data writeToURL:url options:NSDataWritingAtomic error:nil];
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:url.path];
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle closeFile];
        }
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
        if ([attributes[NSFileSize] unsignedLongLongValue] > 1024 * 1024) {
            [data writeToURL:url options:NSDataWritingAtomic error:nil];
        }
    }
}
