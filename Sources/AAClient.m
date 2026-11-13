//
//  AAClient.m
//  Streaming chat client. Speaks the OpenAI-compatible API and the Anthropic
//  Messages API, including streaming tool-calls.
//

#import "Aether.h"

@interface AAClient () <NSURLSessionDataDelegate, NSURLSessionTaskDelegate> {
    NSURLSession *_session;
    NSURLSessionDataTask *_task;
    NSMutableData *_raw;          // non-stream body
    NSMutableString *_lineBuf;    // stream line buffer
    NSMutableString *_text;
    NSMutableString *_reasoning;
    NSMutableArray *_calls;       // array of {id,name,args}
    NSMutableDictionary *_callIndex; // block index -> position in _calls
    NSInteger _promptTokens;
    NSInteger _completionTokens;
    BOOL _anthropic;
    BOOL _finished;
    BOOL _toolDelivered;
    AADeltaBlock _onDelta;
    AAToolBlock _onTool;
    AAUsageBlock _onUsage;
    AAFinishBlock _onFinish;
}
@end

@implementation AAClient

+ (instancetype)shared {
    static AAClient *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[AAClient alloc] init]; [c setup]; });
    return c;
}

- (void)setup {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 180;
    cfg.timeoutIntervalForResource = 900;
    cfg.HTTPAdditionalHeaders = @{@"User-Agent": [NSString stringWithFormat:@"Aether/%@", AETHER_VERSION]};
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSOperationQueue *q = [[NSOperationQueue alloc] init];
    q.maxConcurrentOperationCount = 1;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:q];
}

- (BOOL)isBusy { return _task != nil; }

#pragma mark - URL helpers

- (NSString *)urlFor:(NSString *)kind {
    AAConfig *c = [AAConfig shared];
    NSString *base = [c.baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    if (!base.length) base = @"https://api.openai.com";

    BOOL hasVersion = ([base rangeOfString:@"/v1" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL fullPath  = ([base rangeOfString:@"/chat/completions"].location != NSNotFound) ||
                     ([base rangeOfString:@"/messages"].location != NSNotFound);

    if ([kind isEqualToString:@"chat"]) {
        if (fullPath) return base;
        if (_anthropic) return [base stringByAppendingString:hasVersion ? @"/messages" : @"/v1/messages"];
        return [base stringByAppendingString:hasVersion ? @"/chat/completions" : @"/v1/chat/completions"];
    }
    // models
    if ([base rangeOfString:@"/models" options:NSCaseInsensitiveSearch].location != NSNotFound) return base;
    return [base stringByAppendingString:hasVersion ? @"/models" : @"/v1/models"];
}

#pragma mark - Request building

- (NSString *)contentStringFor:(AAMessage *)m {
    if ([m.role isEqualToString:@"tool"]) return m.toolResult.length ? m.toolResult : m.content;
    return m.content;
}

- (NSDictionary *)openAIMessageFor:(AAMessage *)m {
    NSString *content = [self contentStringFor:m] ?: @"";
    if ([m.role isEqualToString:@"assistant"]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"role"] = @"assistant";
        d[@"content"] = content.length ? content : [NSNull null];
        if (m.isToolCall && m.toolName.length) {
            NSMutableString *args = [m.toolArgs mutableCopy] ?: [@"" mutableCopy];
            d[@"tool_calls"] = @[@{
                @"id": m.toolCallId.length ? m.toolCallId : [NSString stringWithFormat:@"call_%@", m.mid],
                @"type": @"function",
                @"function": @{@"name": m.toolName, @"arguments": args.length ? args : @"{}"},
            }];
        }
        return d;
    }
    if ([m.role isEqualToString:@"tool"]) {
        return @{@"role": @"tool",
                 @"tool_call_id": m.toolCallId.length ? m.toolCallId : @"call_0",
                 @"content": content};
    }
    // user (optionally with an attached image)
    if ([[AAConfig shared] visionInput] && [content rangeOfString:@"<<IMG:"].location != NSNotFound) {
        NSRange r1 = [content rangeOfString:@"<<IMG:"];
        NSRange r2 = [content rangeOfString:@">>" options:0 range:NSMakeRange(r1.location, content.length - r1.location)];
        if (r2.location != NSNotFound) {
            NSString *path = [content substringWithRange:NSMakeRange(r1.location + 6, r2.location - r1.location - 6)];
            NSString *plain = [[content stringByReplacingCharactersInRange:NSMakeRange(r1.location, r2.location + 2 - r1.location) withString:@""]
                               stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData *img = [NSData dataWithContentsOfFile:path];
            if (img.length) {
                NSString *b64 = [img base64EncodedStringWithOptions:0];
                return @{@"role": @"user", @"content": @[
                    @{@"type": @"text", @"text": plain.length ? plain : @"请查看这张截图"},
                    @{@"type": @"image_url", @"image_url": @{@"url": [NSString stringWithFormat:@"data:image/jpeg;base64,%@", b64]}},
                ]};
            }
        }
    }
    return @{@"role": @"user", @"content": content};
}

- (NSArray *)openAIMessages:(NSArray<AAMessage *> *)msgs {
    NSMutableArray *out = [NSMutableArray array];
    AAConfig *c = [AAConfig shared];
    if (c.systemPrompt.length) [out addObject:@{@"role": @"system", @"content": c.systemPrompt}];
    for (AAMessage *m in msgs) {
        if ([m.role isEqualToString:@"system"]) continue;
        if ([m.role isEqualToString:@"tool"] && !m.toolCallId.length) continue;
        [out addObject:[self openAIMessageFor:m]];
    }
    return out;
}

- (NSArray *)anthropicMessages:(NSArray<AAMessage *> *)msgs {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *pendingToolResults = [NSMutableArray array];

    void (^flushToolResults)(void) = ^{
        if (!pendingToolResults.count) return;
        [out addObject:@{@"role": @"user", @"content": [pendingToolResults copy]}];
        [pendingToolResults removeAllObjects];
    };

    for (AAMessage *m in msgs) {
        if ([m.role isEqualToString:@"system"]) continue;
        if ([m.role isEqualToString:@"tool"]) {
            [pendingToolResults addObject:@{
                @"type": @"tool_result",
                @"tool_use_id": m.toolCallId.length ? m.toolCallId : @"toolu_0",
                @"content": [self contentStringFor:m] ?: @"",
            }];
            continue;
        }
        flushToolResults();

        if ([m.role isEqualToString:@"assistant"]) {
            NSMutableArray *blocks = [NSMutableArray array];
            if (m.content.length) [blocks addObject:@{@"type": @"text", @"text": m.content}];
            if (m.isToolCall && m.toolName.length) {
                id input = @{};
                if (m.toolArgs.length) {
                    id parsed = [NSJSONSerialization JSONObjectWithData:[m.toolArgs dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
                    if ([parsed isKindOfClass:[NSDictionary class]]) input = parsed;
                }
                [blocks addObject:@{@"type": @"tool_use",
                                    @"id": m.toolCallId.length ? m.toolCallId : [NSString stringWithFormat:@"toolu_%@", m.mid],
                                    @"name": m.toolName,
                                    @"input": input}];
            }
            if (!blocks.count) [blocks addObject:@{@"type": @"text", @"text": @"…"}];
            // Merge with a preceding assistant turn (Anthropic needs alternation).
            NSDictionary *last = out.lastObject;
            if (last && [last[@"role"] isEqualToString:@"assistant"] && [last[@"content"] isKindOfClass:[NSArray class]]) {
                NSMutableArray *merged = [last[@"content"] mutableCopy];
                [merged addObjectsFromArray:blocks];
                [out removeLastObject];
                [out addObject:@{@"role": @"assistant", @"content": merged}];
            } else {
                [out addObject:@{@"role": @"assistant", @"content": blocks}];
            }
            continue;
        }

        // user
        [out addObject:@{@"role": @"user", @"content": @[@{@"type": @"text", @"text": [self contentStringFor:m] ?: @""}]}];
    }
    flushToolResults();
    return out;
}

- (NSDictionary *)requestBodyFor:(NSArray<AAMessage *> *)msgs tools:(NSArray *)tools {
    AAConfig *c = [AAConfig shared];
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = c.model ?: @"gpt-4o-mini";
    body[@"temperature"] = @(c.temperature);
    body[@"stream"] = @(c.stream);

    if (_anthropic) {
        body[@"max_tokens"] = @(4096);
        if (c.systemPrompt.length) body[@"system"] = c.systemPrompt;
        body[@"messages"] = [self anthropicMessages:msgs];
        if (tools.count && c.allowTools) body[@"tools"] = tools;
    } else {
        body[@"messages"] = [self openAIMessages:msgs];
        if (tools.count && c.allowTools) {
            body[@"tools"] = tools;
            body[@"tool_choice"] = @"auto";
        }
        if (c.stream) body[@"stream_options"] = @{@"include_usage": @YES};
    }
    return body;
}

#pragma mark - Send

- (void)sendMessages:(NSArray *)messages
               tools:(NSArray *)tools
             onDelta:(AADeltaBlock)onDelta
            onToolCall:(AAToolBlock)onTool
               onUsage:(AAUsageBlock)onUsage
              onFinish:(AAFinishBlock)onFinish {
    if (_task) {
        if (onFinish) onFinish([NSError errorWithDomain:@"Aether" code:-1
                                               userInfo:@{NSLocalizedDescriptionKey: @"上一个请求还在进行中"}]);
        return;
    }
    AAConfig *c = [AAConfig shared];
    if (![c isConfigured]) {
        if (onFinish) onFinish([NSError errorWithDomain:@"Aether" code:-2
                                               userInfo:@{NSLocalizedDescriptionKey: @"请先在设置中填写 API 地址、密钥与模型"}]);
        return;
    }

    _anthropic = [c.provider isEqualToString:@"anthropic"];
    _onDelta = [onDelta copy];
    _onTool = [onTool copy];
    _onUsage = [onUsage copy];
    _onFinish = [onFinish copy];
    _text = [NSMutableString string];
    _reasoning = [NSMutableString string];
    _calls = [NSMutableArray array];
    _callIndex = [NSMutableDictionary dictionary];
    _lineBuf = [NSMutableString string];
    _raw = [NSMutableData data];
    _promptTokens = 0;
    _completionTokens = 0;
    _finished = NO;
    _toolDelivered = NO;

    NSDictionary *body = [self requestBodyFor:messages tools:tools];
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if (!data) {
        if (onFinish) onFinish([NSError errorWithDomain:@"Aether" code:-3
                                               userInfo:@{NSLocalizedDescriptionKey: @"请求体序列化失败"}]);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self urlFor:@"chat"]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = data;
    for (NSString *k in c.requestHeaders) [req setValue:c.requestHeaders[k] forHTTPHeaderField:k];

    _task = [_session dataTaskWithRequest:req];
    [_task resume];
}

- (void)cancel {
    if (_task) {
        [_task cancel];
        _task = nil;
    }
    [self finishUp:[NSError errorWithDomain:@"Aether" code:-4
                                   userInfo:@{NSLocalizedDescriptionKey: @"已停止"}]];
}

- (void)finishUp:(NSError *)err {
    if (_finished) return;
    _finished = YES;
    _task = nil;

    if (_onUsage) _onUsage(_promptTokens, _completionTokens);

    if (_calls.count && !_toolDelivered) {
        _toolDelivered = YES;
        NSArray *calls = [_calls copy];
        if (_onTool) _onTool(calls);
    }
    if (_onFinish) _onFinish(err);
    _onDelta = nil; _onTool = nil; _onUsage = nil; _onFinish = nil;
}

#pragma mark - NSURLSession delegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
        if (code >= 400) {
            AALog(@"HTTP %ld", (long)code);
        }
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (![AAConfig shared].stream) {
        [_raw appendData:data];
        return;
    }
    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!chunk.length) return;
    [_lineBuf appendString:chunk];

    NSArray *lines = [_lineBuf componentsSeparatedByString:@"\n"];
    // Keep the trailing (possibly incomplete) fragment in the buffer.
    [_lineBuf setString:lines.lastObject ?: @""];
    for (NSUInteger i = 0; i + 1 < lines.count; i++) {
        [self handleLine:lines[i]];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (![AAConfig shared].stream) {
        [self parseNonStreamBody];
    }
    if (_lineBuf.length) [self handleLine:_lineBuf];

    if (error) {
        if (error.code == NSURLErrorCancelled) {
            [self finishUp:[NSError errorWithDomain:@"Aether" code:-4
                                           userInfo:@{NSLocalizedDescriptionKey: @"已停止"}]];
        } else {
            [self finishUp:error];
        }
        return;
    }
    [self finishUp:nil];
}

#pragma mark - Parsing

- (void)handleLine:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!trimmed.length) return;
    if (![trimmed hasPrefix:@"data:"]) return;

    NSString *payload = [[trimmed substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!payload.length) return;
    if ([payload isEqualToString:@"[DONE]"]) return;

    NSData *d = [payload dataUsingEncoding:NSUTF8StringEncoding];
    id json = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return;

    if (_anthropic) [self handleAnthropic:json];
    else [self handleOpenAI:json];
}

- (void)handleOpenAI:(NSDictionary *)json {
    NSDictionary *err = json[@"error"];
    if ([err isKindOfClass:[NSDictionary class]]) {
        NSString *msg = err[@"message"] ?: @"接口返回错误";
        [self finishUp:[NSError errorWithDomain:@"Aether" code:-5 userInfo:@{NSLocalizedDescriptionKey: msg}]];
        return;
    }
    NSDictionary *usage = json[@"usage"];
    if ([usage isKindOfClass:[NSDictionary class]]) {
        if (usage[@"prompt_tokens"]) _promptTokens = [usage[@"prompt_tokens"] integerValue];
        if (usage[@"completion_tokens"]) _completionTokens = [usage[@"completion_tokens"] integerValue];
    }
    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || !choices.count) return;
    NSDictionary *choice = choices.firstObject;
    NSDictionary *delta = choice[@"delta"];
    if (![delta isKindOfClass:[NSDictionary class]]) delta = choice[@"message"];
    if (![delta isKindOfClass:[NSDictionary class]]) return;

    NSString *reasoning = delta[@"reasoning_content"] ?: delta[@"reasoning"];
    if ([reasoning isKindOfClass:[NSString class]] && reasoning.length) {
        if (![reasoning isEqualToString:@"(null)"]) {
            [_reasoning appendString:reasoning];
            if (_onDelta) _onDelta(nil, reasoning);
        }
    }
    id content = delta[@"content"];
    if ([content isKindOfClass:[NSString class]] && [content length]) {
        [_text appendString:content];
        if (_onDelta) _onDelta(content, nil);
    }

    NSArray *toolCalls = delta[@"tool_calls"];
    if ([toolCalls isKindOfClass:[NSArray class]]) {
        for (NSDictionary *tc in toolCalls) {
            if (![tc isKindOfClass:[NSDictionary class]]) continue;
            NSInteger idx = [tc[@"index"] integerValue];
            NSString *key = [NSString stringWithFormat:@"%ld", (long)idx];
            NSMutableDictionary *slot = _callIndex[key];
            if (!slot) {
                slot = [NSMutableDictionary dictionaryWithDictionary:@{@"id": @"", @"name": @"", @"args": @""}];
                _callIndex[key] = slot;
                [_calls addObject:slot];
            }
            NSString *cid = tc[@"id"];
            if ([cid isKindOfClass:[NSString class]] && cid.length) slot[@"id"] = cid;
            NSDictionary *fn = tc[@"function"];
            if ([fn isKindOfClass:[NSDictionary class]]) {
                NSString *name = fn[@"name"];
                if ([name isKindOfClass:[NSString class]] && name.length) slot[@"name"] = name;
                id args = fn[@"arguments"];
                if ([args isKindOfClass:[NSString class]]) {
                    slot[@"args"] = [(NSString *)slot[@"args"] stringByAppendingString:args];
                } else if ([args isKindOfClass:[NSDictionary class]]) {
                    NSData *ad = [NSJSONSerialization dataWithJSONObject:args options:0 error:NULL];
                    if (ad) slot[@"args"] = [[NSString alloc] initWithData:ad encoding:NSUTF8StringEncoding];
                }
            }
            if (![(NSString *)slot[@"id"] length]) slot[@"id"] = [NSString stringWithFormat:@"call_%ld", (long)idx];
        }
    }
}

- (void)handleAnthropic:(NSDictionary *)json {
    NSString *type = json[@"type"];
    if ([type isEqualToString:@"error"]) {
        NSDictionary *e = json[@"error"];
        NSString *msg = [e isKindOfClass:[NSDictionary class]] ? (e[@"message"] ?: @"接口返回错误") : @"接口返回错误";
        [self finishUp:[NSError errorWithDomain:@"Aether" code:-5 userInfo:@{NSLocalizedDescriptionKey: msg}]];
        return;
    }
    if ([type isEqualToString:@"message_start"]) {
        NSDictionary *msg = json[@"message"];
        NSDictionary *usage = [msg isKindOfClass:[NSDictionary class]] ? msg[@"usage"] : nil;
        if ([usage isKindOfClass:[NSDictionary class]] && usage[@"input_tokens"])
            _promptTokens = [usage[@"input_tokens"] integerValue];
        return;
    }
    if ([type isEqualToString:@"content_block_start"]) {
        NSDictionary *block = json[@"content_block"];
        NSInteger idx = [json[@"index"] integerValue];
        if ([block[@"type"] isEqualToString:@"tool_use"]) {
            NSString *key = [NSString stringWithFormat:@"%ld", (long)idx];
            NSMutableDictionary *slot = [NSMutableDictionary dictionaryWithDictionary:@{
                @"id": block[@"id"] ?: @"toolu_0",
                @"name": block[@"name"] ?: @"",
                @"args": @"",
            }];
            _callIndex[key] = slot;
            [_calls addObject:slot];
        } else if ([block[@"type"] isEqualToString:@"thinking"] && [block[@"thinking"] isKindOfClass:[NSString class]]) {
            NSString *t = block[@"thinking"];
            if (t.length) {
                [_reasoning appendString:t];
                if (_onDelta) _onDelta(nil, t);
            }
        }
        return;
    }
    if ([type isEqualToString:@"content_block_delta"]) {
        NSDictionary *delta = json[@"delta"];
        NSString *dtype = delta[@"type"];
        if ([dtype isEqualToString:@"text_delta"]) {
            NSString *t = delta[@"text"];
            if ([t isKindOfClass:[NSString class]] && t.length) {
                [_text appendString:t];
                if (_onDelta) _onDelta(t, nil);
            }
        } else if ([dtype isEqualToString:@"input_json_delta"]) {
            NSString *partial = delta[@"partial_json"];
            NSInteger idx = [json[@"index"] integerValue];
            NSMutableDictionary *slot = _callIndex[[NSString stringWithFormat:@"%ld", (long)idx]];
            if (slot && [partial isKindOfClass:[NSString class]]) {
                slot[@"args"] = [(NSString *)slot[@"args"] stringByAppendingString:partial];
            }
        } else if ([dtype isEqualToString:@"thinking_delta"]) {
            NSString *t = delta[@"thinking"];
            if ([t isKindOfClass:[NSString class]] && t.length) {
                [_reasoning appendString:t];
                if (_onDelta) _onDelta(nil, t);
            }
        }
        return;
    }
    if ([type isEqualToString:@"message_delta"]) {
        NSDictionary *usage = json[@"usage"];
        if ([usage isKindOfClass:[NSDictionary class]] && usage[@"output_tokens"])
            _completionTokens = [usage[@"output_tokens"] integerValue];
        return;
    }
}

- (void)parseNonStreamBody {
    if (!_raw.length) return;
    id json = [NSJSONSerialization JSONObjectWithData:_raw options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *dict = json;

    NSDictionary *usage = dict[@"usage"];
    if ([usage isKindOfClass:[NSDictionary class]]) {
        if (usage[@"prompt_tokens"]) _promptTokens = [usage[@"prompt_tokens"] integerValue];
        if (usage[@"completion_tokens"]) _completionTokens = [usage[@"completion_tokens"] integerValue];
        if (usage[@"input_tokens"]) _promptTokens = [usage[@"input_tokens"] integerValue];
        if (usage[@"output_tokens"]) _completionTokens = [usage[@"output_tokens"] integerValue];
    }

    if (_anthropic) {
        NSArray *blocks = dict[@"content"];
        if ([blocks isKindOfClass:[NSArray class]]) {
            for (NSDictionary *b in blocks) {
                if ([b[@"type"] isEqualToString:@"text"]) {
                    NSString *t = b[@"text"];
                    if ([t isKindOfClass:[NSString class]]) {
                        [_text appendString:t];
                        if (_onDelta) _onDelta(t, nil);
                    }
                } else if ([b[@"type"] isEqualToString:@"tool_use"]) {
                    NSData *ad = [NSJSONSerialization dataWithJSONObject:(b[@"input"] ?: @{}) options:0 error:NULL];
                    [_calls addObject:[@{
                        @"id": b[@"id"] ?: @"toolu_0",
                        @"name": b[@"name"] ?: @"",
                        @"args": ad ? [[NSString alloc] initWithData:ad encoding:NSUTF8StringEncoding] : @"{}",
                    } mutableCopy]];
                }
            }
        }
        return;
    }

    NSArray *choices = dict[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || !choices.count) {
        NSString *msg = dict[@"error"][@"message"] ?: @"接口返回为空";
        _raw = nil;
        [self finishUp:[NSError errorWithDomain:@"Aether" code:-6 userInfo:@{NSLocalizedDescriptionKey: msg}]];
        return;
    }
    NSDictionary *msg = choices.firstObject[@"message"] ?: choices.firstObject[@"delta"];
    if (![msg isKindOfClass:[NSDictionary class]]) return;
    NSString *content = msg[@"content"];
    if ([content isKindOfClass:[NSString class]] && content.length) {
        [_text appendString:content];
        if (_onDelta) _onDelta(content, nil);
    }
    NSArray *tcs = msg[@"tool_calls"];
    if ([tcs isKindOfClass:[NSArray class]]) {
        for (NSDictionary *tc in tcs) {
            NSDictionary *fn = tc[@"function"];
            if (![fn isKindOfClass:[NSDictionary class]]) continue;
            [_calls addObject:[@{
                @"id": tc[@"id"] ?: @"call_0",
                @"name": fn[@"name"] ?: @"",
                @"args": [fn[@"arguments"] isKindOfClass:[NSString class]] ? fn[@"arguments"] : @"{}",
            } mutableCopy]];
        }
    }
}

#pragma mark - Models

- (void)fetchModels:(void (^)(NSArray<NSString *> *, NSError *))done {
    AAConfig *c = [AAConfig shared];
    if (!c.apiKey.length) {
        if (done) done(@[], [NSError errorWithDomain:@"Aether" code:-2
                                            userInfo:@{NSLocalizedDescriptionKey: @"请先填写 API 密钥"}]);
        return;
    }
    NSString *url = [self urlFor:@"models"];
    if ([c.provider isEqualToString:@"anthropic"]) {
        // Anthropic exposes /v1/models on newer accounts; fall back gracefully.
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.timeoutInterval = 30;
    for (NSString *k in c.requestHeaders) [req setValue:c.requestHeaders[k] forHTTPHeaderField:k];

    NSURLSessionDataTask *t = [_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { if (done) done(@[], err); return; }
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSMutableArray *names = [NSMutableArray array];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSArray *arr = json[@"data"] ?: json[@"models"];
            if ([arr isKindOfClass:[NSArray class]]) {
                for (id item in arr) {
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        NSString *n = item[@"id"] ?: item[@"name"];
                        if ([n isKindOfClass:[NSString class]]) [names addObject:n];
                    } else if ([item isKindOfClass:[NSString class]]) {
                        [names addObject:item];
                    }
                }
            }
            NSString *msg = json[@"error"][@"message"];
            if (!names.count && [msg isKindOfClass:[NSString class]]) {
                if (done) done(@[], [NSError errorWithDomain:@"Aether" code:-7 userInfo:@{NSLocalizedDescriptionKey: msg}]);
                return;
            }
        }
        [names sortUsingSelector:@selector(compare:)];
        if (done) done(names, nil);
    }];
    [t resume];
}

@end
