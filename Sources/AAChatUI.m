//
//  AAChatUI.m
//  Chat surface: markdown-lite bubbles, tool cards, streaming, composer.
//

#import "AAUI.h"

#pragma mark - Markdown-lite

static NSMutableAttributedString *AAInline(NSString *line, UIFont *base, UIColor *color) {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:@""];
    NSUInteger i = 0;
    NSUInteger len = line.length;
    UIFont *boldFont = [UIFont systemFontOfSize:base.pointSize weight:UIFontWeightSemibold];
    UIFont *monoFont = [AAU mono:base.pointSize - 0.5];

    while (i < len) {
        unichar c = [line characterAtIndex:i];
        // **bold**
        if (c == '*' && i + 1 < len && [line characterAtIndex:i + 1] == '*') {
            NSRange r = [line rangeOfString:@"**" options:0 range:NSMakeRange(i + 2, len - i - 2)];
            if (r.location != NSNotFound) {
                NSString *inner = [line substringWithRange:NSMakeRange(i + 2, r.location - i - 2)];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:inner
                    attributes:@{NSFontAttributeName: boldFont, NSForegroundColorAttributeName: color}]];
                i = r.location + 2;
                continue;
            }
        }
        // `code`
        if (c == '`') {
            NSRange r = [line rangeOfString:@"`" options:0 range:NSMakeRange(i + 1, len - i - 1)];
            if (r.location != NSNotFound) {
                NSString *inner = [line substringWithRange:NSMakeRange(i + 1, r.location - i - 1)];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:inner
                    attributes:@{NSFontAttributeName: monoFont,
                                 NSForegroundColorAttributeName: [AAU accent],
                                 NSBackgroundColorAttributeName: [[AAU card2] colorWithAlphaComponent:0.7]}]];
                i = r.location + 1;
                continue;
            }
        }
        // plain run until next special char
        NSUInteger j = i;
        while (j < len) {
            unichar ch = [line characterAtIndex:j];
            if (ch == '*' || ch == '`') break;
            j++;
        }
        if (j == i) j = i + 1;
        NSString *plain = [line substringWithRange:NSMakeRange(i, j - i)];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:plain
            attributes:@{NSFontAttributeName: base, NSForegroundColorAttributeName: color}]];
        i = j;
    }
    return out;
}

NSAttributedString *AARenderMarkdown(NSString *text, CGFloat size, UIColor *color) {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if (!text.length) return out;

    UIFont *base = [AAU ui:size];
    UIFont *mono = [AAU mono:size - 1];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 2.5;
    ps.paragraphSpacing = 3;

    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    BOOL inCode = NO;
    BOOL firstLine = YES;

    for (NSString *line in lines) {
        NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trim hasPrefix:@"```"]) {
            inCode = !inCode;
            if (inCode) {
                NSString *lang = [trim stringByReplacingOccurrencesOfString:@"```" withString:@""];
                if (lang.length) {
                    NSMutableAttributedString *tag = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@\n", lang]
                        attributes:@{NSFontAttributeName: [AAU mono:9.5],
                                     NSForegroundColorAttributeName: [AAU textDim]}];
                    [out appendAttributedString:tag];
                }
            }
            continue;
        }
        if (inCode) {
            NSString *l = [line stringByAppendingString:@"\n"];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:l attributes:@{
                NSFontAttributeName: mono,
                NSForegroundColorAttributeName: [AAU isDark] ? [UIColor colorWithRed:0.78 green:0.85 blue:0.95 alpha:1] : [UIColor colorWithRed:0.15 green:0.22 blue:0.32 alpha:1],
                NSBackgroundColorAttributeName: [[AAU card2] colorWithAlphaComponent:0.85],
                NSParagraphStyleAttributeName: ps,
            }]];
            continue;
        }

        // headings
        if ([trim hasPrefix:@"### "] || [trim hasPrefix:@"## "] || [trim hasPrefix:@"# "]) {
            NSUInteger hashes = [trim hasPrefix:@"### "] ? 3 : ([trim hasPrefix:@"## "] ? 2 : 1);
            NSString *body = [trim substringFromIndex:hashes + 1];
            NSMutableAttributedString *h = [[NSMutableAttributedString alloc] initWithString:body
                attributes:@{NSFontAttributeName: [AAU ui:size + (hashes == 1 ? 2 : 0.5) weight:UIFontWeightBold],
                             NSForegroundColorAttributeName: color,
                             NSParagraphStyleAttributeName: ps}];
            if (!firstLine) [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            [out appendAttributedString:h];
            firstLine = NO;
            continue;
        }

        NSMutableAttributedString *l = AAInline(line, base, color);
        [l addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, l.length)];
        [out appendAttributedString:l];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: base}]];
        firstLine = NO;
    }
    // trim trailing newline
    if (out.length) {
        NSRange last = NSMakeRange(out.length - 1, 1);
        if ([[out.string substringWithRange:last] isEqualToString:@"\n"]) [out deleteCharactersInRange:last];
    }
    return out;
}

static NSString *AAStripImageMarker(NSString *s) {
    NSRange r1 = [s rangeOfString:@"<<IMG:"];
    if (r1.location == NSNotFound) return s;
    NSRange r2 = [s rangeOfString:@">>" options:0 range:NSMakeRange(r1.location, s.length - r1.location)];
    if (r2.location == NSNotFound) return s;
    return [[s stringByReplacingCharactersInRange:NSMakeRange(r1.location, r2.location + 2 - r1.location) withString:@"📎 已附带当前界面截图"]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Message views

@interface AAUserBubble : UIView
@property (nonatomic, strong) UILabel *label;
- (void)configure:(NSString *)text;
@end

@implementation AAUserBubble

- (instancetype)init {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *bubble = [[UIView alloc] init];
        bubble.translatesAutoresizingMaskIntoConstraints = NO;
        bubble.backgroundColor = [[AAU accent] colorWithAlphaComponent:0.16];
        [AAU round:bubble radius:14];
        [AAU border:bubble color:[[AAU accent] colorWithAlphaComponent:0.28] width:0.7];
        [self addSubview:bubble];

        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [AAU ui:14];
        _label.textColor = [AAU text];
        [bubble addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [bubble.topAnchor constraintEqualToAnchor:self.topAnchor],
            [bubble.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [bubble.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:48],
            [_label.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:9],
            [_label.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-9],
            [_label.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12],
            [_label.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)configure:(NSString *)text {
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 2;
    self.label.attributedText = [[NSAttributedString alloc] initWithString:AAStripImageMarker(text ?: @"")
        attributes:@{NSFontAttributeName: [AAU ui:14], NSForegroundColorAttributeName: [AAU text], NSParagraphStyleAttributeName: ps}];
}

@end

@interface AAAssistantBubble : UIView
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UILabel *reasoning;
- (void)configure:(NSString *)text reasoning:(NSString *)reasoning;
- (void)setStreaming:(BOOL)streaming;
@end

@implementation AAAssistantBubble

- (instancetype)init {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _reasoning = [[UILabel alloc] init];
        _reasoning.numberOfLines = 0;
        _reasoning.font = [AAU ui:11.5];
        _reasoning.textColor = [AAU textDim];
        _reasoning.translatesAutoresizingMaskIntoConstraints = NO;

        _body = [[UILabel alloc] init];
        _body.numberOfLines = 0;
        _body.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_reasoning, _body]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],
        ]];
    }
    return self;
}

- (void)configure:(NSString *)text reasoning:(NSString *)reasoning {
    BOOL showReasoning = reasoning.length && [AAConfig shared].showReasoning;
    self.reasoning.hidden = !showReasoning;
    if (showReasoning) {
        self.reasoning.text = [NSString stringWithFormat:@"💭 %@", reasoning];
    }
    self.body.attributedText = AARenderMarkdown(AAStripImageMarker(text ?: @""), 14.5, [AAU text]);
}

- (void)setStreaming:(BOOL)streaming {
    self.body.alpha = 1.0;
}

@end

@interface AAToolCard : UIView
@property (nonatomic, strong) UIView *head;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *argsLabel;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) UIView *resultBox;
@property (nonatomic, assign) BOOL expanded;
@end

@implementation AAToolCard

- (instancetype)init {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [AAU card];
        [AAU round:self radius:12];
        [AAU border:self color:[AAU stroke] width:0.7];

        _head = [[UIView alloc] init];
        _head.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_head];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [AAU mono:12];
        _nameLabel.textColor = [AAU text];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_head addSubview:_nameLabel];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [AAU ui:10.5 weight:UIFontWeightMedium];
        _statusLabel.textColor = [AAU textDim];
        _statusLabel.textAlignment = NSTextAlignmentRight;
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_head addSubview:_statusLabel];

        _argsLabel = [[UILabel alloc] init];
        _argsLabel.numberOfLines = 4;
        _argsLabel.font = [AAU mono:10.5];
        _argsLabel.textColor = [AAU textDim];
        _argsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_argsLabel];

        _resultBox = [[UIView alloc] init];
        _resultBox.backgroundColor = [AAU card2];
        _resultBox.translatesAutoresizingMaskIntoConstraints = NO;
        [AAU round:_resultBox radius:8];
        [self addSubview:_resultBox];

        _resultLabel = [[UILabel alloc] init];
        _resultLabel.numberOfLines = 0;
        _resultLabel.font = [AAU mono:10.5];
        _resultLabel.textColor = [AAU textDim];
        _resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_resultBox addSubview:_resultLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_head.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_head.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_head.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_head.heightAnchor constraintEqualToConstant:18],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_head.leadingAnchor],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:_head.centerYAnchor],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:_head.trailingAnchor],
            [_statusLabel.centerYAnchor constraintEqualToAnchor:_head.centerYAnchor],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-8],

            [_argsLabel.topAnchor constraintEqualToAnchor:_head.bottomAnchor constant:6],
            [_argsLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_argsLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

            [_resultBox.topAnchor constraintEqualToAnchor:_argsLabel.bottomAnchor constant:6],
            [_resultBox.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_resultBox.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_resultBox.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],

            [_resultLabel.topAnchor constraintEqualToAnchor:_resultBox.topAnchor constant:7],
            [_resultLabel.bottomAnchor constraintEqualToAnchor:_resultBox.bottomAnchor constant:-7],
            [_resultLabel.leadingAnchor constraintEqualToAnchor:_resultBox.leadingAnchor constant:8],
            [_resultLabel.trailingAnchor constraintEqualToAnchor:_resultBox.trailingAnchor constant:-8],
        ]];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        [self addGestureRecognizer:tap];
        _expanded = NO;
    }
    return self;
}

- (void)configureName:(NSString *)name args:(NSString *)args result:(NSString *)result error:(BOOL)error running:(BOOL)running {
    self.nameLabel.text = [NSString stringWithFormat:@"⚙︎ %@", name ?: @"tool"];
    self.nameLabel.textColor = running ? [AAU warn] : [AAU colorForTool:name ?: @""];

    if (running) {
        self.statusLabel.text = @"运行中";
        self.statusLabel.textColor = [AAU warn];
    } else if (result.length) {
        self.statusLabel.text = error ? @"失败" : @"完成";
        self.statusLabel.textColor = error ? [AAU err] : [AAU ok];
    } else {
        self.statusLabel.text = @"排队";
        self.statusLabel.textColor = [AAU textDim];
    }

    NSString *pretty = args ?: @"{}";
    pretty = [pretty stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (pretty.length > 220) pretty = [[pretty substringToIndex:220] stringByAppendingString:@"…"];
    self.argsLabel.text = pretty;
    self.argsLabel.hidden = (pretty.length <= 2);

    self.resultBox.hidden = !result.length;
    if (result.length) {
        NSString *r = self.expanded ? result : [self previewOf:result];
        self.resultLabel.text = r;
        self.resultLabel.textColor = error ? [AAU err] : [AAU textDim];
    }
    [self setNeedsLayout];
}

- (NSString *)previewOf:(NSString *)r {
    if (self.expanded || r.length <= 340) return r;
    return [[r substringToIndex:340] stringByAppendingString:@"\n… (点击展开)"];
}

- (void)toggle {
    self.expanded = !self.expanded;
    if (self.resultLabel.text.length) {
        NSString *full = self.resultLabel.text;
        if (!self.expanded) {
            self.resultLabel.text = [self previewOf:full];
        } else {
            self.resultLabel.text = full;
        }
    }
    [AAU haptic:0];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AetherLayoutChanged" object:nil];
}

@end

@interface AAStatusPill : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation AAStatusPill

- (instancetype)init {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [[AAU accent] colorWithAlphaComponent:0.12];
        [AAU round:self radius:11];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.color = [AAU accent];
        _spinner.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [self addSubview:_spinner];

        _label = [[UILabel alloc] init];
        _label.font = [AAU ui:11 weight:UIFontWeightMedium];
        _label.textColor = [AAU accent];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_spinner.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:5],
            [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_spinner.widthAnchor constraintEqualToConstant:16],
            [_label.leadingAnchor constraintEqualToAnchor:_spinner.trailingAnchor constant:2],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-9],
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        ]];
    }
    return self;
}

@end

#pragma mark - Chat view

@interface AAChatView () <UITextViewDelegate> {
    BOOL _withShot;
    BOOL _busy;
    BOOL _streaming;
}
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) AAAssistantBubble *liveBubble;
@property (nonatomic, strong) NSMutableString *liveText;
@property (nonatomic, strong) NSMutableString *liveReasoning;
@property (nonatomic, strong) AAStatusPill *statusPill;
@property (nonatomic, strong) UILabel *usageLabel;

@property (nonatomic, strong) UIView *composer;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *sendBtn;
@property (nonatomic, strong) UIButton *shotBtn;
@property (nonatomic, strong) NSLayoutConstraint *inputHeight;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic, strong) UIView *emptyState;
@end

@implementation AAChatView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _liveText = [NSMutableString string];
        _liveReasoning = [NSMutableString string];
        [self buildScroll];
        [self buildComposer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutChanged)
                                                     name:@"AetherLayoutChanged" object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildScroll {
    _scroll = [[UIScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _scroll.showsVerticalScrollIndicator = NO;
    [self addSubview:_scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 12;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:14],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-14],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.leadingAnchor constant:14],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.trailingAnchor constant:-14],
    ]];
}

- (void)buildComposer {
    _composer = [[UIView alloc] init];
    _composer.translatesAutoresizingMaskIntoConstraints = NO;
    _composer.backgroundColor = [[AAU card] colorWithAlphaComponent:0.92];
    [AAU round:_composer radius:18];
    [AAU border:_composer color:[AAU stroke] width:0.7];
    [self addSubview:_composer];

    _input = [[UITextView alloc] init];
    _input.translatesAutoresizingMaskIntoConstraints = NO;
    _input.backgroundColor = [UIColor clearColor];
    _input.font = [AAU ui:14];
    _input.textColor = [AAU text];
    _input.delegate = self;
    _input.textContainerInset = UIEdgeInsetsMake(9, 4, 9, 4);
    _input.scrollEnabled = YES;
    _input.returnKeyType = UIReturnKeyDefault;
    _input.keyboardAppearance = [AAU isDark] ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    [_composer addSubview:_input];

    _placeholder = [[UILabel alloc] init];
    _placeholder.text = @"描述任务，Aether 会在 App 内执行…";
    _placeholder.font = [AAU ui:14];
    _placeholder.textColor = [AAU textDim];
    _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholder.userInteractionEnabled = NO;
    [_composer addSubview:_placeholder];

    _shotBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _shotBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *cam = [UIImage systemImageNamed:@"camera"];
    [_shotBtn setImage:cam forState:UIControlStateNormal];
    _shotBtn.tintColor = [AAU textDim];
    [_shotBtn addTarget:self action:@selector(toggleShot) forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_shotBtn];

    _sendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _sendBtn.backgroundColor = [AAU accent];
    [AAU round:_sendBtn radius:15];
    UIImage *arrow = [UIImage systemImageNamed:@"arrow.up"];
    [_sendBtn setImage:arrow forState:UIControlStateNormal];
    _sendBtn.tintColor = [UIColor whiteColor];
    [_sendBtn addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_sendBtn];

    _statusPill = [[AAStatusPill alloc] init];
    _statusPill.hidden = YES;
    [self addSubview:_statusPill];

    _usageLabel = [[UILabel alloc] init];
    _usageLabel.font = [AAU mono:9.5];
    _usageLabel.textColor = [AAU textDim];
    _usageLabel.textAlignment = NSTextAlignmentRight;
    _usageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_usageLabel];

    _inputHeight = [_input.heightAnchor constraintEqualToConstant:34];

    [NSLayoutConstraint activateConstraints:@[
        [_composer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_composer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_composer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [_composer.topAnchor constraintGreaterThanOrEqualToAnchor:_scroll.bottomAnchor constant:0],

        [_input.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:8],
        [_input.topAnchor constraintEqualToAnchor:_composer.topAnchor constant:4],
        [_input.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-4],
        _inputHeight,

        [_placeholder.leadingAnchor constraintEqualToAnchor:_input.leadingAnchor constant:8],
        [_placeholder.topAnchor constraintEqualToAnchor:_input.topAnchor constant:9],

        [_shotBtn.leadingAnchor constraintEqualToAnchor:_input.trailingAnchor constant:2],
        [_shotBtn.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-9],
        [_shotBtn.widthAnchor constraintEqualToConstant:26],
        [_shotBtn.heightAnchor constraintEqualToConstant:26],

        [_sendBtn.leadingAnchor constraintEqualToAnchor:_shotBtn.trailingAnchor constant:6],
        [_sendBtn.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-7],
        [_sendBtn.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-6],
        [_sendBtn.widthAnchor constraintEqualToConstant:30],
        [_sendBtn.heightAnchor constraintEqualToConstant:30],

        [_statusPill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_statusPill.bottomAnchor constraintEqualToAnchor:_composer.topAnchor constant:-8],

        [_usageLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_usageLabel.centerYAnchor constraintEqualToAnchor:_statusPill.centerYAnchor],
    ]];

    _composer.layer.shadowColor = [UIColor blackColor].CGColor;
    _composer.layer.shadowOpacity = 0.12;
    _composer.layer.shadowRadius = 10;
    _composer.layer.shadowOffset = CGSizeMake(0, 3);
}

#pragma mark lifecycle

- (void)layoutChanged {
    [UIView animateWithDuration:0.2 animations:^{ [self.superview layoutIfNeeded]; }];
}

#pragma mark reload

- (void)clearStack {
    for (UIView *v in self.stack.arrangedSubviews) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.liveBubble = nil;
}

- (void)showEmptyState {
    [self clearStack];
    if (!_emptyState) {
        _emptyState = [[UIView alloc] init];
        _emptyState.translatesAutoresizingMaskIntoConstraints = NO;

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
        icon.tintColor = [AAU accent];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *title = [[UILabel alloc] init];
        title.text = @"Aether";
        title.font = [AAU ui:22 weight:UIFontWeightBold];
        title.textColor = [AAU text];
        title.textAlignment = NSTextAlignmentCenter;
        title.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *sub = [[UILabel alloc] init];
        sub.text = @"一个跑在 App 里的全权限智能体\n描述任务，它会自己看界面、点按、敲命令";
        sub.numberOfLines = 0;
        sub.font = [AAU ui:12.5];
        sub.textColor = [AAU textDim];
        sub.textAlignment = NSTextAlignmentCenter;
        sub.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, sub]];
        col.axis = UILayoutConstraintAxisVertical;
        col.alignment = UIStackViewAlignmentCenter;
        col.spacing = 8;
        col.translatesAutoresizingMaskIntoConstraints = NO;
        [_emptyState addSubview:col];

        NSArray *examples = @[@"看看当前界面并告诉我这是什么页面",
                              @"帮我把设置里的深色模式打开",
                              @"列出 App 容器里最大的 10 个文件"];
        UIStackView *chips = [[UIStackView alloc] init];
        chips.axis = UILayoutConstraintAxisVertical;
        chips.spacing = 7;
        chips.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSString *ex in examples) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            [b setTitle:ex forState:UIControlStateNormal];
            b.titleLabel.font = [AAU ui:11.5];
            b.titleLabel.numberOfLines = 1;
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            [b setTitleColor:[AAU textDim] forState:UIControlStateNormal];
            b.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
            b.backgroundColor = [AAU card2];
            [AAU round:b radius:10];
            [b addTarget:self action:@selector(exampleTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chips addArrangedSubview:b];
        }

        [self.stack addArrangedSubview:_emptyState];
        [self.stack addArrangedSubview:chips];
        [NSLayoutConstraint activateConstraints:@[
            [col.topAnchor constraintEqualToAnchor:_emptyState.topAnchor constant:26],
            [col.leadingAnchor constraintEqualToAnchor:_emptyState.leadingAnchor],
            [col.trailingAnchor constraintEqualToAnchor:_emptyState.trailingAnchor],
            [col.bottomAnchor constraintEqualToAnchor:_emptyState.bottomAnchor],
            [icon.widthAnchor constraintEqualToConstant:34],
            [icon.heightAnchor constraintEqualToConstant:34],
        ]];
    } else {
        [self.stack addArrangedSubview:_emptyState];
    }
    [self scrollToBottom];
}

- (void)exampleTapped:(UIButton *)b {
    self.input.text = [b titleForState:UIControlStateNormal];
    self.placeholder.hidden = YES;
    [self textViewDidChange:self.input];
    [AAU haptic:0];
}

- (void)reload {
    NSString *sid = [AAConfig shared].lastSessionID;
    NSArray *msgs = sid.length ? [[AAStore shared] messages:sid] : @[];
    [self clearStack];
    if (!msgs.count) {
        [self showEmptyState];
        return;
    }
    for (NSUInteger i = 0; i < msgs.count; i++) {
        AAMessage *m = msgs[i];
        if ([m.role isEqualToString:@"system"]) continue;

        if ([m.role isEqualToString:@"user"]) {
            AAUserBubble *b = [[AAUserBubble alloc] init];
            [b configure:m.content];
            [self.stack addArrangedSubview:b];
            continue;
        }
        if ([m.role isEqualToString:@"assistant"] && m.isToolCall) {
            NSString *result = nil;
            BOOL err = NO;
            BOOL running = YES;
            for (NSUInteger j = i + 1; j < msgs.count; j++) {
                AAMessage *n = msgs[j];
                if ([n.role isEqualToString:@"tool"] && [n.toolCallId isEqualToString:m.toolCallId]) {
                    result = n.toolResult;
                    err = n.isError;
                    running = NO;
                    break;
                }
            }
            if (m.content.length) {
                AAAssistantBubble *ab = [[AAssistantBubble alloc] init];
                [ab configure:m.content reasoning:m.reasoning];
                [self.stack addArrangedSubview:ab];
            }
            AAToolCard *card = [[AAToolCard alloc] init];
            [card configureName:m.toolName args:m.toolArgs result:result error:err running:running];
            [self.stack addArrangedSubview:card];
            continue;
        }
        if ([m.role isEqualToString:@"assistant"]) {
            if (!m.content.length) continue;
            AAAssistantBubble *b = [[AAssistantBubble alloc] init];
            [b configure:m.content reasoning:m.reasoning];
            [self.stack addArrangedSubview:b];
            continue;
        }
        if ([m.role isEqualToString:@"tool"]) {
            // Orphan tool result (its call scrolled out of the window) — skip.
            continue;
        }
    }
    [self scrollToBottom];
}

#pragma mark streaming

- (void)beginStreaming {
    [self endStreaming];
    _streaming = YES;
    self.liveText = [NSMutableString string];
    self.liveReasoning = [NSMutableString string];
    if (self.stack.arrangedSubviews.count == 1 && self.stack.arrangedSubviews.firstObject == _emptyState) {
        [self clearStack];
    }
    self.liveBubble = [[AAAssistantBubble alloc] init];
    [self.liveBubble configure:@"…" reasoning:nil];
    [self.stack addArrangedSubview:self.liveBubble];
    [self scrollToBottom];
}

- (void)appendStream:(NSString *)text reasoning:(NSString *)reasoning {
    if (!_streaming) [self beginStreaming];
    if (text.length) [self.liveText appendString:text];
    if (reasoning.length) [self.liveReasoning appendString:reasoning];
    if (!self.liveBubble) return;
    [self.liveBubble configure:self.liveText reasoning:self.liveReasoning];
    [self scrollToBottom];
}

- (void)endStreaming {
    if (self.liveBubble) {
        [self.liveBubble removeFromSuperview];
        self.liveBubble = nil;
    }
    _streaming = NO;
    [self.liveText setString:@""];
    [self.liveReasoning setString:@""];
}

- (void)scrollToBottom {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self layoutIfNeeded];
        CGFloat h = self.scroll.contentSize.height;
        CGFloat vh = self.scroll.bounds.size.height;
        if (h > vh) {
            [self.scroll setContentOffset:CGPointMake(0, h - vh + self.scroll.contentInset.bottom) animated:YES];
        }
    });
}

#pragma mark status / usage

- (void)setStatus:(NSString *)status {
    if (!status.length) {
        self.statusPill.hidden = YES;
        [self.statusPill.spinner stopAnimating];
        return;
    }
    self.statusPill.hidden = NO;
    self.statusPill.label.text = status;
    [self.statusPill.spinner startAnimating];
}

- (void)setUsage:(NSInteger)used max:(NSInteger)max {
    if (max <= 0) { self.usageLabel.text = @""; return; }
    double pct = MIN(100.0, used * 100.0 / max);
    NSString *fmt = used >= 1000 ? [NSString stringWithFormat:@"%.1fk / %.0fk", used / 1000.0, max / 1000.0]
                                 : [NSString stringWithFormat:@"%ld / %ld", (long)used, (long)max];
    self.usageLabel.text = [NSString stringWithFormat:@"context %.0f%% · %@", pct, fmt];
    self.usageLabel.textColor = pct > 85 ? [AAU err] : (pct > 65 ? [AAU warn] : [AAU textDim]);
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    UIImage *img = [UIImage systemImageNamed:busy ? @"stop.fill" : @"arrow.up"];
    [self.sendBtn setImage:img forState:UIControlStateNormal];
    self.sendBtn.backgroundColor = busy ? [AAU err] : [AAU accent];
}

#pragma mark composer actions

- (void)toggleShot {
    _withShot = !_withShot;
    self.shotBtn.tintColor = _withShot ? [AAU accent] : [AAU textDim];
    self.shotBtn.backgroundColor = _withShot ? [[AAU accent] colorWithAlphaComponent:0.15] : [UIColor clearColor];
    [AAU round:self.shotBtn radius:7];
    [AAU haptic:0];
    [AAU toast:_withShot ? @"发送时将附带当前界面截图" : @"已取消附带截图"];
}

- (void)sendTapped {
    if (_busy) {
        if (self.onStop) self.onStop();
        return;
    }
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) [AAU haptic:4], [AAU toast:@"先写点任务内容"];
    if (!text.length) return;

    BOOL shot = _withShot;
    if (shot) {
        NSString *path = [[[AAU dataDir] stringByAppendingPathComponent:@"shots"]
                          stringByAppendingPathComponent:[NSString stringWithFormat:@"shot-%.0f.jpg", [[NSDate date] timeIntervalSince1970]]];
        if ([[AAUIBridge shared] saveScreenshot:path]) {
            text = [text stringByAppendingFormat:@"\n<<IMG:%@>>", path];
        }
        _withShot = NO;
        self.shotBtn.tintColor = [AAU textDim];
        self.shotBtn.backgroundColor = [UIColor clearColor];
    }

    self.input.text = @"";
    self.placeholder.hidden = NO;
    self.inputHeight.constant = 34;
    if (self.onSend) self.onSend(text, shot);
    [AAU haptic:1];
}

#pragma mark UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholder.hidden = textView.text.length > 0;
    CGFloat h = [textView sizeThatFits:CGSizeMake(textView.bounds.size.width, 1000)].height;
    CGFloat clamped = MAX(34, MIN(120, h));
    if (fabs(clamped - self.inputHeight.constant) > 1) {
        self.inputHeight.constant = clamped;
        [UIView animateWithDuration:0.15 animations:^{ [self layoutIfNeeded]; }];
    }
}

@end
