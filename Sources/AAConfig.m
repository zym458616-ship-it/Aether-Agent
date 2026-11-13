//
//  AAConfig.m
//  Theme, small utilities and persisted configuration.
//

#import "Aether.h"

#pragma mark - Utilities

@implementation AAU

+ (BOOL)isDark {
    if (@available(iOS 13.0, *)) {
        return UITraitCollection.currentTraitCollection.userInterfaceStyle != UIUserInterfaceStyleLight;
    }
    return YES;
}

+ (UIColor *)bg {
    return [self isDark] ? [UIColor colorWithRed:0.055 green:0.059 blue:0.075 alpha:1.0]
                         : [UIColor colorWithRed:0.965 green:0.968 blue:0.980 alpha:1.0];
}

+ (UIColor *)card {
    return [self isDark] ? [UIColor colorWithRed:0.098 green:0.106 blue:0.129 alpha:0.96]
                         : [UIColor colorWithWhite:1.0 alpha:0.96];
}

+ (UIColor *)card2 {
    return [self isDark] ? [UIColor colorWithRed:0.145 green:0.157 blue:0.188 alpha:1.0]
                         : [UIColor colorWithRed:0.929 green:0.937 blue:0.957 alpha:1.0];
}

+ (UIColor *)stroke {
    return [self isDark] ? [UIColor colorWithWhite:1.0 alpha:0.09]
                         : [UIColor colorWithWhite:0.0 alpha:0.08];
}

+ (UIColor *)text {
    return [self isDark] ? [UIColor colorWithRed:0.945 green:0.953 blue:0.973 alpha:1.0]
                         : [UIColor colorWithRed:0.078 green:0.086 blue:0.110 alpha:1.0];
}

+ (UIColor *)textDim {
    return [self isDark] ? [UIColor colorWithRed:0.541 green:0.565 blue:0.620 alpha:1.0]
                         : [UIColor colorWithRed:0.380 green:0.404 blue:0.451 alpha:1.0];
}

+ (UIColor *)accent {
    return [UIColor colorWithRed:0.353 green:0.478 blue:1.000 alpha:1.0];
}

+ (UIColor *)accent2 {
    return [UIColor colorWithRed:0.639 green:0.361 blue:0.984 alpha:1.0];
}

+ (UIColor *)ok {
    return [UIColor colorWithRed:0.204 green:0.780 blue:0.474 alpha:1.0];
}

+ (UIColor *)warn {
    return [UIColor colorWithRed:0.988 green:0.706 blue:0.239 alpha:1.0];
}

+ (UIColor *)err {
    return [UIColor colorWithRed:0.976 green:0.361 blue:0.361 alpha:1.0];
}

+ (UIFont *)ui:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)ui:(CGFloat)size weight:(UIFontWeight)w {
    return [UIFont systemFontOfSize:size weight:w];
}

+ (UIFont *)mono:(CGFloat)size {
    UIFont *f = [UIFont fontWithName:@"SFMono-Regular" size:size];
    if (!f) f = [UIFont fontWithName:@"Menlo-Regular" size:size];
    if (!f) f = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
    return f;
}

+ (void)round:(UIView *)v radius:(CGFloat)r {
    if (!v) return;
    v.layer.cornerRadius = r;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
}

+ (void)border:(UIView *)v color:(UIColor *)c width:(CGFloat)w {
    if (!v) return;
    v.layer.borderColor = c.CGColor;
    v.layer.borderWidth = w;
}

+ (void)blur:(UIView *)host style:(int)style {
    if (!host) return;
    UIBlurEffectStyle s = UIBlurEffectStyleDark;
    if (@available(iOS 13.0, *)) {
        if (style == 1) s = UIBlurEffectStyleSystemThinMaterialLight;
        else if (style == 2) s = UIBlurEffectStyleSystemUltraThinMaterialDark;
        else s = UIBlurEffectStyleSystemThinMaterialDark;
    } else {
        s = (style == 1) ? UIBlurEffectStyleLight : UIBlurEffectStyleDark;
    }
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:s]];
    blur.frame = host.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.userInteractionEnabled = NO;
    [host insertSubview:blur atIndex:0];
}

+ (void)haptic:(NSInteger)style {
    if (![AAConfig shared].haptics) return;
    Class gen = NSClassFromString(@"UIImpactFeedbackGenerator");
    if (!gen) return;
    if (style == 3 || style == 4) {
        UINotificationFeedbackGenerator *n = [[UINotificationFeedbackGenerator alloc] init];
        [n notificationOccurred:(style == 3 ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError)];
        return;
    }
    UIImpactFeedbackStyle s = UIImpactFeedbackStyleLight;
    if (style == 1) s = UIImpactFeedbackStyleMedium;
    if (style == 2) s = UIImpactFeedbackStyleHeavy;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:s];
    [g impactOccurred];
}

static UIView *AAActiveToast = nil;

+ (void)toast:(NSString *)text {
    if (!text.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [AAOverlay shared].window ?: [UIApplication sharedApplication].keyWindow;
        if (!win) return;
        if (AAActiveToast) { [AAActiveToast removeFromSuperview]; AAActiveToast = nil; }

        UIView *box = [[UIView alloc] init];
        box.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.86];
        box.alpha = 0.0;
        [self round:box radius:12];
        box.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = text;
        lbl.textColor = [UIColor whiteColor];
        lbl.font = [self ui:13 weight:UIFontWeightMedium];
        lbl.numberOfLines = 0;
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:lbl];

        [win addSubview:box];
        [NSLayoutConstraint activateConstraints:@[
            [lbl.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14],
            [lbl.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-14],
            [lbl.topAnchor constraintEqualToAnchor:box.topAnchor constant:9],
            [lbl.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-9],
            [box.centerXAnchor constraintEqualToAnchor:win.centerXAnchor],
            [box.bottomAnchor constraintEqualToAnchor:win.bottomAnchor constant:-84],
            [box.widthAnchor constraintLessThanOrEqualToConstant:win.bounds.size.width - 60],
        ]];
        AAActiveToast = box;

        [UIView animateWithDuration:0.22 animations:^{ box.alpha = 1.0; } completion:^(BOOL f) {
            [UIView animateWithDuration:0.28 delay:1.5 options:0 animations:^{ box.alpha = 0.0; } completion:^(BOOL f2) {
                [box removeFromSuperview];
                if (AAActiveToast == box) AAActiveToast = nil;
            }];
        }];
    });
}

+ (NSString *)homePath {
    return NSHomeDirectory();
}

+ (NSString *)dataDir {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Aether"];
}

+ (NSString *)ensureDataDir {
    NSString *d = [self dataDir];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:d]) {
        [fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    NSString *s = [d stringByAppendingPathComponent:@"shots"];
    if (![fm fileExistsAtPath:s]) {
        [fm createDirectoryAtPath:s withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return d;
}

+ (NSString *)shortPath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]]) return @"";
    NSString *h = NSHomeDirectory();
    NSString *r = path;
    if (h.length && [path hasPrefix:h]) r = [@"~" stringByAppendingString:[path substringFromIndex:h.length]];
    if (r.length > 64) r = [NSString stringWithFormat:@"…%@", [r substringFromIndex:r.length - 60]];
    return r;
}

+ (NSString *)humanBytes:(unsigned long long)b {
    if (b < 1024) return [NSString stringWithFormat:@"%lluB", b];
    if (b < 1024 * 1024) return [NSString stringWithFormat:@"%.1fK", b / 1024.0];
    if (b < 1024ULL * 1024 * 1024) return [NSString stringWithFormat:@"%.1fM", b / 1048576.0];
    return [NSString stringWithFormat:@"%.2fG", b / 1073741824.0];
}

+ (NSString *)humanTime:(NSTimeInterval)ts {
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = [[NSCalendar currentCalendar] isDateInToday:d] ? @"HH:mm" : @"MM/dd HH:mm";
    return [f stringFromDate:d];
}

+ (UIColor *)colorForTool:(NSString *)name {
    if ([name hasPrefix:@"shell"]) return [UIColor colorWithRed:0.298 green:0.851 blue:0.549 alpha:1];
    if ([name hasPrefix:@"fs"]) return [UIColor colorWithRed:0.298 green:0.624 blue:0.976 alpha:1];
    if ([name hasPrefix:@"ui"]) return [UIColor colorWithRed:0.639 green:0.361 blue:0.984 alpha:1];
    if ([name hasPrefix:@"app"]) return [UIColor colorWithRed:0.988 green:0.706 blue:0.239 alpha:1];
    if ([name hasPrefix:@"net"]) return [UIColor colorWithRed:0.294 green:0.812 blue:0.851 alpha:1];
    return [UIColor colorWithWhite:0.6 alpha:1];
}

@end

#pragma mark - Config

static NSString *const kCfgProvider   = @"provider";
static NSString *const kCfgBaseURL    = @"baseURL";
static NSString *const kCfgAPIKey     = @"apiKey";
static NSString *const kCfgModel      = @"model";
static NSString *const kCfgPrompt     = @"systemPrompt";
static NSString *const kCfgMaxCtx     = @"maxContext";
static NSString *const kCfgMaxSteps   = @"maxSteps";
static NSString *const kCfgTemp       = @"temperature";
static NSString *const kCfgStream     = @"stream";
static NSString *const kCfgTools      = @"allowTools";
static NSString *const kCfgVision     = @"visionInput";
static NSString *const kCfgReasoning  = @"showReasoning";
static NSString *const kCfgAutoApprove= @"autoApprove";
static NSString *const kCfgHaptics    = @"haptics";
static NSString *const kCfgBallAlpha  = @"ballOpacity";
static NSString *const kCfgBallCenter = @"ballCenter";
static NSString *const kCfgBallHidden = @"ballHidden";
static NSString *const kCfgLastSID    = @"lastSessionID";

@interface AAConfig ()
@property (nonatomic, strong) NSUserDefaults *defs;
@end

@implementation AAConfig

+ (instancetype)shared {
    static AAConfig *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[AAConfig alloc] init]; [c load]; });
    return c;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defs = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

- (void)load {
    NSDictionary *d = [self defaultsDictionary];
    self.provider     = d[kCfgProvider] ?: @"openai";
    self.baseURL      = d[kCfgBaseURL] ?: @"https://api.openai.com";
    self.apiKey       = d[kCfgAPIKey] ?: @"";
    self.model        = d[kCfgModel] ?: @"gpt-4o-mini";
    self.systemPrompt = d[kCfgPrompt] ?: [AAConfig defaultSystemPrompt];
    self.maxContext   = [d[kCfgMaxCtx] integerValue];
    self.maxSteps     = [d[kCfgMaxSteps] integerValue] ?: 20;
    self.temperature  = d[kCfgTemp] ? [d[kCfgTemp] doubleValue] : 0.3;
    self.stream       = d[kCfgStream] ? [d[kCfgStream] boolValue] : YES;
    self.allowTools   = d[kCfgTools] ? [d[kCfgTools] boolValue] : YES;
    self.visionInput  = [d[kCfgVision] boolValue];
    self.showReasoning= d[kCfgReasoning] ? [d[kCfgReasoning] boolValue] : YES;
    self.autoApprove  = d[kCfgAutoApprove] ? [d[kCfgAutoApprove] boolValue] : YES;
    self.haptics      = d[kCfgHaptics] ? [d[kCfgHaptics] boolValue] : YES;
    self.ballOpacity  = d[kCfgBallAlpha] ? [d[kCfgBallAlpha] doubleValue] : 0.92;
    self.ballHidden   = [d[kCfgBallHidden] boolValue];
    self.lastSessionID= d[kCfgLastSID] ?: @"";
    self.ballCenter   = CGPointMake(-1, -1);
    NSString *bc = d[kCfgBallCenter];
    if (bc.length) {
        NSArray *p = [bc componentsSeparatedByString:@","];
        if (p.count == 2) self.ballCenter = CGPointMake([p[0] doubleValue], [p[1] doubleValue]);
    }
}

- (NSDictionary *)defaultsDictionary {
    // NSUserDefaults lives in the host app container — good enough and survives
    // app restarts. Keeps API key per-app, which is usually what people want.
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSString *k in @[kCfgProvider, kCfgBaseURL, kCfgAPIKey, kCfgModel, kCfgPrompt,
                          kCfgMaxCtx, kCfgMaxSteps, kCfgTemp, kCfgStream, kCfgTools,
                          kCfgVision, kCfgReasoning, kCfgAutoApprove, kCfgHaptics,
                          kCfgBallAlpha, kCfgBallCenter, kCfgBallHidden, kCfgLastSID]) {
        id v = [self.defs objectForKey:k];
        if (v) m[k] = v;
    }
    return m;
}

+ (NSString *)defaultSystemPrompt {
    return @"你是 Aether，运行在 iOS 应用进程内的全权限 AI 智能体。"
           @"你可以通过工具真实地操作这台设备：执行 shell 命令、读写任意文件、查看当前 App 的界面层级、"
           @"点击/滑动/输入文本接管界面、截图、发网络请求、启动 App。"
           @"原则：先观察后行动；每次只做必要的操作；操作前用 ui_dump 或 fs_list 确认现状；"
           @"遇到错误读错误信息再换方案；完成任务后用 task_done 汇报。回答使用简体中文，简洁、可执行。";
}

- (void)save {
    NSUserDefaults *d = self.defs;
    [d setObject:self.provider forKey:kCfgProvider];
    [d setObject:self.baseURL forKey:kCfgBaseURL];
    [d setObject:self.apiKey forKey:kCfgAPIKey];
    [d setObject:self.model forKey:kCfgModel];
    [d setObject:self.systemPrompt forKey:kCfgPrompt];
    [d setInteger:self.maxContext forKey:kCfgMaxCtx];
    [d setInteger:self.maxSteps forKey:kCfgMaxSteps];
    [d setDouble:self.temperature forKey:kCfgTemp];
    [d setBool:self.stream forKey:kCfgStream];
    [d setBool:self.allowTools forKey:kCfgTools];
    [d setBool:self.visionInput forKey:kCfgVision];
    [d setBool:self.showReasoning forKey:kCfgReasoning];
    [d setBool:self.autoApprove forKey:kCfgAutoApprove];
    [d setBool:self.haptics forKey:kCfgHaptics];
    [d setDouble:self.ballOpacity forKey:kCfgBallAlpha];
    [d setBool:self.ballHidden forKey:kCfgBallHidden];
    [d setObject:self.lastSessionID forKey:kCfgLastSID];
    [d setObject:[NSString stringWithFormat:@"%.1f,%.1f", self.ballCenter.x, self.ballCenter.y] forKey:kCfgBallCenter];
    [d synchronize];
}

- (void)reset {
    self.provider = @"openai";
    self.baseURL = @"https://api.openai.com";
    self.apiKey = @"";
    self.model = @"gpt-4o-mini";
    self.systemPrompt = [AAConfig defaultSystemPrompt];
    self.maxContext = 0;
    self.maxSteps = 20;
    self.temperature = 0.3;
    self.stream = YES;
    self.allowTools = YES;
    self.visionInput = NO;
    self.autoApprove = YES;
    self.haptics = YES;
    self.showReasoning = YES;
    self.ballOpacity = 0.92;
    [self save];
}

- (BOOL)isConfigured {
    return self.apiKey.length > 4 && self.baseURL.length > 6 && self.model.length > 0;
}

- (NSInteger)effectiveMaxContext {
    if (self.maxContext > 512) return self.maxContext;
    // Sensible defaults per model family when the user left it on "auto".
    NSString *m = self.model.lowercaseString ?: @"";
    if ([m containsString:@"128k"] || [m containsString:@"4.1"] || [m containsString:@"gpt-4o"]) return 128000;
    if ([m containsString:@"claude"] || [m containsString:@"sonnet"] || [m containsString:@"opus"]) return 200000;
    if ([m containsString:@"gemini"]) return 1000000;
    if ([m containsString:@"32k"]) return 32768;
    if ([m containsString:@"deepseek"] || [m containsString:@"qwen"] || [m containsString:@"glm"]) return 65536;
    return 32768;
}

- (NSDictionary *)requestHeaders {
    if ([self.provider isEqualToString:@"anthropic"]) {
        return @{
            @"x-api-key": self.apiKey ?: @"",
            @"anthropic-version": @"2023-06-01",
            @"content-type": @"application/json",
        };
    }
    return @{
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey ?: @""],
        @"Content-Type": @"application/json",
    };
}

@end
