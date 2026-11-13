//
//  AAAgent.m
//  The reasoning loop: think → call tools → observe → repeat, until done.
//

#import "Aether.h"

@interface AAAgent () {
    BOOL _running;
    BOOL _cancelled;
    NSInteger _steps;
    NSInteger _lastPromptTokens;
}
@property (nonatomic, copy) NSString *sid;
@property (nonatomic, strong) NSMutableArray<AAMessage *> *pending;
@property (nonatomic, strong) NSMutableString *streamText;
@property (nonatomic, strong) NSMutableString *streamReasoning;
@end

@implementation AAAgent

+ (instancetype)shared {
    static AAAgent *a = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = [[AAAgent alloc] init]; });
    return a;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableArray array];
    }
    return self;
}

- (BOOL)running { return _running; }

#pragma mark - Public

- (void)startTask:(NSString *)task session:(NSString *)sid {
    if (_running) {
        if (self.onStatus) self.onStatus(@"上一个任务正在运行");
        return;
    }
    if (!task.length) return;
    if (![[AAConfig shared] isConfigured]) {
        if (self.onFinish) self.onFinish(@"请先在设置里填写 API 地址 / 密钥 / 模型");
        return;
    }

    AAStore *store = [AAStore shared];
    AASession *session = nil;
    if (sid.length) session = [store session:sid];
    if (!session) session = [store createSession:[self titleFor:task]];
    self.sid = session.sid;

    if ([session.title isEqualToString:@"新任务"] || !session.title.length) {
        [store renameSession:session.sid title:[self titleFor:task]];
    }

    AAMessage *um = [[AAMessage alloc] init];
    um.sid = session.sid;
    um.role = @"user";
    um.content = task;
    um.tokens = [AAToken count:task];
    [store insertMessage:um];

    [AAConfig shared].lastSessionID = session.sid;
    [[AAConfig shared] save];

    _running = YES;
    _cancelled = NO;
    _steps = 0;
    _lastPromptTokens = 0;
    [self.pending removeAllObjects];

    if (self.onStatus) self.onStatus(@"思考中…");
    if (self.onUsage) self.onUsage(0, [[AAConfig shared] effectiveMaxContext]);
    dispatch_async(dispatch_get_main_queue(), ^{ [self step]; });
}

- (void)cancel {
    _cancelled = YES;
    [[AAClient shared] cancel];
    _running = NO;
    if (self.onStatus) self.onStatus(@"已停止");
    if (self.onFinish) self.onFinish(@"已停止");
}

- (NSString *)titleFor:(NSString *)task {
    NSString *t = [task stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length > 22) t = [[t substringToIndex:22] stringByAppendingString:@"…"];
    return t.length ? t : @"新任务";
}

#pragma mark - Loop

- (void)step {
    if (_cancelled) { _running = NO; return; }
    if (_steps >= [AAConfig shared].maxSteps) {
        [self finishWith:[NSString stringWithFormat:@"已达到最大步数 %ld，任务结束", (long)[AAConfig shared].maxSteps]];
        return;
    }
    _steps++;
    _lastPromptTokens = 0;
    [self.pending removeAllObjects];
    self.streamText = [NSMutableString string];
    self.streamReasoning = [NSMutableString string];

    NSArray *msgs = [self contextMessages];
    AAConfig *cfg = [AAConfig shared];
    NSArray *tools = nil;
    if (cfg.allowTools) {
        tools = [cfg.provider isEqualToString:@"anthropic"] ? [AATools anthropicSchemas] : [AATools openAISchemas];
    }

    if (self.onStatus) self.onStatus(_steps == 1 ? @"思考中…" : [NSString stringWithFormat:@"第 %ld 轮", (long)_steps]);

    __weak typeof(self) weakSelf = self;
    [[AAClient shared] sendMessages:msgs
                              tools:tools
                            onDelta:^(NSString *text, NSString *reasoning) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        if (text.length) [self_.streamText appendString:text];
        if (reasoning.length) [self_.streamReasoning appendString:reasoning];
        if (self_.onDelta) self_.onDelta(text, reasoning);
    } onToolCall:^(NSArray<NSDictionary *> *calls) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        for (NSDictionary *c in calls) {
            AAMessage *m = [[AAMessage alloc] init];
            m.sid = self_.sid;
            m.role = @"assistant";
            m.isToolCall = YES;
            m.toolName = c[@"name"] ?: @"";
            m.toolArgs = c[@"args"] ?: @"{}";
            m.toolCallId = c[@"id"] ?: @"";
            [self_.pending addObject:m];
        }
    } onUsage:^(NSInteger prompt, NSInteger completion) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        if (prompt > 0) self_->_lastPromptTokens = prompt;
        if (self_.onUsage) self_.onUsage(prompt, [[AAConfig shared] effectiveMaxContext]);
    } onFinish:^(NSError *error) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        [self_ handleTurnEnd:error];
    }];
}

- (void)handleTurnEnd:(NSError *)error {
    if (_cancelled) { _running = NO; return; }

    if (error && error.code == -4) { _running = NO; return; }
    if (error) {
        [self finishWith:[NSString stringWithFormat:@"请求失败：%@", error.localizedDescription ?: @"未知错误"]];
        return;
    }

    // Persist the assistant turn.
    AAMessage *assistant = [[AAMessage alloc] init];
    assistant.sid = self.sid;
    assistant.role = @"assistant";
    assistant.content = self.streamText.length ? [self.streamText copy] : @"";
    assistant.reasoning = self.streamReasoning.length ? [self.streamReasoning copy] : @"";
    assistant.tokens = [AAToken count:assistant.content];

    if (self.pending.count) {
        // Attach the assistant's prose to the first tool call so the history reads naturally.
        if (assistant.content.length) {
            AAMessage *first = self.pending.firstObject;
            first.content = assistant.content;
            first.reasoning = assistant.reasoning;
        }
        for (AAMessage *call in self.pending) {
            [[AAStore shared] insertMessage:call];
            [self executeCall:call];
        }
        [self.pending removeAllObjects];
        [[AAStore shared] touchSession:self.sid tokens:_lastPromptTokens steps:_steps];
        if (!_cancelled) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self step];
            });
        }
        return;
    }

    if (assistant.content.length) [[AAStore shared] insertMessage:assistant];

    // Text-mode tool fallback for models without native function calling.
    NSArray *textCalls = [self parseTextCalls:assistant.content];
    if (textCalls.count) {
        for (NSDictionary *c in textCalls) {
            AAMessage *m = [[AAMessage alloc] init];
            m.sid = self.sid;
            m.role = @"assistant";
            m.isToolCall = YES;
            m.toolName = c[@"name"] ?: @"";
            m.toolArgs = c[@"args"] ?: @"{}";
            m.toolCallId = [NSString stringWithFormat:@"call_%ld", (long)(_steps * 10 + [self.pending count])];
            [[AAStore shared] insertMessage:m];
            [self executeCall:m];
        }
        [[AAStore shared] touchSession:self.sid tokens:_lastPromptTokens steps:_steps];
        if (!_cancelled) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self step];
            });
        }
        return;
    }

    [[AAStore shared] touchSession:self.sid tokens:_lastPromptTokens steps:_steps];
    [self finishWith:nil];
}

- (void)finishWith:(NSString *)error {
    _running = NO;
    _cancelled = NO;
    if (self.onFinish) self.onFinish(error);
}

#pragma mark - Tool execution

- (void)executeCall:(AAMessage *)call {
    if (_cancelled) return;
    if (self.onStatus) self.onStatus([NSString stringWithFormat:@"执行 %@…", call.toolName]);
    if (self.onToolStart) self.onToolStart(call);

    NSDictionary *args = @{};
    if (call.toolArgs.length) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[call.toolArgs dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0 error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) args = parsed;
    }

    NSString *result = [AATools runTool:call.toolName args:args];
    BOOL isDone = [call.toolName isEqualToString:@"task_done"];
    BOOL isErr = [result hasPrefix:@"错误"] || [result hasPrefix:@"失败"] || [result hasPrefix:@"未知工具"] ||
                 [result hasPrefix:@"读取失败"] || [result hasPrefix:@"无法"];

    AAMessage *tm = [[AAMessage alloc] init];
    tm.sid = self.sid;
    tm.role = @"tool";
    tm.toolName = call.toolName;
    tm.toolCallId = call.toolCallId;
    tm.toolResult = result;
    tm.content = result;
    tm.isError = isErr;
    tm.tokens = [AAToken count:result];
    [[AAStore shared] insertMessage:tm];

    if (self.onToolEnd) self.onToolEnd(tm);

    if (isDone) {
        NSString *summary = [result stringByReplacingOccurrencesOfString:@"TASK_DONE:" withString:@""];
        AALog(@"task done: %@", summary);
        _cancelled = YES;   // stop the loop after this turn
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_cancelled = NO;
            self->_running = NO;
            if (self.onStatus) self.onStatus(@"已完成");
            if (self.onFinish) self.onFinish(nil);
        });
    }
}

#pragma mark - Context

- (NSArray<AAMessage *> *)contextMessages {
    AAConfig *cfg = [AAConfig shared];
    NSArray *all = [[AAStore shared] messages:self.sid];
    NSInteger budget = [cfg effectiveMaxContext];
    NSInteger reserve = 1600;                 // room for the next completion
    NSInteger limit = MAX(2000, budget - reserve);

    NSMutableArray *kept = [NSMutableArray array];
    NSInteger total = 0;
    // Walk backwards, always keeping the newest messages.
    for (AAMessage *m in [all reverseObjectEnumerator]) {
        NSInteger t = [AAToken count:m.content] + [AAToken count:m.toolArgs] + [AAToken count:m.toolResult] + 6;
        if (total + t > limit && kept.count >= 4) break;
        [kept insertObject:m atIndex:0];
        total += t;
    }
    // Drop orphan tool messages at the head (their call is gone).
    while (kept.count && [[kept.firstObject role] isEqualToString:@"tool"]) [kept removeObjectAtIndex:0];
    return kept;
}

#pragma mark - Text-mode tool parsing

- (NSArray *)parseTextCalls:(NSString *)text {
    if (!text.length) return @[];
    NSMutableArray *calls = [NSMutableArray array];
    // Look for ```json { "tool": "...", "args": {...} } ``` or {"tool": ...} inline.
    NSArray *fences = [text componentsSeparatedByString:@"```"];
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSUInteger i = 1; i < fences.count; i += 2) [candidates addObject:fences[i]];
    [candidates addObject:text];

    for (NSString *chunk in candidates) {
        NSString *s = chunk;
        if ([s hasPrefix:@"json"]) s = [s substringFromIndex:4];
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![s containsString:@"\"tool\""] && ![s containsString:@"\"name\""]) continue;
        NSRange start = [s rangeOfString:@"{"];
        NSRange end = [s rangeOfString:@"}" options:NSBackwardsSearch];
        if (start.location == NSNotFound || end.location == NSNotFound || end.location <= start.location) continue;
        NSString *json = [s substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
        // Try progressively larger prefixes to survive trailing prose.
        id obj = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = obj;
        NSString *name = d[@"tool"] ?: d[@"name"];
        if (![name isKindOfClass:[NSString class]]) continue;
        if (![AATools toolNamed:name]) continue;
        id args = d[@"args"] ?: d[@"arguments"] ?: d[@"parameters"] ?: @{};
        NSString *argsStr = @"{}";
        if ([args isKindOfClass:[NSDictionary class]]) {
            NSData *ad = [NSJSONSerialization dataWithJSONObject:args options:0 error:NULL];
            if (ad) argsStr = [[NSString alloc] initWithData:ad encoding:NSUTF8StringEncoding];
        } else if ([args isKindOfClass:[NSString class]]) {
            argsStr = args;
        }
        [calls addObject:@{@"name": name, @"args": argsStr}];
        break;
    }
    return calls;
}

@end
