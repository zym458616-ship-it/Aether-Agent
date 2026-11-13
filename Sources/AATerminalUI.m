//
//  AATerminalUI.m
//  A real terminal: every keystroke runs through posix_spawn in this process.
//

#import "AAUI.h"

@interface AATerminalView () <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *output;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel *cwdLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@property (nonatomic, assign) NSInteger historyIndex;
@property (nonatomic, copy) NSString *cwd;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableString *buffer;
@property (nonatomic, assign) BOOL running;
- (void)emit:(NSString *)fmt, ...;
@end

@implementation AATerminalView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _history = [NSMutableArray array];
        _historyIndex = -1;
        _buffer = [NSMutableString string];
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"AetherTermCWD"];
        _cwd = saved.length ? saved : NSHomeDirectory();
        [self build];
        [self emit:@"Aether Terminal — 真实 shell（posix_spawn）\n"
              "shell: %@\n"
              "cwd:   %@\n"
              "输入 help 查看示例命令。\n\n", [AAExecutor shellPath], _cwd];
    }
    return self;
}

- (void)build {
    // ---- header
    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:bar];

    _cwdLabel = [[UILabel alloc] init];
    _cwdLabel.font = [AAU mono:10.5];
    _cwdLabel.textColor = [AAU textDim];
    _cwdLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    _cwdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_cwdLabel];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"清屏" forState:UIControlStateNormal];
    clear.titleLabel.font = [AAU ui:11];
    [clear setTitleColor:[AAU textDim] forState:UIControlStateNormal];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [clear addTarget:self action:@selector(clear) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:clear];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [AAU accent];
    _spinner.transform = CGAffineTransformMakeScale(0.55, 0.55);
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_spinner];

    // ---- output
    _output = [[UITextView alloc] init];
    _output.translatesAutoresizingMaskIntoConstraints = NO;
    _output.editable = NO;
    _output.selectable = YES;
    _output.backgroundColor = [AAU isDark] ? [UIColor colorWithWhite:0.02 alpha:1] : [UIColor colorWithWhite:0.10 alpha:1];
    _output.textColor = [UIColor colorWithRed:0.82 green:0.88 blue:0.78 alpha:1];
    _output.font = [AAU mono:11];
    _output.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    _output.keyboardAppearance = UIKeyboardAppearanceDark;
    [AAU round:_output radius:12];
    [AAU border:_output color:[[UIColor whiteColor] colorWithAlphaComponent:0.06] width:0.7];
    [self addSubview:_output];

    // ---- quick chips
    UIScrollView *chipScroll = [[UIScrollView alloc] init];
    chipScroll.translatesAutoresizingMaskIntoConstraints = NO;
    chipScroll.showsHorizontalScrollIndicator = NO;
    [self addSubview:chipScroll];

    UIStackView *chips = [[UIStackView alloc] init];
    chips.axis = UILayoutConstraintAxisHorizontal;
    chips.spacing = 6;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    [chipScroll addSubview:chips];

    NSArray *quick = @[@"ls -la", @"ps aux | head -20", @"uname -a", @"df -h", @"id",
                       @"ls /var/jb/usr/bin | head", @"cat /etc/hosts", @"top -l 1 | head -12"];
    for (NSString *q in quick) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:q forState:UIControlStateNormal];
        b.titleLabel.font = [AAU mono:10];
        [b setTitleColor:[AAU textDim] forState:UIControlStateNormal];
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 9, 5, 9);
        b.backgroundColor = [AAU card2];
        [AAU round:b radius:7];
        [b addTarget:self action:@selector(quickTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chips addArrangedSubview:b];
    }

    // ---- input
    UIView *inputBar = [[UIView alloc] init];
    inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    inputBar.backgroundColor = [AAU card];
    [AAU round:inputBar radius:12];
    [AAU border:inputBar color:[AAU stroke] width:0.7];
    [self addSubview:inputBar];

    UILabel *prompt = [[UILabel alloc] init];
    prompt.text = @"❯";
    prompt.font = [AAU mono:14];
    prompt.textColor = [AAU accent];
    prompt.translatesAutoresizingMaskIntoConstraints = NO;
    [inputBar addSubview:prompt];

    _field = [[UITextField alloc] init];
    _field.translatesAutoresizingMaskIntoConstraints = NO;
    _field.font = [AAU mono:12];
    _field.textColor = [AAU text];
    _field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"输入命令…"
        attributes:@{NSForegroundColorAttributeName: [AAU textDim], NSFontAttributeName: [AAU mono:12]}];
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.spellCheckingType = UITextSpellCheckingTypeNo;
    _field.returnKeyType = UIReturnKeyGo;
    _field.delegate = self;
    [inputBar addSubview:_field];

    UIButton *run = [UIButton buttonWithType:UIButtonTypeSystem];
    run.translatesAutoresizingMaskIntoConstraints = NO;
    [run setImage:[UIImage systemImageNamed:@"return"] forState:UIControlStateNormal];
    run.tintColor = [UIColor whiteColor];
    run.backgroundColor = [AAU accent];
    [AAU round:run radius:8];
    [run addTarget:self action:@selector(runCurrent) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:run];

    UIButton *up = [UIButton buttonWithType:UIButtonTypeSystem];
    up.translatesAutoresizingMaskIntoConstraints = NO;
    [up setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    up.tintColor = [AAU textDim];
    [up addTarget:self action:@selector(historyUp) forControlEvents:UIControlEventTouchUpInside];
    [inputBar addSubview:up];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
        [bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [bar.heightAnchor constraintEqualToConstant:20],

        [_cwdLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_cwdLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [_cwdLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_spinner.leadingAnchor constant:-8],

        [_spinner.trailingAnchor constraintEqualToAnchor:clear.leadingAnchor constant:-6],
        [_spinner.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [clear.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [clear.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [_output.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:6],
        [_output.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_output.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [chipScroll.topAnchor constraintEqualToAnchor:_output.bottomAnchor constant:8],
        [chipScroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [chipScroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [chipScroll.heightAnchor constraintEqualToConstant:26],

        [chips.topAnchor constraintEqualToAnchor:chipScroll.topAnchor],
        [chips.bottomAnchor constraintEqualToAnchor:chipScroll.bottomAnchor],
        [chips.leadingAnchor constraintEqualToAnchor:chipScroll.leadingAnchor],
        [chips.trailingAnchor constraintEqualToAnchor:chipScroll.trailingAnchor],
        [chips.heightAnchor constraintEqualToAnchor:chipScroll.heightAnchor],

        [inputBar.topAnchor constraintEqualToAnchor:chipScroll.bottomAnchor constant:8],
        [inputBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [inputBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [inputBar.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [inputBar.heightAnchor constraintEqualToConstant:40],

        [prompt.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:10],
        [prompt.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],

        [_field.leadingAnchor constraintEqualToAnchor:prompt.trailingAnchor constant:6],
        [_field.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [_field.trailingAnchor constraintEqualToAnchor:up.leadingAnchor constant:-6],

        [up.trailingAnchor constraintEqualToAnchor:run.leadingAnchor constant:-4],
        [up.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [up.widthAnchor constraintEqualToConstant:22],

        [run.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-6],
        [run.centerYAnchor constraintEqualToAnchor:inputBar.centerYAnchor],
        [run.widthAnchor constraintEqualToConstant:30],
        [run.heightAnchor constraintEqualToConstant:28],
    ]];
}

#pragma mark actions

- (void)quickTapped:(UIButton *)b {
    self.field.text = [b titleForState:UIControlStateNormal];
    [self runCurrent];
}

- (void)historyUp {
    if (!self.history.count) return;
    if (self.historyIndex < 0) self.historyIndex = (NSInteger)self.history.count - 1;
    else if (self.historyIndex > 0) self.historyIndex--;
    self.field.text = self.history[self.historyIndex];
    [AAU haptic:0];
}

- (void)runCurrent {
    NSString *cmd = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!cmd.length) return;
    self.field.text = @"";
    [self.history addObject:cmd];
    self.historyIndex = -1;
    [self execute:cmd];
}

- (void)execute:(NSString *)cmd {
    if (self.running) {
        [AAU toast:@"上一条命令还在执行"];
        return;
    }
    [self emit:@"❯ %@\n", cmd];

    // cd is handled in-process so the terminal keeps a stable working directory.
    if ([cmd hasPrefix:@"cd "] || [cmd isEqualToString:@"cd"]) {
        NSString *target = [cmd isEqualToString:@"cd"] ? NSHomeDirectory() : [cmd substringFromIndex:3];
        target = [target stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        target = [target stringByReplacingOccurrencesOfString:@"~" withString:NSHomeDirectory()];
        if (![target hasPrefix:@"/"]) target = [self.cwd stringByAppendingPathComponent:target];
        target = [target stringByStandardizingPath];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&isDir] && isDir) {
            self.cwd = target;
            [[NSUserDefaults standardUserDefaults] setObject:target forKey:@"AetherTermCWD"];
            self.cwdLabel.text = [AAU shortPath:target];
            [self emit:@"→ %@\n\n", target];
        } else {
            [self emit:@"cd: 没有这个目录: %@\n\n", target];
        }
        return;
    }
    if ([cmd isEqualToString:@"clear"] || [cmd isEqualToString:@"cls"]) { [self clear]; return; }
    if ([cmd isEqualToString:@"help"]) {
        [self emit:@"示例：\n"
                "  ls -la                     列出当前目录\n"
                "  ls /var/jb/usr/bin        越狱工具目录\n"
                "  cat /etc/hosts            读取文件\n"
                "  ps aux                    进程列表\n"
                "  id                        当前用户\n"
                "  cd <dir>                  切换目录\n"
                "  clear                     清屏\n\n"];
        return;
    }

    self.running = YES;
    self.field.enabled = NO;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [AAExecutor run:cmd cwd:self.cwd timeout:90 onData:^(NSString *chunk) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf emit:@"%@", chunk]; });
    } onExit:^(int status, BOOL timedOut) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        self_.running = NO;
        self_.field.enabled = YES;
        [self_.spinner stopAnimating];
        if (status != 0 || timedOut) [self_ emit:@"\n[退出码 %d%@]\n\n", status, timedOut ? @" 超时" : @""];
        else [self_ emit:@"\n"];
    }];
}

- (void)clear {
    self.output.text = @"";
}

- (void)emit:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.output.text = [self.output.text stringByAppendingString:s ?: @""];
        if (self.output.text.length > 200000) {
            self.output.text = [self.output.text substringFromIndex:self.output.text.length - 120000];
        }
        [self.output scrollRangeToVisible:NSMakeRange(self.output.text.length, 0)];
    });
}

- (void)focusInput {
    [self.field becomeFirstResponder];
}

#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self runCurrent];
    return NO;
}

@end
