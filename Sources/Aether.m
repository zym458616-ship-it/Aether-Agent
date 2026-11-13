//
//  Aether.m
//  Entry point. A plain Mach-O dylib constructor — no substrate required,
//  so it works whether it is injected into an IPA or loaded by a jailbreak.
//

#import "Aether.h"
#import "AAUI.h"

@interface AetherKernel : NSObject
@end

static BOOL gBooted = NO;

@implementation AetherKernel

+ (void)load_injected {
    @autoreleasepool {
        NSBundle *b = [NSBundle mainBundle];
        AALog(@"Aether %@ (%@) loaded into %@ [pid %d uid %d]",
              AETHER_VERSION, AETHER_BUILD,
              b.bundleIdentifier ?: @"?",
              getpid(), getuid());
        AALog(@"jailbreak root: %@  shell: %@",
              [AAExecutor jbPrefix].length ? [AAExecutor jbPrefix] : @"none",
              [AAExecutor shellPath]);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self waitForUI:0];
    });

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                     object:nil queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *n) {
        [self waitForUI:0];
    }];
}

+ (void)waitForUI:(NSInteger)attempt {
    if (gBooted) return;
    UIApplication *app = [UIApplication sharedApplication];
    BOOL ready = app != nil && (app.windows.count > 0 || [self hasSceneWindows]);
    if (ready || attempt > 120) {
        gBooted = YES;
        [AAOverlay boot];
        AALog(@"overlay booted after %ld ticks", (long)attempt);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self waitForUI:attempt + 1];
    });
}

+ (BOOL)hasSceneWindows {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (((UIWindowScene *)s).windows.count) return YES;
        }
    }
    return NO;
}

@end

__attribute__((constructor))
static void AetherConstructor(void) {
    [AetherKernel load_injected];
}
