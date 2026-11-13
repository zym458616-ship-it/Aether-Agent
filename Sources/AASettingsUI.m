//
//  AASettingsUI.m
//  Settings surface + task history list.
//

#import "AAUI.h"

#pragma mark - Small builders

static UIView *AACardView(void) {
    UIView *v = [[UIView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = [AAU card];
    [AAU round:v radius:14];
    [AAU border:v color:[AAU stroke] width:0.7];
    return v;
}

static UILabel *AASectionLabel(NSString *text) {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [AAU ui:10.5 weight:UIFontWeightSemibold];
    l.textColor = [AAU textDim];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

static UITextField *AAField(NSString *placeholder, NSString *text, BOOL secure) {
    UITextField *f = [[UITextField alloc] init];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.text = text;
    f.placeholder = placeholder;
    f.secureTextEntry = secure;
    f.font = [AAU mono:11.5];
    f.textColor = [AAU text];
    f.backgroundColor = [AAU card2];
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.keyboardType = UIKeyboardTypeURL;
    f.returnKeyType = UIReturnKeyDone;
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    f.leftViewMode = UITextFieldViewModeAlways;
    f.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    f.rightViewMode = UITextFieldViewModeAlways;
    [AAU round:f radius:9];
    [f.heightAnchor constraintEqualToConstant:34].active = YES;
    return f;
}

#pragma mark - Settings

@interface AASettingsView () <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UITextField *baseField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *ctxLabel;
@property (nonatomic, strong) UILabel *stepLabel;
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UITextView *promptView;
@property (nonatomic, assign) NSInteger ctxIndex;
@property (nonatomic, strong) NSArray *ctxOptions;
@end

@implementation AASettingsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _ctxOptions = @[@0, @8192, @16384, @32768, @65536, @128000, @200000, @1048576];
        [self build];
        [self reloadUI];
    }
    return self;
}

- (void)build {
    _scroll = [[UIScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self addSubview:_scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 8;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:10],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.leadingAnchor constant:14],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.trailingAnchor constant:-14],
    ]];
}

- (UIView *)cardWithRows:(NSArray<UIView *> *)rows {
    UIView *card = AACardView();
    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:rows];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 8;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:col];
    [NSLayoutConstraint activateConstraints:@[
        [col.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [col.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [col.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [col.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
    ]];
    return card;
}

- (UIView *)separator {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [AAU stroke];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [v.heightAnchor constraintEqualToConstant:0.7].active = YES;
    return v;
}

- (UIView *)row:(NSString *)title subtitle:(NSString *)subtitle accessory:(UIView *)accessory {
    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [AAU ui:13];
    t.textColor = [AAU text];

    UILabel *s = nil;
    if (subtitle.length) {
        s = [[UILabel alloc] init];
        s.text = subtitle;
        s.font = [AAU ui:10.5];
        s.textColor = [AAU textDim];
        s.numberOfLines = 0;
    }
    UIStackView *left = [[UIStackView alloc] init];
    left.axis = UILayoutConstraintAxisVertical;
    left.spacing = 2;
    [left addArrangedSubview:t];
    if (s) [left addArrangedSubview:s];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, accessory ?: [[UIView alloc] init]]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 10;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

- (UIView *)toggleRow:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on action:(SEL)action {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    sw.transform = CGAffineTransformMakeScale(0.78, 0.78);
    sw.onTintColor = [AAU accent];
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return [self row:title subtitle:subtitle accessory:sw];
}

- (UIButton *)smallButton:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [AAU ui:11.5 weight:UIFontWeightMedium];
    [b setTitleColor:[AAU accent] forState:UIControlStateNormal];
    b.backgroundColor = [[AAU accent] colorWithAlphaComponent:0.12];
    b.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [AAU round:b radius:8];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)stepperRow:(NSString *)title valueLabel:(UILabel *)valueLabel action:(SEL)action {
    UIButton *minus = [UIButton buttonWithType:UIButtonTypeSystem];
    [minus setTitle:@"−" forState:UIControlStateNormal];
    [minus setTitleColor:[AAU text] forState:UIControlStateNormal];
    minus.titleLabel.font = [AAU ui:16 weight:UIFontWeightMedium];
    minus.tag = -1;
    [minus addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    minus.backgroundColor = [AAU card2];
    [AAU round:minus radius:7];
    [minus.widthAnchor constraintEqualToConstant:30].active = YES;
    [minus.heightAnchor constraintEqualToConstant:28].active = YES;

    UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
    [plus setTitle:@"+" forState:UIControlStateNormal];
    [plus setTitleColor:[AAU text] forState:UIControlStateNormal];
    plus.titleLabel.font = [AAU ui:16 weight:UIFontWeightMedium];
    plus.tag = 1;
    [plus addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    plus.backgroundColor = [AAU card2];
    [AAU round:plus radius:7];
    [plus.widthAnchor constraintEqualToConstant:30].active = YES;
    [plus.heightAnchor constraintEqualToConstant:28].active = YES;

    valueLabel.font = [AAU mono:11];
    valueLabel.textColor = [AAU accent];
    valueLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *acc = [[UIStackView alloc] initWithArrangedSubviews:@[minus, valueLabel, plus]];
    acc.axis = UILayoutConstraintAxisHorizontal;
    acc.spacing = 8;
    acc.alignment = UIStackViewAlignmentCenter;
    [valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    return [self row:title subtitle:nil accessory:acc];
}

#pragma mark build content

- (void)reloadUI {
    for (UIView *v in self.stack.arrangedSubviews) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    AAConfig *cfg = [AAConfig shared];

    // ---------- provider
    [self.stack addArrangedSubview:AASectionLabel(@"模型接入")];

    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"OpenAI 兼容", @"Anthropic"]];
    seg.selectedSegmentIndex = [cfg.provider isEqualToString:@"anthropic"] ? 1 : 0;
    seg.translatesAutoresizingMaskIntoConstraints = NO;
    [seg addTarget:self action:@selector(providerChanged:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        seg.selectedSegmentTintColor = [AAU accent];
        [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
        [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [AAU textDim]} forState:UIControlStateNormal];
    }

    _baseField = AAField(@"https://api.openai.com", cfg.baseURL, NO);
    _baseField.delegate = self;
    _baseField.tag = 1;
    [_baseField addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];

    _keyField = AAField(@"sk-…", cfg.apiKey, YES);
    _keyField.delegate = self;
    _keyField.tag = 2;
    _keyField.keyboardType = UIKeyboardTypeDefault;
    [_keyField addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];

    UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
    [eye setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal];
    eye.tintColor = [AAU textDim];
    eye.tag = 99;
    [eye addTarget:self action:@selector(toggleKeyVisible:) forControlEvents:UIControlEventTouchUpInside];
    _keyField.rightView = eye;
    _keyField.rightViewMode = UITextFieldViewModeAlways;

    _modelLabel = [[UILabel alloc] init];
    _modelLabel.text = cfg.model;
    _modelLabel.font = [AAU mono:11];
    _modelLabel.textColor = [AAU accent];
    _modelLabel.textAlignment = NSTextAlignmentRight;

    UIButton *modelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    modelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [modelBtn addTarget:self action:@selector(pickModel) forControlEvents:UIControlEventTouchUpInside];
    [modelBtn addSubview:_modelLabel];
    _modelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_modelLabel.topAnchor constraintEqualToAnchor:modelBtn.topAnchor],
        [_modelLabel.bottomAnchor constraintEqualToAnchor:modelBtn.bottomAnchor],
        [_modelLabel.leadingAnchor constraintEqualToAnchor:modelBtn.leadingAnchor],
        [_modelLabel.trailingAnchor constraintEqualToAnchor:modelBtn.trailingAnchor constant:-4],
        [modelBtn.heightAnchor constraintGreaterThanOrEqualToConstant:24],
    ]];

    UIView *card1 = [self cardWithRows:@[
        [self row:@"协议" subtitle:@"决定请求格式与鉴权头" accessory:seg],
        [self separator],
        [self row:@"API 地址" subtitle:@"可填中转站；/v1 会自动补全" accessory:_baseField],
        [self separator],
        [self row:@"API Key" subtitle:@"仅保存在本机 App 容器内" accessory:_keyField],
        [self separator],
        [self row:@"模型" subtitle:@"点击选择或手动输入" accessory:modelBtn],
    ]];
    [self.stack addArrangedSubview:card1];

    UIStackView *btnRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self smallButton:@"测试连接 / 拉取模型" action:@selector(testConnection)],
        [self smallButton:@"从剪贴板粘贴 Key" action:@selector(pasteKey)],
    ]];
    btnRow.axis = UILayoutConstraintAxisHorizontal;
    btnRow.spacing = 8;
    btnRow.distribution = UIStackViewDistributionFillEqually;
    [self.stack addArrangedSubview:btnRow];

    // ---------- agent
    [self.stack addArrangedSubview:AASectionLabel(@"Agent")];

    _ctxLabel = [[UILabel alloc] init];
    _ctxLabel.text = cfg.maxContext > 0 ? [NSString stringWithFormat:@"%ld", (long)cfg.maxContext] : @"自动";
    _ctxLabel.textAlignment = NSTextAlignmentRight;

    _stepLabel = [[UILabel alloc] init];
    _stepLabel.text = [NSString stringWithFormat:@"%ld", (long)cfg.maxSteps];
    _stepLabel.textAlignment = NSTextAlignmentRight;

    _tempLabel = [[UILabel alloc] init];
    _tempLabel.text = [NSString stringWithFormat:@"%.2f", cfg.temperature];
    _tempLabel.font = [AAU mono:11];
    _tempLabel.textColor = [AAU accent];
    _tempLabel.textAlignment = NSTextAlignmentRight;

    UISlider *temp = [[UISlider alloc] init];
    temp.minimumValue = 0.0;
    temp.maximumValue = 1.5;
    temp.value = cfg.temperature;
    temp.minimumTrackTintColor = [AAU accent];
    [temp addTarget:self action:@selector(tempChanged:) forControlEvents:UIControlEventValueChanged];
    [temp.widthAnchor constraintEqualToConstant:120].active = YES;

    _promptView = [[UITextView alloc] init];
    _promptView.translatesAutoresizingMaskIntoConstraints = NO;
    _promptView.text = cfg.systemPrompt;
    _promptView.font = [AAU mono:10.5];
    _promptView.textColor = [AAU textDim];
    _promptView.backgroundColor = [AAU card2];
    _promptView.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    _promptView.delegate = self;
    [AAU round:_promptView radius:9];
    [_promptView.heightAnchor constraintEqualToConstant:96].active = YES;

    UIView *card2v = [self cardWithRows:@[
        [self stepperRow:@"最大上下文 (tokens)" valueLabel:_ctxLabel action:@selector(ctxStepper:)],
        [self separator],
        [self stepperRow:@"最大步数" valueLabel:_stepLabel action:@selector(stepStepper:)],
        [self separator],
        [self row:@"温度" subtitle:@"越低越稳定，越高越发散" accessory:[[UIStackView alloc] initWithArrangedSubviews:@[temp, _tempLabel]]],
        [self separator],
        [self toggleRow:@"流式输出" subtitle:@"边生成边显示" on:cfg.stream action:@selector(streamToggled:)],
        [self toggleRow:@"启用工具调用" subtitle:@"关闭后模型只能对话" on:cfg.allowTools action:@selector(toolsToggled:)],
        [self toggleRow:@"视觉输入" subtitle:@"发送任务时附带截图" on:cfg.visionInput action:@selector(visionToggled:)],
        [self toggleRow:@"显示思考过程" subtitle:@"显示 reasoning 内容" on:cfg.showReasoning action:@selector(reasoningToggled:)],
        [self toggleRow:@"触感反馈" subtitle:nil on:cfg.haptics action:@selector(hapticsToggled:)],
    ]];
    [self.stack addArrangedSubview:card2v];

    // prompt
    [self.stack addArrangedSubview:AASectionLabel(@"系统提示词")];
    UIView *promptCard = [self cardWithRows:@[_promptView,
        [self smallButton:@"恢复默认提示词" action:@selector(resetPrompt)]]];
    [self.stack addArrangedSubview:promptCard];

    // ---------- ui
    [self.stack addArrangedSubview:AASectionLabel(@"悬浮球")];
    UISlider *opacity = [[UISlider alloc] init];
    opacity.minimumValue = 0.25;
    opacity.maximumValue = 1.0;
    opacity.value = cfg.ballOpacity;
    opacity.minimumTrackTintColor = [AAU accent];
    [opacity addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    [opacity.widthAnchor constraintEqualToConstant:140].active = YES;

    UIView *card3 = [self cardWithRows:@[
        [self row:@"不透明度" subtitle:nil accessory:opacity],
        [self toggleRow:@"隐藏悬浮球" subtitle:@"可从快捷菜单恢复" on:cfg.ballHidden action:@selector(ballHiddenToggled:)],
    ]];
    [self.stack addArrangedSubview:card3];

    // ---------- data
    [self.stack addArrangedSubview:AASectionLabel(@"数据")];
    UIView *card4 = [self cardWithRows:@[
        [self row:@"当前会话" subtitle:@"清空消息，保留会话列表" accessory:[self smallButton:@"清空" action:@selector(clearSession)]],
        [self separator],
        [self row:@"全部重置" subtitle:@"配置与任务记录都会被清除" accessory:[self smallButton:@"重置" action:@selector(resetAll)]],
    ]];
    [self.stack addArrangedSubview:card4];

    // ---------- capabilities
    [self.stack addArrangedSubview:AASectionLabel(@"能力清单（真实实现）")];
    UILabel *catalog = [[UILabel alloc] init];
    catalog.numberOfLines = 0;
    catalog.font = [AAU mono:9.5];
    catalog.textColor = [AAU textDim];
    catalog.text = [AATools catalog];
    [self.stack addArrangedSubview:[self cardWithRows:@[catalog]]];

    // ---------- about
    UILabel *about = [[UILabel alloc] init];
    about.numberOfLines = 0;
    about.textAlignment = NSTextAlignmentCenter;
    about.font = [AAU mono:9];
    about.textColor = [AAU textDim];
    about.text = [NSString stringWithFormat:@"Aether %@ (%@)\nshell: %@\njbroot: %@\n工具 %lu 个",
                  AETHER_VERSION, AETHER_BUILD,
                  [AAExecutor shellPath],
                  [AAExecutor jbPrefix].length ? [AAExecutor jbPrefix] : @"未检测到",
                  (unsigned long)[AATools all].count];
    [self.stack addArrangedSubview:about];
}

#pragma mark actions

- (void)providerChanged:(UISegmentedControl *)seg {
    AAConfig *c = [AAConfig shared];
    c.provider = seg.selectedSegmentIndex == 1 ? @"anthropic" : @"openai";
    if ([c.baseURL rangeOfString:@"api.openai.com"].location != NSNotFound && seg.selectedSegmentIndex == 1) {
        c.baseURL = @"https://api.anthropic.com";
        _baseField.text = c.baseURL;
    }
    [c save];
    [AAU haptic:0];
}

- (void)textChanged:(UITextField *)f {
    AAConfig *c = [AAConfig shared];
    if (f.tag == 1) c.baseURL = f.text;
    if (f.tag == 2) c.apiKey = f.text;
    [c save];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)toggleKeyVisible:(UIButton *)b {
    _keyField.secureTextEntry = !_keyField.secureTextEntry;
    [b setImage:[UIImage systemImageNamed:_keyField.secureTextEntry ? @"eye" : @"eye.slash"] forState:UIControlStateNormal];
}

- (void)pasteKey {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (!s.length) { [AAU toast:@"剪贴板为空"]; return; }
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _keyField.text = s;
    [AAConfig shared].apiKey = s;
    [[AAConfig shared] save];
    [AAU toast:@"已粘贴 API Key"];
}

- (void)pickModel {
    AAConfig *c = [AAConfig shared];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择模型"
                                                                  message:c.model
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.popoverPresentationController.sourceView = self;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 1, 1);
    [sheet addAction:[UIAlertAction actionWithTitle:@"刷新模型列表…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self fetchModelsAndShow];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动输入…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptManualModel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet];
}

- (void)fetchModelsAndShow {
    [AAU toast:@"正在拉取模型列表…"];
    __weak typeof(self) weakSelf = self;
    [[AAClient shared] fetchModels:^(NSArray<NSString *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!models.count) {
                [AAU toast:error.localizedDescription ?: @"没有拿到模型列表"];
                [weakSelf promptManualModel];
                return;
            }
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"可用模型"
                                                                          message:[NSString stringWithFormat:@"共 %lu 个", (unsigned long)models.count]
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];
            sheet.popoverPresentationController.sourceView = weakSelf;
            sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(weakSelf.bounds), CGRectGetMidY(weakSelf.bounds), 1, 1);
            for (NSString *m in models) {
                [sheet addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    [AAConfig shared].model = m;
                    [[AAConfig shared] save];
                    [weakSelf reloadUI];
                    [AAU toast:[NSString stringWithFormat:@"已选择 %@", m]];
                }]];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf present:sheet];
        });
    }];
}

- (void)promptManualModel {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"模型名称" message:@"例如 gpt-4o / claude-sonnet-4 / deepseek-chat" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [AAConfig shared].model;
        tf.font = [AAU mono:13];
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *m = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (m.length) {
            [AAConfig shared].model = m;
            [[AAConfig shared] save];
            [self reloadUI];
        }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}

- (void)testConnection {
    AAConfig *c = [AAConfig shared];
    c.baseURL = _baseField.text;
    c.apiKey = _keyField.text;
    [c save];
    if (![c isConfigured]) { [AAU toast:@"请先填写地址与密钥"]; return; }
    [AAU toast:@"测试中…"];
    [[AAClient shared] fetchModels:^(NSArray<NSString *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) [AAU toast:[NSString stringWithFormat:@"失败：%@", error.localizedDescription]];
            else [AAU toast:[NSString stringWithFormat:@"连接正常，%lu 个模型", (unsigned long)models.count]];
        });
    }];
}

- (void)ctxStepper:(UIButton *)b {
    AAConfig *c = [AAConfig shared];
    NSInteger idx = 0;
    for (NSInteger i = 0; i < (NSInteger)self.ctxOptions.count; i++) {
        if ([self.ctxOptions[i] integerValue] == c.maxContext) { idx = i; break; }
    }
    idx += b.tag;
    if (idx < 0) idx = 0;
    if (idx >= (NSInteger)self.ctxOptions.count) idx = (NSInteger)self.ctxOptions.count - 1;
    c.maxContext = [self.ctxOptions[idx] integerValue];
    [c save];
    _ctxLabel.text = c.maxContext > 0 ? [NSString stringWithFormat:@"%ld", (long)c.maxContext] : @"自动";
    [AAU haptic:0];
}

- (void)stepStepper:(UIButton *)b {
    AAConfig *c = [AAConfig shared];
    NSInteger v = c.maxSteps + b.tag * 5;
    c.maxSteps = MAX(1, MIN(80, v));
    [c save];
    _stepLabel.text = [NSString stringWithFormat:@"%ld", (long)c.maxSteps];
    [AAU haptic:0];
}

- (void)tempChanged:(UISlider *)s {
    [AAConfig shared].temperature = s.value;
    [[AAConfig shared] save];
    _tempLabel.text = [NSString stringWithFormat:@"%.2f", s.value];
}

- (void)streamToggled:(UISwitch *)s { [AAConfig shared].stream = s.on; [[AAConfig shared] save]; }
- (void)toolsToggled:(UISwitch *)s { [AAConfig shared].allowTools = s.on; [[AAConfig shared] save]; }
- (void)visionToggled:(UISwitch *)s { [AAConfig shared].visionInput = s.on; [[AAConfig shared] save]; }
- (void)reasoningToggled:(UISwitch *)s { [AAConfig shared].showReasoning = s.on; [[AAConfig shared] save]; }
- (void)hapticsToggled:(UISwitch *)s { [AAConfig shared].haptics = s.on; [[AAConfig shared] save]; [AAU haptic:1]; }

- (void)opacityChanged:(UISlider *)s {
    [AAConfig shared].ballOpacity = s.value;
    [[AAConfig shared] save];
    [[AAOverlay shared] showBall:![AAConfig shared].ballHidden];
}

- (void)ballHiddenToggled:(UISwitch *)s {
    [AAConfig shared].ballHidden = s.on;
    [[AAConfig shared] save];
    [[AAOverlay shared] showBall:!s.on];
}

- (void)clearSession {
    NSString *sid = [AAConfig shared].lastSessionID;
    if (!sid.length) { [AAU toast:@"没有进行中的会话"]; return; }
    [[AAStore shared] deleteSession:sid];
    [AAConfig shared].lastSessionID = @"";
    [[AAConfig shared] save];
    [[AAOverlay shared] reloadChat];
    [AAU toast:@"已清空当前会话"];
}

- (void)resetAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"重置全部数据？" message:@"配置、API Key、任务记录都会被删除。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        [[AAConfig shared] reset];
        for (AASession *s in [[AAStore shared] sessions]) [[AAStore shared] deleteSession:s.sid];
        [AAConfig shared].lastSessionID = @"";
        [[AAConfig shared] save];
        [self reloadUI];
        [[AAOverlay shared] reloadChat];
        [AAU toast:@"已重置"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}

- (void)resetPrompt {
    [AAConfig shared].systemPrompt = [AAConfig defaultSystemPrompt];
    [[AAConfig shared] save];
    _promptView.text = [AAConfig shared].systemPrompt;
    [AAU toast:@"已恢复默认提示词"];
}

- (void)present:(UIViewController *)vc {
    UIViewController *root = [AAOverlay shared].window.rootViewController;
    if (!root) return;
    UIViewController *top = root;
    while (top.presentedViewController) top = top.presentedViewController;
    dispatch_async(dispatch_get_main_queue(), ^{ [top presentViewController:vc animated:YES completion:nil]; });
}

- (void)textViewDidChange:(UITextView *)textView {
    if (textView == self.promptView) {
        [AAConfig shared].systemPrompt = textView.text;
        [[AAConfig shared] save];
    }
}

@end

#pragma mark - History

@interface AAHistoryCell : UITableViewCell
@end

@implementation AAHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.textLabel.font = [AAU ui:13 weight:UIFontWeightMedium];
        self.textLabel.textColor = [AAU text];
        self.detailTextLabel.font = [AAU mono:9.5];
        self.detailTextLabel.textColor = [AAU textDim];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [[AAU accent] colorWithAlphaComponent:0.10];
        self.selectedBackgroundView = sel;
    }
    return self;
}

@end

@interface AAHistoryView () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<AASession *> *data;
@property (nonatomic, strong) UILabel *empty;
@end

@implementation AAHistoryView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.translatesAutoresizingMaskIntoConstraints = NO;
        _table.backgroundColor = [UIColor clearColor];
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.delegate = self;
        _table.dataSource = self;
        _table.rowHeight = 62;
        _table.contentInset = UIEdgeInsetsMake(6, 0, 20, 0);
        [self addSubview:_table];
        [NSLayoutConstraint activateConstraints:@[
            [_table.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_table.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_table.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_table.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        _empty = [[UILabel alloc] init];
        _empty.text = @"还没有任务记录";
        _empty.font = [AAU ui:12.5];
        _empty.textColor = [AAU textDim];
        _empty.textAlignment = NSTextAlignmentCenter;
        _empty.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_empty];
        [NSLayoutConstraint activateConstraints:@[
            [_empty.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_empty.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];

        [self reloadData];
    }
    return self;
}

- (void)reloadData {
    self.data = [[AAStore shared] sessions];
    self.empty.hidden = self.data.count > 0;
    [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.data.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AAHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"h"];
    if (!cell) cell = [[AAHistoryCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"h"];
    AASession *s = self.data[indexPath.row];
    cell.textLabel.text = s.title;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %ld 条消息 · %ld tokens",
                                 [AAU humanTime:s.updatedAt], (long)s.steps, (long)s.tokens];
    BOOL current = [s.sid isEqualToString:[AAConfig shared].lastSessionID];
    cell.textLabel.textColor = current ? [AAU accent] : [AAU text];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    AASession *s = self.data[indexPath.row];
    [AAConfig shared].lastSessionID = s.sid;
    [[AAConfig shared] save];
    if (self.onSelect) self.onSelect(s.sid);
    [AAU haptic:0];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(UIContextualAction *action, UIView *src, void (^done)(BOOL)) {
        AASession *s = weakSelf.data[indexPath.row];
        [[AAStore shared] deleteSession:s.sid];
        if ([s.sid isEqualToString:[AAConfig shared].lastSessionID]) {
            [AAConfig shared].lastSessionID = @"";
            [[AAConfig shared] save];
            [[AAOverlay shared] reloadChat];
        }
        [weakSelf reloadData];
        done(YES);
    }];
    del.backgroundColor = [AAU err];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
