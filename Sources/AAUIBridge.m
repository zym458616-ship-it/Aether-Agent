//
//  AAUIBridge.m
//  Reads the live view hierarchy, injects touches and captures the screen.
//
//  Touch injection strategy:
//    1) IOHIDEvent digitizer injection (real hardware-level events).
//    2) Semantic fallback: hit-test the view, drive UIControl actions or
//       gesture recognizers directly. Used when the HID client is unavailable
//       in un-entitled app processes.
//

#import "Aether.h"
#import <objc/runtime.h>
#import <mach/mach_time.h>
#import <dlfcn.h>

#pragma mark - HID private API (resolved with dlsym, never linked)

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

typedef IOHIDEventRef (*AAHIDFingerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                       double, double, double, double, double, double, double, double, uint32_t);
typedef IOHIDEventSystemClientRef (*AAHIDCreateFn)(CFAllocatorRef);
typedef void (*AAHIDDispatchFn)(IOHIDEventSystemClientRef, IOHIDEventRef);

static AAHIDFingerFn    gFinger = NULL;
static AAHIDCreateFn    gClientCreate = NULL;
static AAHIDDispatchFn  gDispatch = NULL;
static IOHIDEventSystemClientRef gClient = NULL;
static BOOL gHIDResolved = NO;
static BOOL gHIDBroken = NO;

static void AAResolveHID(void) {
    if (gHIDResolved) return;
    gHIDResolved = YES;
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h) h = RTLD_DEFAULT;
    gFinger = (AAHIDFingerFn)dlsym(h, "IOHIDEventCreateDigitizerFingerEventWithQuality");
    gClientCreate = (AAHIDCreateFn)dlsym(h, "IOHIDEventSystemClientCreate");
    gDispatch = (AAHIDDispatchFn)dlsym(h, "IOHIDEventSystemClientDispatchEvent");
    if (!gClientCreate) {
        typedef IOHIDEventSystemClientRef (*FnT)(CFAllocatorRef, int, CFDictionaryRef);
        FnT f = (FnT)dlsym(h, "IOHIDEventSystemClientCreateWithType");
        if (f) gClient = f(kCFAllocatorDefault, 1, NULL);
    }
    if (!gFinger || !gDispatch) gHIDBroken = YES;
    AALog(@"hid resolved: finger=%p dispatch=%p create=%p", (void *)gFinger, (void *)gDispatch, (void *)gClientCreate);
}

// eventMask bits: range 0x01, touch 0x02, position 0x04
static BOOL AAHIDEvent(CGPoint pt, uint32_t mask, double pressure) {
    AAResolveHID();
    if (gHIDBroken || !gFinger || !gDispatch) return NO;
    if (!gClient && gClientCreate) gClient = gClientCreate(kCFAllocatorDefault);
    if (!gClient) return NO;
    IOHIDEventRef ev = gFinger(kCFAllocatorDefault, mach_absolute_time(), 1, 2, mask,
                               pt.x, pt.y, 0, pressure, 0, 1.0, 1.0, 1.0, 0);
    if (!ev) return NO;
    gDispatch(gClient, ev);
    CFRelease(ev);
    return YES;
}

#pragma mark - Element

@implementation AAElement

- (NSString *)description {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"<%@", self.cls];
    if (self.text.length) [s appendFormat:@" text=\"%@\"", self.text];
    if (self.label.length) [s appendFormat:@" label=\"%@\"", self.label];
    if (self.identifier.length) [s appendFormat:@" id=\"%@\"", self.identifier];
    [s appendFormat:@" @%.0f,%.0f %.0fx%.0f", self.frame.origin.x, self.frame.origin.y,
        self.frame.size.width, self.frame.size.height];
    if (self.image.length) [s appendFormat:@" img=%@", self.image];
    [s appendString:@">"];
    return s;
}

@end

#pragma mark - Bridge

@interface AAUIBridge ()
@property (nonatomic, strong) NSMapTable *weakMap;
@property (nonatomic, strong) NSMutableArray *lastDump;
@end

@implementation AAUIBridge

+ (instancetype)shared {
    static AAUIBridge *b = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        b = [[AAUIBridge alloc] init];
        b.weakMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                                          valueOptions:NSPointerFunctionsWeakMemory];
        b.lastDump = [NSMutableArray array];
    });
    return b;
}

#pragma mark windows

- (NSArray<UIWindow *> *)appWindows {
    NSMutableArray *out = [NSMutableArray array];
    UIWindow *mine = [AAOverlay shared].window;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w == mine) continue;
                if (w.windowLevel >= UIWindowLevelAlert - 1 && w != [UIApplication sharedApplication].keyWindow) {
                    // still include; games often use alert-level windows
                }
                [out addObject:w];
            }
        }
    }
    if (!out.count) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w != mine) [out addObject:w];
        }
    }
    return out;
}

- (UIView *)hitViewAt:(CGPoint)pt {
    NSArray *wins = [self appWindows];
    for (UIWindow *w in [wins reverseObjectEnumerator]) {
        if (w.isHidden || w.alpha < 0.01) continue;
        CGPoint local = [w convertPoint:pt fromWindow:nil];
        UIView *hit = [w hitTest:local withEvent:nil];
        if (hit) return hit;
    }
    return nil;
}

static NSString *AATextOf(UIView *v) {
    NSString *t = nil;
    @try {
        if ([v isKindOfClass:[UILabel class]]) t = ((UILabel *)v).text;
        else if ([v isKindOfClass:[UITextField class]]) t = ((UITextField *)v).text ?: ((UITextField *)v).placeholder;
        else if ([v isKindOfClass:[UITextView class]]) t = ((UITextView *)v).text;
        else if ([v isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)v;
            t = [b titleForState:UIControlStateNormal] ?: [b titleForState:UIControlStateSelected] ?: b.titleLabel.text;
        }
        if (!t.length) {
            NSString *al = v.accessibilityLabel;
            if (al.length) t = al;
        }
        if (!t.length) {
            NSString *al = v.accessibilityValue;
            if ([al isKindOfClass:[NSString class]] && al.length) t = al;
        }
    } @catch (NSException *e) {}
    return t;
}

- (void)walk:(UIView *)v depth:(NSInteger)depth window:(NSInteger)wi out:(NSMutableArray *)out {
    if (!v || out.count > 600) return;
    if (v.isHidden || v.alpha < 0.02) return;
    CGRect frame = [v convertRect:v.bounds toView:nil];
    if (frame.size.width < 1 || frame.size.height < 1) {
        // zero-size containers can still hold visible children
    }
    NSString *text = AATextOf(v);
    NSString *ident = v.accessibilityIdentifier;
    BOOL isControl = [v isKindOfClass:[UIControl class]];
    BOOL isTextish = [v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UITextView class]] ||
                     [v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UIImageView class]];
    BOOL meaningful = (text.length > 0) || (ident.length > 0) || isControl ||
                      [v isKindOfClass:[UITableViewCell class]] || [v isKindOfClass:[UICollectionViewCell class]];

    if (meaningful && frame.size.width >= 2 && frame.size.height >= 2) {
        AAElement *e = [[AAElement alloc] init];
        e.index = out.count;
        e.cls = NSStringFromClass([v class]);
        e.text = text.length > 120 ? [text substringToIndex:120] : text;
        e.label = v.accessibilityLabel.length > 80 ? [v.accessibilityLabel substringToIndex:80] : v.accessibilityLabel;
        e.identifier = ident;
        if ([v isKindOfClass:[UIImageView class]]) {
            e.image = v.accessibilityLabel.length ? v.accessibilityLabel : @"";
        }
        e.frame = frame;
        e.depth = depth;
        e.tappable = isControl || v.gestureRecognizers.count > 0 || v.userInteractionEnabled;
        e.enabled = v.userInteractionEnabled && !v.isHidden;
        e.eid = [NSString stringWithFormat:@"w%lde%ld", (long)wi, (long)e.index];
        [out addObject:e];
        [self.weakMap setObject:v forKey:e.eid];
    }

    for (UIView *sub in v.subviews) {
        [self walk:sub depth:depth + 1 window:wi out:out];
    }
}

- (NSArray<AAElement *> *)dumpHierarchy {
    [self.weakMap removeAllObjects];
    NSMutableArray *out = [NSMutableArray array];
    NSArray *wins = [self appWindows];
    NSInteger wi = 0;
    for (UIWindow *w in wins) {
        if (w.isHidden || w.alpha < 0.01) { wi++; continue; }
        [self walk:w depth:0 window:wi out:out];
        wi++;
    }
    self.lastDump = out;
    return out;
}

- (NSString *)hierarchyDescription {
    NSArray *els = [self dumpHierarchy];
    NSMutableString *s = [NSMutableString string];
    UIScreen *scr = [UIScreen mainScreen];
    [s appendFormat:@"screen %.0fx%.0f\n", scr.bounds.size.width, scr.bounds.size.height];
    for (AAElement *e in els) {
        [s appendString:@"  "];
        for (NSInteger i = 0; i < MIN(e.depth, 8); i++) [s appendString:@"  "];
        [s appendFormat:@"[%@] %@", e.eid, e.description];
        [s appendString:@"\n"];
    }
    if (!els.count) [s appendString:@"(未找到可交互元素)\n"];
    return s;
}

- (NSArray<AAElement *> *)find:(NSString *)query {
    if (!query.length) return self.lastDump.count ? self.lastDump : [self dumpHierarchy];
    NSArray *els = self.lastDump.count ? self.lastDump : [self dumpHierarchy];
    NSString *q = query.lowercaseString;
    NSMutableArray *hits = [NSMutableArray array];
    for (AAElement *e in els) {
        NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@", e.cls, e.text ?: @"", e.label ?: @"", e.identifier ?: @""].lowercaseString;
        if ([hay containsString:q]) [hits addObject:e];
    }
    return hits;
}

#pragma mark touch

- (BOOL)tapPoint:(CGPoint)pt {
    // 1) HID injection — press, hold 40 ms, release.
    BOOL hid = NO;
    if (AAHIDEvent(pt, 0x03, 1.0)) {
        usleep(40000);
        AAHIDEvent(pt, 0x00, 0.0);
        hid = YES;
    }
    // 2) Always also run the semantic path when HID is unavailable.
    if (!hid) return [self semanticTap:pt];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Nothing to do; kept for symmetry / future verification.
    });
    return YES;
}

- (BOOL)semanticTap:(CGPoint)pt {
    __block BOOL ok = NO;
    void (^work)(void) = ^{
        UIView *hit = [self hitViewAt:pt];
        if (!hit) return;
        UIView *v = hit;
        for (NSInteger depth = 0; v && depth < 10; depth++, v = v.superview) {
            if ([v isKindOfClass:[UIControl class]]) {
                UIControl *c = (UIControl *)v;
                if (!c.enabled) continue;
                [c sendActionsForControlEvents:UIControlEventTouchDown];
                [c sendActionsForControlEvents:UIControlEventTouchUpInside];
                [c sendActionsForControlEvents:UIControlEventTouchUpOutside];
                ok = YES;
                break;
            }
            for (UIGestureRecognizer *g in v.gestureRecognizers) {
                BOOL isTap = [g isKindOfClass:[UITapGestureRecognizer class]];
                BOOL isPress = [g isKindOfClass:[UILongPressGestureRecognizer class]];
                if (!isTap && !isPress) continue;
                if (!g.enabled) continue;
                @try {
                    [g setState:UIGestureRecognizerStateBegan];
                    [g setState:UIGestureRecognizerStateEnded];
                    ok = YES;
                } @catch (NSException *e) {}
                if (ok) break;
            }
            if (ok) break;
        }
        if (!ok) {
            // Table / collection row selection by indexPath.
            UIView *row = hit;
            while (row && ![row isKindOfClass:[UITableViewCell class]] && ![row isKindOfClass:[UICollectionViewCell class]])
                row = row.superview;
            if (row) {
                UIView *pv = row.superview;
                while (pv && ![pv isKindOfClass:[UITableView class]] && ![pv isKindOfClass:[UICollectionView class]])
                    pv = pv.superview;
                if ([pv isKindOfClass:[UITableView class]]) {
                    NSIndexPath *ip = [(UITableView *)pv indexPathForCell:(UITableViewCell *)row];
                    id<UITableViewDelegate> d = ((UITableView *)pv).delegate;
                    if (ip && [d respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                        [d tableView:(UITableView *)pv didSelectRowAtIndexPath:ip];
                        ok = YES;
                    }
                } else if ([pv isKindOfClass:[UICollectionView class]]) {
                    NSIndexPath *ip = [(UICollectionView *)pv indexPathForCell:(UICollectionViewCell *)row];
                    id<UICollectionViewDelegate> d = ((UICollectionView *)pv).delegate;
                    if (ip && [d respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                        [d collectionView:(UICollectionView *)pv didSelectItemAtIndexPath:ip];
                        ok = YES;
                    }
                }
            }
        }
        if (!ok && [hit canBecomeFirstResponder]) {
            [hit becomeFirstResponder];
            ok = YES;
        }
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return ok;
}

- (BOOL)tapElement:(NSString *)eid {
    UIView *v = [self.weakMap objectForKey:eid];
    if (!v) {
        // Try a fresh dump (hierarchy may have changed).
        [self dumpHierarchy];
        v = [self.weakMap objectForKey:eid];
    }
    if (!v) return NO;
    CGRect r = [v convertRect:v.bounds toView:nil];
    CGPoint p = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    if (AAHIDEvent(p, 0x03, 1.0)) {
        usleep(40000);
        AAHIDEvent(p, 0x00, 0.0);
        return YES;
    }
    return [self semanticTap:p];
}

- (BOOL)swipeFrom:(CGPoint)a to:(CGPoint)b duration:(double)duration {
    if (!AAHIDEvent(a, 0x03, 1.0)) {
        // Semantic scroll fallback.
        CGFloat dy = a.y - b.y;
        return [self scrollBy:dy];
    }
    double d = duration > 0.05 ? duration : 0.35;
    int steps = MAX(6, (int)(d / 0.016));
    for (int i = 1; i <= steps; i++) {
        double t = (double)i / steps;
        CGPoint p = CGPointMake(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
        AAHIDEvent(p, 0x07, 1.0);
        usleep((useconds_t)(d / steps * 1000000));
    }
    AAHIDEvent(b, 0x00, 0.0);
    return YES;
}

- (BOOL)longPress:(CGPoint)pt duration:(double)duration {
    double d = duration > 0.1 ? duration : 0.7;
    if (!AAHIDEvent(pt, 0x03, 1.0)) {
        return [self semanticTap:pt];
    }
    int steps = (int)(d / 0.05);
    for (int i = 0; i < steps; i++) {
        usleep(50000);
        AAHIDEvent(pt, 0x07, 1.0);
    }
    AAHIDEvent(pt, 0x00, 0.0);
    return YES;
}

- (BOOL)scrollBy:(CGFloat)dy {
    __block BOOL ok = NO;
    void (^work)(void) = ^{
        CGPoint center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2,
                                     [UIScreen mainScreen].bounds.size.height / 2);
        UIView *hit = [self hitViewAt:center];
        UIView *v = hit;
        while (v && ![v isKindOfClass:[UIScrollView class]]) v = v.superview;
        if ([v isKindOfClass:[UIScrollView class]]) {
            UIScrollView *sv = (UIScrollView *)v;
            CGPoint o = sv.contentOffset;
            CGFloat maxY = MAX(0, sv.contentSize.height - sv.bounds.size.height + sv.contentInset.bottom);
            o.y = MAX(-sv.contentInset.top, MIN(maxY, o.y + dy));
            [sv setContentOffset:o animated:YES];
            ok = YES;
        }
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return ok;
}

#pragma mark text input

static UIView *AAFirstResponder(UIView *v) {
    if (!v) return nil;
    if (v.isFirstResponder) return v;
    for (UIView *s in v.subviews) {
        UIView *r = AAFirstResponder(s);
        if (r) return r;
    }
    return nil;
}

- (BOOL)inputText:(NSString *)text {
    if (!text.length) return NO;
    __block BOOL ok = NO;
    void (^work)(void) = ^{
        UIView *fr = nil;
        for (UIWindow *w in [self appWindows]) {
            fr = AAFirstResponder(w);
            if (fr) break;
        }
        if (!fr) {
            // Pick the first editable view on screen.
            NSArray *els = [self dumpHierarchy];
            for (AAElement *e in els) {
                if ([e.cls isEqualToString:@"UITextField"] || [e.cls isEqualToString:@"UITextView"]) {
                    UIView *v = [self.weakMap objectForKey:e.eid];
                    if ([v canBecomeFirstResponder]) { [v becomeFirstResponder]; fr = v; break; }
                }
            }
        }
        if (!fr) return;
        @try {
            if ([fr respondsToSelector:@selector(insertText:)]) {
                [(id<UIKeyInput>)fr insertText:text];
                ok = YES;
            }
            if ([fr isKindOfClass:[UITextField class]]) {
                UITextField *tf = (UITextField *)fr;
                if (!ok) { tf.text = [tf.text ?: @"" stringByAppendingString:text]; ok = YES; }
                [tf sendActionsForControlEvents:UIControlEventEditingChanged];
                if ([tf.delegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)]) {}
            } else if ([fr isKindOfClass:[UITextView class]]) {
                UITextView *tv = (UITextView *)fr;
                if (!ok) { tv.text = [tv.text ?: @"" stringByAppendingString:text]; ok = YES; }
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
            }
        } @catch (NSException *e) { ok = NO; }
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return ok;
}

#pragma mark screenshot

- (UIImage *)screenshot {
    NSArray *wins = [self appWindows];
    UIWindow *base = nil;
    for (UIWindow *w in wins) {
        if (!w.isHidden && w.windowLevel <= UIWindowLevelNormal + 1) { base = w; break; }
    }
    if (!base) base = wins.firstObject;
    if (!base) return nil;
    CGRect bounds = base.bounds;
    if (bounds.size.width < 1) bounds = [UIScreen mainScreen].bounds;

    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:bounds.size
                                                                       format:[[UIGraphicsImageRendererFormat alloc] init]];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (UIWindow *w in wins) {
            if (w.isHidden || w.alpha < 0.01) continue;
            if (w.bounds.size.width < 1) continue;
            @try {
                [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:NO];
            } @catch (NSException *e) {}
        }
    }];
    return img;
}

- (BOOL)saveScreenshot:(NSString *)path {
    UIImage *img = [self screenshot];
    if (!img) return NO;
    [AAU ensureDataDir];
    NSString *out = path.length ? path : [[[AAU dataDir] stringByAppendingPathComponent:@"shots"]
                                          stringByAppendingPathComponent:
                                          [NSString stringWithFormat:@"shot-%.0f.jpg", [[NSDate date] timeIntervalSince1970]]];
    NSData *data = UIImageJPEGRepresentation(img, 0.72);
    if (!data) data = UIImagePNGRepresentation(img);
    return [data writeToFile:out atomically:YES];
}

#pragma mark app info

+ (NSString *)foregroundBundleID {
    return [NSBundle mainBundle].bundleIdentifier ?: @"unknown";
}

+ (NSDictionary *)appInfo {
    NSBundle *b = [NSBundle mainBundle];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"bundle_id"] = b.bundleIdentifier ?: @"?";
    d[@"name"] = [b objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [b objectForInfoDictionaryKey:@"CFBundleName"] ?: @"?";
    d[@"version"] = [b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    d[@"build"] = [b objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    d[@"executable"] = b.executablePath ?: @"?";
    d[@"bundle_path"] = b.bundlePath ?: @"?";
    d[@"container"] = NSHomeDirectory();
    d[@"pid"] = @(getpid());
    d[@"uid"] = @(getuid());
    d[@"system"] = [NSString stringWithFormat:@"%@ %@", [[UIDevice currentDevice] systemName], [[UIDevice currentDevice] systemVersion]];
    d[@"model"] = [[UIDevice currentDevice] model];
    d[@"screen"] = [NSString stringWithFormat:@"%.0fx%.0f@%.0fx", [UIScreen mainScreen].bounds.size.width,
                    [UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].scale];
    return d;
}

@end
