#import <UIKit/UIKit.h>
#import <string.h>
#import "AppDelegate.h"
#import "FloatingController.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "-hud") == 0) {
            return TCHUDMain();
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
