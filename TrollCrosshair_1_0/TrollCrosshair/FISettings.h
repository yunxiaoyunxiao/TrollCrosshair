#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface FISettings : NSObject
@property(nonatomic) CGFloat x;
@property(nonatomic) CGFloat y;
@property(nonatomic) CGFloat width;
@property(nonatomic) CGFloat height;
@property(nonatomic) CGFloat alpha;
@property(nonatomic, getter=isEnabled) BOOL enabled;
+ (instancetype)shared;
- (void)save;
- (void)reset;
@end
NS_ASSUME_NONNULL_END
