//
//  AAOverlay.m
//  The window, the floating ball and the panel shell.
//

#import "AAUI.h"

#pragma mark - Pass-through container

@interface AAContainer : UIView
@end

@implementation AAContainer
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return (v == self) ? nil : v;      // let touches fall through to the host app
}
@end

#pragma mark - Pass-through window

@interface AAWindow : UIWindow
@end

@implementation AAWindow

// Without this the overlay window would swallow every touch in the app: the
// root view controller's view covers the whole screen and hit-tests as itself.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self) return nil;
    if (v == self.rootViewController.view) return nil;
    if ([v isKindOfClass:[AAContainer class]]) return nil;
    return v;
}

@end

#pragma mark - Usage bar

@interface AAUsageBar : UIView
@property (nonatomic, assign) double progress;
@end

@implementation AAUsageBar
- (void)setProgress:(double)progress {
    _progress = MAX(0, MIN(1, progress));
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [[AAU stroke] CGColor]);
    CGContextFillRect(ctx, rect);
    if (_progress <= 0) return;
    UIColor *c = _progress > 0.85 ? [AAU err] : (_progress > 0.65 ? [AAU warn] : [AAU accent]);
    CGRect f = CGRectMake(0, 0, rect.size.width * _progress, rect.size.height);
    CGContextSetFillColorWithColor(ctx, [c CGColor]);
    CGContextFillRect(ctx, f);
}
@end

#pragma mark - Floating ball

@interface AABall : UIView
@property (nonatomic, strong) CAGradientLayer *grad;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) CAShapeLayer *ring;
@end

@implementation AABall

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        _grad = [CAGradientLayer layer];
        _grad.frame = self.bounds;
        _grad.cornerRadius = frame.size.width / 2;
        _grad.cornerCurve = kCACornerCurveContinuous;
        _grad.colors = @[(id)[[AAU accent] CGColor], (id)[[AAU accent2] CGColor]];
        _grad.startPoint = CGPointMake(0, 0);
        _grad.endPoint = CGPointMake(1, 1);
        [self.layer addSublayer:_grad];

        _ring = [CAShapeLayer layer];
        _ring.frame = self.bounds;
        _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 3, 3)].CGPath;
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.35].CGColor;
        _ring.lineWidth = 1.2;
        [self.layer addSublayer:_ring];

        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
        _icon.tintColor = [UIColor whiteColor];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.frame = CGRectInset(self.bounds, 16, 16);
        _icon.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_icon];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _grad.frame = self.bounds;
    _ring.frame = self.bounds;
}

- (void)pulse {
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    a.fromValue = @1.0;
    a.toValue = @1.22;
    a.duration = 0.42;
    a.autoreverses = YES;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:a forKey:@"pulse"];
}

@end

#pragma mark - Panel

@interface AAPanel () <UIScrollViewDelegate>
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *dot;
@property (nonatomic, strong) UIStackView *tabBar;
@property (nonatomic, strong) NSArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UIView *tabIndicator;
@property (nonatomic, strong) NSLayoutConstraint *tabCenterX;
@property (nonatomic, strong) AAUsageBar *usageBar;
@property (nonatomic, strong) UIView *contentHost;
@property (nonatomic, assign) NSInteger tab;
@end

@implementation AAPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [AAU bg];
        self.layer.cornerRadius = 24;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        [AAU border:self color:[[UIColor whiteColor] colorWithAlphaComponent:[AAU isDark] ? 0.10 : 0.06] width:0.8];

        [self buildHeader];
        [self buildContent];
        self.tab = 0;
    }
    return self;
}

- (void)buildHeader {
    _header = [[UIView alloc] init];
    _header.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_header];

    _dot = [[UIView alloc] init];
    _dot.backgroundColor = [AAU ok];
    _dot.translatesAutoresizingMaskIntoConstraints = NO;
    [AAU round:_dot radius:3.5];
    [_header addSubview:_dot];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"Aether";
    _titleLabel.font = [AAU ui:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [AAU text];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_header addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.font = [AAU mono:9.5];
    _subtitleLabel.textColor = [AAU textDim];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_header addSubview:_subtitleLabel];

    UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
    [plus setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    plus.tintColor = [AAU textDim];
    plus.translatesAutoresizingMaskIntoConstraints = NO;
    [plus addTarget:self action:@selector(newTask) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:plus];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = [AAU textDim];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:close];

    // tabs
    _tabBar = [[UIStackView alloc] init];
    _tabBar.axis = UILayoutConstraintAxisHorizontal;
    _tabBar.distribution = UIStackViewDistributionFillEqually;
    _tabBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_tabBar];

    NSArray *titles = @[@"对话", @"终端", @"设置", @"历史"];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [AAU ui:12 weight:UIFontWeightMedium];
        [b setTitleColor:[AAU textDim] forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabBar addArrangedSubview:b];
        [btns addObject:b];
    }
    _tabButtons = btns;

    _tabIndicator = [[UIView alloc] init];
    _tabIndicator.backgroundColor = [AAU accent];
    _tabIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [AAU round:_tabIndicator radius:1.5];
    [self addSubview:_tabIndicator];

    _usageBar = [[AAUsageBar alloc] init];
    _usageBar.translatesAutoresizingMaskIntoConstraints = NO;
    _usageBar.progress = 0;
    [self addSubview:_usageBar];

    _tabCenterX = [_tabIndicator.centerXAnchor constraintEqualToAnchor:_tabBar.leadingAnchor constant:0];
    _tabCenterX.active = YES;

    _contentHost = [[UIView alloc] init];
    _contentHost.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_contentHost];

    [NSLayoutConstraint activateConstraints:@[
        [_header.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [_header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_header.heightAnchor constraintEqualToConstant:26],

        [_dot.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor],
        [_dot.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],
        [_dot.widthAnchor constraintEqualToConstant:7],
        [_dot.heightAnchor constraintEqualToConstant:7],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:7],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:8],
        [_subtitleLabel.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:plus.leadingAnchor constant:-8],

        [plus.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-14],
        [plus.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],
        [plus.widthAnchor constraintEqualToConstant:26],
        [plus.heightAnchor constraintEqualToConstant:26],

        [close.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor],
        [close.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:26],
        [close.heightAnchor constraintEqualToConstant:26],

        [_tabBar.topAnchor constraintEqualToAnchor:_header.bottomAnchor constant:10],
        [_tabBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_tabBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [_tabBar.heightAnchor constraintEqualToConstant:30],

        [_tabIndicator.topAnchor constraintEqualToAnchor:_tabBar.bottomAnchor constant:1],
        [_tabIndicator.heightAnchor constraintEqualToConstant:2.5],
        [_tabIndicator.widthAnchor constraintEqualToConstant:22],

        [_usageBar.topAnchor constraintEqualToAnchor:_tabIndicator.bottomAnchor constant:2],
        [_usageBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_usageBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_usageBar.heightAnchor constraintEqualToConstant:1.5],

        [_contentHost.topAnchor constraintEqualToAnchor:_usageBar.bottomAnchor constant:2],
        [_contentHost.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_contentHost.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_contentHost.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)buildContent {
    _chat = [[AAChatView alloc] init];
    _terminal = [[AATerminalView alloc] init];
    _settings = [[AASettingsView alloc] init];
    _history = [[AAHistoryView alloc] init];

    for (UIView *v in @[_chat, _terminal, _settings, _history]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        v.hidden = YES;
        [_contentHost addSubview:v];
        [NSLayoutConstraint activateConstraints:@[
            [v.topAnchor constraintEqualToAnchor:_contentHost.topAnchor],
            [v.leadingAnchor constraintEqualToAnchor:_contentHost.leadingAnchor],
            [v.trailingAnchor constraintEqualToAnchor:_contentHost.trailingAnchor],
            [v.bottomAnchor constraintEqualToAnchor:_contentHost.bottomAnchor],
        ]];
    }

    __weak typeof(self) weakSelf = self;
    _chat.onSend = ^(NSString *text, BOOL withShot) {
        [weakSelf startTask:text withShot:withShot];
    };
    _chat.onStop = ^{
        [[AAAgent shared] cancel];
    };
    _chat.onNewTask = ^{
        [weakSelf newTask];
    };
    _history.onSelect = ^(NSString *sid) {
        [weakSelf setSession:sid];
        [weakSelf selectTab:0];
    };

    [self selectTab:0];
}

- (void)updateSubtitle {
    AAConfig *c = [AAConfig shared];
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@ · %@", c.model ?: @"-", c.provider];
}

- (void)selectTab:(NSInteger)tab {
    _tab = tab;
    NSArray *views = @[_chat, _terminal, _settings, _history];
    for (NSUInteger i = 0; i < views.count; i++) ((UIView *)views[i]).hidden = (i != (NSUInteger)tab);
    for (NSUInteger i = 0; i < _tabButtons.count; i++) {
        BOOL on = (i == (NSUInteger)tab);
        [_tabButtons[i] setTitleColor:on ? [AAU text] : [AAU textDim] forState:UIControlStateNormal];
        _tabButtons[i].titleLabel.font = [AAU ui:12 weight:on ? UIFontWeightSemibold : UIFontWeightMedium];
    }
    CGFloat w = self.bounds.size.width - 20;
    if (w > 0) _tabCenterX.constant = w / 8.0 + w / 4.0 * tab;
    if (tab == 2) [_settings reloadUI];
    if (tab == 3) [_history reloadData];
    if (tab == 0) [_chat reload];
    if (tab == 1) [_terminal focusInput];
}

- (void)tabTapped:(UIButton *)b {
    [self selectTab:b.tag];
    [AAU haptic:0];
    CGFloat w = self.bounds.size.width - 20;
    if (w > 0) {
        self.tabCenterX.constant = w / 8.0 + w / 4.0 * b.tag;
        [UIView animateWithDuration:0.22 animations:^{ [self layoutIfNeeded]; }];
    }
}

- (void)newTask {
    if ([AAAgent shared].running) [[AAAgent shared] cancel];
    [AAConfig shared].lastSessionID = @"";
    [[AAConfig shared] save];
    [_chat setStatus:nil];
    [_chat setBusy:NO];
    [_chat showEmptyState];
    [self selectTab:0];
}

- (void)closeTapped {
    if (self.onClose) self.onClose();
}

- (void)setSession:(NSString *)sid {
    [AAConfig shared].lastSessionID = sid;
    [[AAConfig shared] save];
    [_chat reload];
}

- (void)refreshAll {
    [self updateSubtitle];
    [_chat reload];
    [_history reloadData];
}

- (void)setUsageProgress:(double)p {
    _usageBar.progress = p;
}

- (void)startTask:(NSString *)text withShot:(BOOL)shot {
    [_chat beginStreaming];
    [_chat setBusy:YES];
    [_chat setStatus:@"思考中…"];
    [[AAAgent shared] startTask:text session:[AAConfig shared].lastSessionID];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width - 20;
    if (w > 0) _tabCenterX.constant = w / 8.0 + w / 4.0 * _tab;
}

@end

#pragma mark - Overlay

@interface AAOverlay () {
    UIWindow *_prevKeyWindow;
    CGPoint _ballStart;
    BOOL _ballMoved;
    BOOL _panelOpen;
    CGFloat _kbHeight;
    CGFloat _basePanelHeight;
}
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) AAContainer *container;
@property (nonatomic, strong) AABall *ball;
@property (nonatomic, strong) AAPanel *panel;
@property (nonatomic, strong) UIView *dim;
@property (nonatomic, strong) NSLayoutConstraint *panelBottom;
@property (nonatomic, strong) NSLayoutConstraint *panelHeight;
@property (nonatomic, assign) BOOL attached;
@end

@implementation AAOverlay

+ (instancetype)shared {
    static AAOverlay *o = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        o = [[AAOverlay alloc] init];
        [o setup];
    });
    return o;
}

- (UIView *)container { return _container; }

+ (void)boot {
    (void)[AAOverlay shared];
}

#pragma mark boot

- (void)setup {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildWindow];
        [self buildBall];
        [self buildPanel];
        [self wireAgent];
        [self wireKeyboard];
        [self restoreBallPosition];
        self.attached = YES;
    });
}

- (UIWindowScene *)activeScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive)
                return (UIWindowScene *)s;
        }
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
        }
    }
    return nil;
}

- (void)buildWindow {
    UIWindowScene *scene = [self activeScene];
    if (scene) {
        _window = [[AAWindow alloc] initWithWindowScene:scene];
    } else {
        _window = [[AAWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    _window.frame = [UIScreen mainScreen].bounds;
    _window.windowLevel = UIWindowLevelAlert + 200;
    _window.backgroundColor = [UIColor clearColor];
    _window.rootViewController = [[UIViewController alloc] init];
    _window.rootViewController.view.backgroundColor = [UIColor clearColor];

    _container = [[AAContainer alloc] initWithFrame:_window.bounds];
    _container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _container.backgroundColor = [UIColor clearColor];
    [_window.rootViewController.view addSubview:_container];

    _window.hidden = NO;
    AALog(@"window attached at level %.0f", _window.windowLevel);
}

- (void)buildBall {
    CGFloat size = 56;
    _ball = [[AABall alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    _ball.alpha = 0.0;
    [_container addSubview:_ball];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_ball addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [_ball addGestureRecognizer:tap];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.minimumPressDuration = 0.45;
    [_ball addGestureRecognizer:press];

    [self showBall:![AAConfig shared].ballHidden];
}

- (void)buildPanel {
    _panel = [[AAPanel alloc] initWithFrame:CGRectZero];
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    _panel.alpha = 0.0;
    _panel.transform = CGAffineTransformMakeTranslation(0, 40);
    [_container addSubview:_panel];

    __weak typeof(self) weakSelf = self;
    _panel.onClose = ^{ [weakSelf closePanel]; };

    _dim = [[UIView alloc] init];
    _dim.translatesAutoresizingMaskIntoConstraints = NO;
    _dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];
    _dim.alpha = 0.0;
    _dim.hidden = YES;
    [_container insertSubview:_dim belowSubview:_panel];
    UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closePanel)];
    [_dim addGestureRecognizer:dimTap];

    CGFloat maxW = MIN(620, [UIScreen mainScreen].bounds.size.width - 16);
    _basePanelHeight = [UIScreen mainScreen].bounds.size.height * 0.88;

    _panelBottom = [_panel.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor constant:-8];
    _panelHeight = [_panel.heightAnchor constraintEqualToConstant:_basePanelHeight];

    [NSLayoutConstraint activateConstraints:@[
        [_panel.centerXAnchor constraintEqualToAnchor:_container.centerXAnchor],
        [_panel.widthAnchor constraintEqualToConstant:maxW],
        _panelBottom,
        _panelHeight,
        [_dim.topAnchor constraintEqualToAnchor:_container.topAnchor],
        [_dim.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor],
        [_dim.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor],
        [_dim.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor],
    ]];
    [_panel refreshAll];
}

#pragma mark public

- (void)showBall:(BOOL)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            self.ball.alpha = show ? [AAConfig shared].ballOpacity : 0.0;
        }];
        self.ball.userInteractionEnabled = show;
    });
}

- (BOOL)isPanelOpen { return _panelOpen; }
- (UIEdgeInsets)safeInsets { return _window.safeAreaInsets; }
- (void)pulse { [_ball pulse]; }

- (void)openPanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_panelOpen) return;
        self->_panelOpen = YES;
        self->_prevKeyWindow = [UIApplication sharedApplication].keyWindow;
        [self->_panel refreshAll];
        [self->_panel selectTab:0];

        self->_dim.hidden = NO;
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
            self->_panel.alpha = 1.0;
            self->_panel.transform = CGAffineTransformIdentity;
            self->_dim.alpha = 1.0;
            self->_ball.alpha = 0.0;
        } completion:nil];
        [self->_window makeKeyWindow];
        [AAU haptic:1];
    });
}

- (void)closePanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_panelOpen) return;
        self->_panelOpen = NO;
        [self->_panel endEditing:YES];
        [UIView animateWithDuration:0.24 animations:^{
            self->_panel.alpha = 0.0;
            self->_panel.transform = CGAffineTransformMakeTranslation(0, 40);
            self->_dim.alpha = 0.0;
            self->_ball.alpha = [AAConfig shared].ballHidden ? 0.0 : [AAConfig shared].ballOpacity;
        } completion:^(BOOL finished) {
            self->_dim.hidden = YES;
        }];
        if (self->_prevKeyWindow) [self->_prevKeyWindow makeKeyWindow];
        self->_prevKeyWindow = nil;
    });
}

- (void)reloadChat {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_panel.chat reload];
        [self->_panel.history reloadData];
    });
}

#pragma mark ball gestures

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:_container];
    if (g.state == UIGestureRecognizerStateBegan) {
        _ballStart = _ball.center;
        _ballMoved = NO;
        [UIView animateWithDuration:0.15 animations:^{ self.ball.transform = CGAffineTransformMakeScale(1.08, 1.08); }];
    } else if (g.state == UIGestureRecognizerStateChanged) {
        if (fabs(t.x) > 4 || fabs(t.y) > 4) _ballMoved = YES;
        CGPoint c = CGPointMake(_ballStart.x + t.x, _ballStart.y + t.y);
        _ball.center = [self clampCenter:c];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.15 animations:^{ self.ball.transform = CGAffineTransformIdentity; }];
        [self snapBall];
    }
}

- (CGPoint)clampCenter:(CGPoint)c {
    CGFloat half = 28;
    CGFloat w = _container.bounds.size.width, h = _container.bounds.size.height;
    CGFloat top = 60, bottom = h - 40;
    return CGPointMake(MAX(half + 6, MIN(w - half - 6, c.x)),
                       MAX(top, MIN(bottom, c.y)));
}

- (void)snapBall {
    CGFloat w = _container.bounds.size.width;
    CGFloat targetX = (_ball.center.x < w / 2) ? 34 : w - 34;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.ball.center = CGPointMake(targetX, self.ball.center.y);
    } completion:nil];
    [AAConfig shared].ballCenter = _ball.center;
    [[AAConfig shared] save];
}

- (void)restoreBallPosition {
    CGPoint c = [AAConfig shared].ballCenter;
    CGSize s = _container.bounds.size;
    if (c.x < 0 || c.y < 0 || c.x > s.width || c.y > s.height) {
        c = CGPointMake(s.width - 34, s.height * 0.42);
    }
    _ball.center = [self clampCenter:c];
    _ball.alpha = [AAConfig shared].ballHidden ? 0.0 : [AAConfig shared].ballOpacity;
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    if (_ballMoved) return;
    [self openPanel];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [AAU haptic:2];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"新建任务" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self openPanel];
        [self.panel newTask];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"打开终端" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self openPanel];
        [self.panel selectTab:1];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"截取当前界面" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[AAUIBridge shared] saveScreenshot:nil];
        [AAU toast:@"已保存截图到 Aether/shots"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"隐藏悬浮球" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [AAConfig shared].ballHidden = YES;
        [[AAConfig shared] save];
        [self showBall:NO];
        [AAU toast:@"已隐藏；在设置中可恢复"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _ball;
    UIViewController *root = _window.rootViewController;
    [root presentViewController:sheet animated:YES completion:nil];
}

#pragma mark keyboard

- (void)wireKeyboard {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillChangeFrameNotification
                                                     object:nil queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
        CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        CGFloat overlap = MAX(0, screenH - end.origin.y);
        if (fabs(overlap - self->_kbHeight) < 1) return;
        self->_kbHeight = overlap;
        [self adjustForKeyboard];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillHideNotification
                                                     object:nil queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
        self->_kbHeight = 0;
        [self adjustForKeyboard];
    }];
}

- (void)adjustForKeyboard {
    CGFloat bottomInset = _container.safeAreaInsets.bottom;
    CGFloat overlap = MAX(0, _kbHeight - bottomInset);
    _panelBottom.constant = -(8 + overlap);
    CGFloat h = _basePanelHeight - overlap;
    _panelHeight.constant = MAX(300, h);
    [UIView animateWithDuration:0.22 animations:^{ [self.container layoutIfNeeded]; }];
}

#pragma mark agent wiring

- (void)wireAgent {
    AAAgent *a = [AAAgent shared];
    __weak typeof(self) weakSelf = self;

    a.onDelta = ^(NSString *text, NSString *reasoning) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.panel.chat appendStream:text reasoning:reasoning];
        });
    };
    a.onToolStart = ^(AAMessage *call) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.panel.chat endStreaming];
            [weakSelf.panel.chat reload];
            [weakSelf.panel.chat setStatus:[NSString stringWithFormat:@"%@ …", call.toolName]];
            [weakSelf pulse];
        });
    };
    a.onToolEnd = ^(AAMessage *m) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.panel.chat reload];
            [AAU haptic:m.isError ? 4 : 0];
        });
    };
    a.onStatus = ^(NSString *status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.panel.chat setStatus:status];
        });
    };
    a.onUsage = ^(NSInteger used, NSInteger max) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.panel.chat setUsage:used max:max];
            [weakSelf.panel setUsageProgress:max > 0 ? (double)used / max : 0];
        });
    };
    a.onFinish = ^(NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.panel.chat endStreaming];
            [weakSelf.panel.chat setBusy:NO];
            [weakSelf.panel.chat setStatus:nil];
            [weakSelf.panel.chat reload];
            [weakSelf.panel.history reloadData];
            if (error.length) {
                [AAU haptic:4];
                [AAU toast:error];
            } else {
                [AAU haptic:3];
                [weakSelf pulse];
            }
        });
    };
}

@end
