//
//  AATools.m
//  The agent's hands. Every tool below is a real implementation — no mocks.
//

#import "Aether.h"
#import <objc/runtime.h>

#pragma mark - Tool

@implementation AATool
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@>", self.category, self.name];
}
@end

typedef NSString *(^AAHandler)(NSDictionary *args);

static NSDictionary *P(NSString *type, NSString *desc) {
    return @{@"type": type, @"description": desc};
}
static NSDictionary *PEnum(NSString *type, NSString *desc, NSArray *enums) {
    return @{@"type": type, @"description": desc, @"enum": enums};
}

static AATool *T(NSString *name, NSString *cat, NSString *summary,
                 NSDictionary *props, NSArray *required, AAHandler handler) {
    AATool *t = [[AATool alloc] init];
    t.name = name;
    t.category = cat;
    t.summary = summary;
    NSMutableDictionary *schema = [NSMutableDictionary dictionary];
    schema[@"type"] = @"object";
    schema[@"properties"] = props ?: @{};
    if (required.count) schema[@"required"] = required;
    t.schema = schema;
    t.handler = handler;
    return t;
}

static NSString *Cap(NSString *s, NSUInteger limit) {
    if (!s) return @"";
    if (s.length <= limit) return s;
    return [NSString stringWithFormat:@"%@\n…[截断，共 %lu 字符]", [s substringToIndex:limit], (unsigned long)s.length];
}

static NSString *ArgStr(NSDictionary *a, NSString *k, NSString *def) {
    id v = a[k];
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return def;
}
static double ArgNum(NSDictionary *a, NSString *k, double def) {
    id v = a[k];
    if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v doubleValue];
    return def;
}

#pragma mark - Tools

@implementation AATools

+ (NSArray<AATool *> *)all {
    static NSArray *tools = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tools = [AATools build]; });
    return tools;
}

+ (AATool *)toolNamed:(NSString *)name {
    for (AATool *t in [self all]) if ([t.name isEqualToString:name]) return t;
    return nil;
}

+ (NSArray<AATool *> *)build {
    NSMutableArray *list = [NSMutableArray array];

    // ---------------------------------------------------------------- shell
    [list addObject:T(@"shell", @"shell",
        @"在目标 App 进程内执行真实的 shell 命令，返回 stdout/stderr 合并输出。可用命令取决于设备是否已越狱（sh/ls/cat/grep/curl 等）。",
        @{@"command": P(@"string", @"要执行的命令，例如 'ls -la /var/mobile'"),
          @"cwd": P(@"string", @"工作目录，默认 App 容器目录"),
          @"timeout": P(@"number", @"超时秒数，默认 30，最大 120")},
        @[@"command"], ^NSString *(NSDictionary *a) {
            NSString *cmd = ArgStr(a, @"command", @"");
            if (!cmd.length) return @"错误：command 为空";
            NSString *cwd = ArgStr(a, @"cwd", nil);
            double to = ArgNum(a, @"timeout", 30);
            if (to <= 0 || to > 120) to = 120;
            NSString *err = nil;
            NSString *out = [AAExecutor run:cmd cwd:cwd timeout:to error:&err];
            if (!out.length && err) out = err;
            return Cap(out.length ? out : @"(无输出)", 20000);
        }));

    // ------------------------------------------------------------------- fs
    [list addObject:T(@"fs_list", @"fs",
        @"列出目录内容（真实文件系统）。",
        @{@"path": P(@"string", @"目录路径，默认 App 容器"),
          @"detailed": P(@"boolean", @"是否输出大小与时间")},
        @[], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", NSHomeDirectory());
            BOOL detailed = [a[@"detailed"] boolValue];
            NSFileManager *fm = [NSFileManager defaultManager];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir]) return [NSString stringWithFormat:@"路径不存在: %@", path];
            if (!isDir) {
                NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
                return [NSString stringWithFormat:@"%@ (%@)\n%@", path, [AAU humanBytes:[attr[NSFileSize] unsignedLongLongValue]], Cap([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL], 4000) ?: @""];
            }
            NSArray *items = [fm contentsOfDirectoryAtPath:path error:NULL] ?: @[];
            NSMutableString *s = [NSMutableString stringWithFormat:@"%@ (%lu 项)\n", path, (unsigned long)items.count];
            NSArray *sorted = [items sortedArrayUsingSelector:@selector(compare:)];
            for (NSString *name in sorted) {
                NSString *full = [path stringByAppendingPathComponent:name];
                BOOL d = NO;
                [fm fileExistsAtPath:full isDirectory:&d];
                if (detailed) {
                    NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
                    [s appendFormat:@"%@ %-40s %@\n", d ? @"d" : @"-",
                        name.UTF8String ?: "", [AAU humanBytes:[attr[NSFileSize] unsignedLongLongValue]]];
                } else {
                    [s appendFormat:@"%@ %@\n", d ? @"[DIR]" : @"     ", name];
                }
            }
            return Cap(s, 20000);
        }));

    [list addObject:T(@"fs_read", @"fs",
        @"读取文本文件。支持行偏移，超大文件自动截断。",
        @{@"path": P(@"string", @"文件绝对路径"),
          @"offset": P(@"number", @"起始行，默认 0"),
          @"limit": P(@"number", @"最多读取行数，默认 800")},
        @[@"path"], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", @"");
            NSInteger offset = (NSInteger)ArgNum(a, @"offset", 0);
            NSInteger limit = (NSInteger)ArgNum(a, @"limit", 800);
            if (limit <= 0) limit = 800;
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data) return [NSString stringWithFormat:@"读取失败（不存在或无权限）: %@", path];
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!text) {
                NSMutableString *hex = [NSMutableString stringWithFormat:@"(二进制文件, %@)\n", [AAU humanBytes:data.length]];
                NSUInteger n = MIN(data.length, (NSUInteger)512);
                const unsigned char *b = data.bytes;
                for (NSUInteger i = 0; i < n; i++) {
                    [hex appendFormat:@"%02x", b[i]];
                    if ((i + 1) % 32 == 0) [hex appendString:@"\n"];
                }
                return hex;
            }
            NSArray *lines = [text componentsSeparatedByString:@"\n"];
            if (offset < 0) offset = 0;
            NSUInteger start = MIN((NSUInteger)offset, lines.count);
            NSUInteger end = MIN(start + (NSUInteger)limit, lines.count);
            NSMutableString *s = [NSMutableString string];
            for (NSUInteger i = start; i < end; i++) {
                [s appendFormat:@"%5lu| %@\n", (unsigned long)(i + 1), lines[i]];
            }
            if (end < lines.count) [s appendFormat:@"…(还有 %lu 行)\n", (unsigned long)(lines.count - end)];
            return Cap(s, 24000);
        }));

    [list addObject:T(@"fs_write", @"fs",
        @"写入或覆盖文件；append=true 时追加。会自动创建父目录。",
        @{@"path": P(@"string", @"文件绝对路径"),
          @"content": P(@"string", @"文本内容"),
          @"append": P(@"boolean", @"是否追加")},
        @[@"path", @"content"], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", @"");
            NSString *content = ArgStr(a, @"content", @"");
            if (!path.length) return @"错误：path 为空";
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dir = [path stringByDeletingLastPathComponent];
            if (![fm fileExistsAtPath:dir]) [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
            BOOL append = [a[@"append"] boolValue];
            NSError *err = nil;
            BOOL ok;
            if (append) {
                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
                if (!fh) {
                    ok = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
                } else {
                    @try {
                        [fh seekToEndOfFile];
                        [fh writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
                        [fh closeFile];
                        ok = YES;
                    } @catch (NSException *e) { ok = NO; err = [NSError errorWithDomain:@"Aether" code:-1 userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"写入失败"}]; }
                }
            } else {
                ok = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
            }
            if (!ok) return [NSString stringWithFormat:@"写入失败: %@", err.localizedDescription ?: @"未知错误"];
            NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
            return [NSString stringWithFormat:@"已写入 %@ (%@)", path, [AAU humanBytes:[attr[NSFileSize] unsignedLongLongValue]]];
        }));

    [list addObject:T(@"fs_mkdir", @"fs", @"创建目录（递归）。",
        @{@"path": P(@"string", @"目录路径")}, @[@"path"], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", @"");
            NSError *err = nil;
            BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&err];
            return ok ? [NSString stringWithFormat:@"已创建 %@", path] : [NSString stringWithFormat:@"失败: %@", err.localizedDescription];
        }));

    [list addObject:T(@"fs_delete", @"fs", @"删除文件或目录（递归）。",
        @{@"path": P(@"string", @"目标路径")}, @[@"path"], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", @"");
            if (path.length < 2) return @"拒绝执行：路径过于危险";
            NSError *err = nil;
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
            return ok ? [NSString stringWithFormat:@"已删除 %@", path] : [NSString stringWithFormat:@"失败: %@", err.localizedDescription];
        }));

    [list addObject:T(@"fs_move", @"fs", @"移动或重命名文件/目录。",
        @{@"from": P(@"string", @"源路径"), @"to": P(@"string", @"目标路径")},
        @[@"from", @"to"], ^NSString *(NSDictionary *a) {
            NSString *from = ArgStr(a, @"from", @""), *to = ArgStr(a, @"to", @"");
            NSError *err = nil;
            BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:from toPath:to error:&err];
            return ok ? [NSString stringWithFormat:@"%@ → %@", from, to] : [NSString stringWithFormat:@"失败: %@", err.localizedDescription];
        }));

    [list addObject:T(@"fs_stat", @"fs", @"查看文件/目录属性（大小、权限、时间）。",
        @{@"path": P(@"string", @"路径")}, @[@"path"], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", @"");
            NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
            if (!attr) return [NSString stringWithFormat:@"无法获取属性: %@", path];
            NSMutableString *s = [NSMutableString stringWithFormat:@"path: %@\n", path];
            for (NSString *k in attr) [s appendFormat:@"%@: %@\n", k, attr[k]];
            return s;
        }));

    [list addObject:T(@"fs_search", @"fs",
        @"在目录中按文件名或内容搜索（递归，最多 100 条命中）。",
        @{@"path": P(@"string", @"搜索根目录"),
          @"name": P(@"string", @"文件名包含的字符串（可空）"),
          @"content": P(@"string", @"文件内容包含的字符串（可空）"),
          @"max_depth": P(@"number", @"最大深度，默认 6")},
        @[@"path"], ^NSString *(NSDictionary *a) {
            NSString *root = ArgStr(a, @"path", NSHomeDirectory());
            NSString *nameQ = ArgStr(a, @"name", nil);
            NSString *contentQ = ArgStr(a, @"content", nil);
            NSInteger maxDepth = (NSInteger)ArgNum(a, @"max_depth", 6);
            NSFileManager *fm = [NSFileManager defaultManager];
            NSMutableArray *hits = [NSMutableArray array];
            NSMutableArray *queue = [NSMutableArray arrayWithObject:@[root, @0]];
            while (queue.count && hits.count < 100) {
                NSArray *pair = queue.firstObject;
                [queue removeObjectAtIndex:0];
                NSString *dir = pair[0];
                NSInteger depth = [pair[1] integerValue];
                if (depth > maxDepth) continue;
                NSArray *items = [fm contentsOfDirectoryAtPath:dir error:NULL];
                for (NSString *name in items) {
                    if (hits.count >= 100) break;
                    NSString *full = [dir stringByAppendingPathComponent:name];
                    BOOL isDir = NO;
                    [fm fileExistsAtPath:full isDirectory:&isDir];
                    BOOL nameHit = !nameQ.length || [name localizedCaseInsensitiveContainsString:nameQ];
                    if (!isDir && nameHit) {
                        BOOL pass = YES;
                        if (contentQ.length) {
                            pass = NO;
                            NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
                            if ([attr[NSFileSize] unsignedLongLongValue] < 3 * 1024 * 1024) {
                                NSString *txt = [NSString stringWithContentsOfFile:full encoding:NSUTF8StringEncoding error:NULL];
                                pass = [txt localizedCaseInsensitiveContainsString:contentQ];
                            }
                        }
                        if (pass) [hits addObject:full];
                    }
                    if (isDir) [queue addObject:@[full, @(depth + 1)]];
                }
            }
            if (!hits.count) return @"未找到匹配项";
            return Cap([hits componentsJoinedByString:@"\n"], 12000);
        }));

    // ------------------------------------------------------------------- ui
    [list addObject:T(@"ui_dump", @"ui",
        @"导出当前 App 的完整界面层级树（含元素 id、类名、文字、坐标）。这是操控界面前的第一步。",
        @{}, @[], ^NSString *(NSDictionary *a) {
            return Cap([[AAUIBridge shared] hierarchyDescription], 24000);
        }));

    [list addObject:T(@"ui_find", @"ui",
        @"按文字/类名/id 搜索界面元素，返回匹配项及坐标。",
        @{@"query": P(@"string", @"关键字")}, @[@"query"], ^NSString *(NSDictionary *a) {
            NSString *q = ArgStr(a, @"query", @"");
            NSArray *hits = [[AAUIBridge shared] find:q];
            if (!hits.count) return [NSString stringWithFormat:@"没有匹配 \"%@\" 的元素", q];
            NSMutableString *s = [NSMutableString string];
            for (AAElement *e in hits) [s appendFormat:@"[%@] %@\n", e.eid, e.description];
            return Cap(s, 12000);
        }));

    [list addObject:T(@"ui_tap", @"ui",
        @"点击屏幕坐标（逻辑点，非像素）。也可传 element_id 直接点击已抓取的元素。",
        @{@"x": P(@"number", @"横坐标"),
          @"y": P(@"number", @"纵坐标"),
          @"element_id": P(@"string", @"元素 id（优先于 x/y）")},
        @[], ^NSString *(NSDictionary *a) {
            NSString *eid = ArgStr(a, @"element_id", nil);
            if (eid.length) {
                BOOL ok = [[AAUIBridge shared] tapElement:eid];
                return ok ? [NSString stringWithFormat:@"已点击 %@", eid] : [NSString stringWithFormat:@"点击失败：元素 %@ 不在当前层级", eid];
            }
            double x = ArgNum(a, @"x", -1), y = ArgNum(a, @"y", -1);
            if (x < 0 || y < 0) return @"错误：需要 x/y 或 element_id";
            BOOL ok = [[AAUIBridge shared] tapPoint:CGPointMake(x, y)];
            return ok ? [NSString stringWithFormat:@"已点击 (%.0f, %.0f)", x, y] : @"点击失败（没有可命中的视图）";
        }));

    [list addObject:T(@"ui_swipe", @"ui",
        @"从一点滑动到另一点（用于滚动/翻页/拖拽）。",
        @{@"x1": P(@"number", @"起点 x"), @"y1": P(@"number", @"起点 y"),
          @"x2": P(@"number", @"终点 x"), @"y2": P(@"number", @"终点 y"),
          @"duration": P(@"number", @"时长秒，默认 0.35")},
        @[@"x1", @"y1", @"x2", @"y2"], ^NSString *(NSDictionary *a) {
            CGPoint p1 = CGPointMake(ArgNum(a, @"x1", 0), ArgNum(a, @"y1", 0));
            CGPoint p2 = CGPointMake(ArgNum(a, @"x2", 0), ArgNum(a, @"y2", 0));
            BOOL ok = [[AAUIBridge shared] swipeFrom:p1 to:p2 duration:ArgNum(a, @"duration", 0.35)];
            return ok ? [NSString stringWithFormat:@"已滑动 (%.0f,%.0f) → (%.0f,%.0f)", p1.x, p1.y, p2.x, p2.y] : @"滑动失败";
        }));

    [list addObject:T(@"ui_longpress", @"ui", @"长按坐标。",
        @{@"x": P(@"number", @"x"), @"y": P(@"number", @"y"),
          @"duration": P(@"number", @"秒，默认 0.7")},
        @[@"x", @"y"], ^NSString *(NSDictionary *a) {
            CGPoint p = CGPointMake(ArgNum(a, @"x", 0), ArgNum(a, @"y", 0));
            BOOL ok = [[AAUIBridge shared] longPress:p duration:ArgNum(a, @"duration", 0.7)];
            return ok ? @"已长按" : @"长按失败";
        }));

    [list addObject:T(@"ui_input", @"ui",
        @"向当前焦点输入框输入文本（会先尝试聚焦可编辑控件）。",
        @{@"text": P(@"string", @"要输入的文本")}, @[@"text"], ^NSString *(NSDictionary *a) {
            NSString *text = ArgStr(a, @"text", @"");
            BOOL ok = [[AAUIBridge shared] inputText:text];
            return ok ? [NSString stringWithFormat:@"已输入 %lu 字符", (unsigned long)text.length] : @"输入失败：找不到可编辑控件";
        }));

    [list addObject:T(@"ui_scroll", @"ui",
        @"滚动当前屏幕中的第一个滚动视图。dy>0 向上滚动（内容上移）。",
        @{@"dy": P(@"number", @"滚动距离，正数向下翻")},
        @[@"dy"], ^NSString *(NSDictionary *a) {
            BOOL ok = [[AAUIBridge shared] scrollBy:ArgNum(a, @"dy", 300)];
            return ok ? @"已滚动" : @"滚动失败：未找到滚动视图";
        }));

    [list addObject:T(@"screenshot", @"ui",
        @"截取当前 App 画面并保存为 JPEG，返回文件路径。启用视觉输入后模型可直接看图。",
        @{@"path": P(@"string", @"可选保存路径")},
        @[], ^NSString *(NSDictionary *a) {
            NSString *path = ArgStr(a, @"path", nil);
            BOOL ok = [[AAUIBridge shared] saveScreenshot:path];
            if (!ok) return @"截图失败";
            return [NSString stringWithFormat:@"已保存截图：%@", path.length ? path : @"(见最新 shots 目录)"];
        }));

    // ------------------------------------------------------------------ app
    [list addObject:T(@"app_info", @"app", @"当前 App 信息（bundle id、版本、容器路径、进程与设备信息）。",
        @{}, @[], ^NSString *(NSDictionary *a) {
            NSDictionary *info = [AAUIBridge appInfo];
            NSMutableString *s = [NSMutableString string];
            for (NSString *k in [info.allKeys sortedArrayUsingSelector:@selector(compare:)])
                [s appendFormat:@"%@: %@\n", k, info[k]];
            return s;
        }));

    [list addObject:T(@"list_apps", @"app", @"列出设备上已安装的应用（bundle id + 名称）。",
        @{}, @[], ^NSString *(NSDictionary *a) {
            Class ws = NSClassFromString(@"LSApplicationWorkspace");
            if (!ws) return @"当前环境无法枚举应用（LSApplicationWorkspace 不可用）";
            id workspace = [ws performSelector:@selector(defaultWorkspace)];
            NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
            NSMutableArray *lines = [NSMutableArray array];
            for (id proxy in apps) {
                NSString *bid = [proxy performSelector:@selector(bundleIdentifier)];
                NSString *nm = nil;
                if ([proxy respondsToSelector:@selector(localizedName)]) nm = [proxy performSelector:@selector(localizedName)];
                [lines addObject:[NSString stringWithFormat:@"%@  %@", bid ?: @"?", nm ?: @""]];
            }
            [lines sortUsingSelector:@selector(compare:)];
            return Cap([lines componentsJoinedByString:@"\n"], 16000);
        }));

    [list addObject:T(@"launch_app", @"app", @"通过 bundle id 启动另一个 App（会离开当前 App）。",
        @{@"bundle_id": P(@"string", @"目标 App 的 bundle id")},
        @[@"bundle_id"], ^NSString *(NSDictionary *a) {
            NSString *bid = ArgStr(a, @"bundle_id", @"");
            if (!bid.length) return @"错误：bundle_id 为空";
            Class ws = NSClassFromString(@"LSApplicationWorkspace");
            if (!ws) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bid]];
                    if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
                });
                return [NSString stringWithFormat:@"已尝试通过 URL scheme 启动 %@", bid];
            }
            id workspace = [ws performSelector:@selector(defaultWorkspace)];
            BOOL ok = [workspace performSelector:@selector(openApplicationWithBundleID:) withObject:bid] ? YES : NO;
            return ok ? [NSString stringWithFormat:@"已启动 %@", bid] : [NSString stringWithFormat:@"启动失败: %@", bid];
        }));

    [list addObject:T(@"open_url", @"app", @"用系统打开 URL（支持 http/https/自定义 scheme）。",
        @{@"url": P(@"string", @"URL")}, @[@"url"], ^NSString *(NSDictionary *a) {
            NSString *u = ArgStr(a, @"url", @"");
            NSURL *url = [NSURL URLWithString:u];
            if (!url) return @"URL 无效";
            __block BOOL ok = NO;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                    ok = success;
                    dispatch_semaphore_signal(sem);
                }];
            });
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
            return ok ? [NSString stringWithFormat:@"已打开 %@", u] : @"打开失败或超时";
        }));

    // ------------------------------------------------------------------ net
    [list addObject:T(@"http_request", @"net",
        @"发起任意 HTTP 请求（GET/POST/PUT/DELETE），返回状态码与响应体（自动截断）。",
        @{@"url": P(@"string", @"请求地址"),
          @"method": PEnum(@"string", @"方法", @[@"GET", @"POST", @"PUT", @"DELETE", @"PATCH"]),
          @"headers": P(@"object", @"请求头字典"),
          @"body": P(@"string", @"请求体")},
        @[@"url"], ^NSString *(NSDictionary *a) {
            NSString *u = ArgStr(a, @"url", @"");
            NSURL *url = [NSURL URLWithString:u];
            if (!url) return @"URL 无效";
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            req.HTTPMethod = [ArgStr(a, @"method", @"GET") uppercaseString];
            req.timeoutInterval = 60;
            NSDictionary *h = a[@"headers"];
            if ([h isKindOfClass:[NSDictionary class]]) {
                for (NSString *k in h) [req setValue:[h[k] description] forHTTPHeaderField:k];
            }
            NSString *body = ArgStr(a, @"body", nil);
            if (body.length) req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

            __block NSData *respData = nil;
            __block NSInteger code = 0;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithRequest:req
                completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                    respData = data;
                    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) code = ((NSHTTPURLResponse *)resp).statusCode;
                    dispatch_semaphore_signal(sem);
                }];
            [t resume];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(65 * NSEC_PER_SEC)));
            if (!respData) return @"请求超时或无响应";
            NSString *txt = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            if (!txt) txt = [NSString stringWithFormat:@"(二进制 %@)", [AAU humanBytes:respData.length]];
            return Cap([NSString stringWithFormat:@"HTTP %ld\n%@", (long)code, txt], 16000);
        }));

    // ----------------------------------------------------------------- misc
    [list addObject:T(@"clipboard_get", @"misc", @"读取系统剪贴板。", @{}, @[], ^NSString *(NSDictionary *a) {
        __block NSString *s = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{ s = [UIPasteboard generalPasteboard].string; });
        return s.length ? s : @"(剪贴板为空)";
    }));

    [list addObject:T(@"clipboard_set", @"misc", @"写入系统剪贴板。",
        @{@"text": P(@"string", @"内容")}, @[@"text"], ^NSString *(NSDictionary *a) {
            NSString *text = ArgStr(a, @"text", @"");
            dispatch_sync(dispatch_get_main_queue(), ^{ [UIPasteboard generalPasteboard].string = text; });
            return @"已写入剪贴板";
        }));

    [list addObject:T(@"wait", @"misc", @"等待若干秒（用于等待界面加载）。",
        @{@"seconds": P(@"number", @"秒，最大 30")}, @[@"seconds"], ^NSString *(NSDictionary *a) {
            double s = ArgNum(a, @"seconds", 1);
            if (s < 0) s = 0;
            if (s > 30) s = 30;
            [NSThread sleepForTimeInterval:s];
            return [NSString stringWithFormat:@"已等待 %.1f 秒", s];
        }));

    [list addObject:T(@"sys_info", @"misc", @"系统信息：型号、系统版本、内存、磁盘、电池。",
        @{}, @[], ^NSString *(NSDictionary *a) {
            NSMutableString *s = [NSMutableString string];
            UIDevice *d = [UIDevice currentDevice];
            [s appendFormat:@"device: %@ (%@)\n", d.model, d.name];
            [s appendFormat:@"system: %@ %@\n", d.systemName, d.systemVersion];
            [s appendFormat:@"screen: %.0fx%.0f @%.0fx\n", [UIScreen mainScreen].bounds.size.width,
                [UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].scale];
            NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
            if (fs) {
                [s appendFormat:@"disk free: %@ / total %@\n", [AAU humanBytes:[fs[NSFileSystemFreeSize] unsignedLongLongValue]],
                    [AAU humanBytes:[fs[NSFileSystemSize] unsignedLongLongValue]]];
            }
            unsigned long long mem = [NSProcessInfo processInfo].physicalMemory;
            [s appendFormat:@"ram: %@\n", [AAU humanBytes:mem]];
            [s appendFormat:@"uid: %d  pid: %d\n", getuid(), getpid()];
            [s appendFormat:@"jailbreak root: %@\n", [AAExecutor jbPrefix].length ? [AAExecutor jbPrefix] : @"(未检测到)"];
            [s appendFormat:@"shell: %@\n", [AAExecutor shellPath]];
            return s;
        }));

    [list addObject:T(@"task_done", @"misc",
        @"任务完成时调用，提交结果摘要并结束本轮。",
        @{@"summary": P(@"string", @"完成情况与关键结果")}, @[@"summary"], ^NSString *(NSDictionary *a) {
            return [NSString stringWithFormat:@"TASK_DONE:%@", ArgStr(a, @"summary", @"完成")];
        }));

    return list;
}

#pragma mark - Schemas

+ (NSArray *)openAISchemas {
    NSMutableArray *out = [NSMutableArray array];
    for (AATool *t in [self all]) {
        [out addObject:@{
            @"type": @"function",
            @"function": @{
                @"name": t.name,
                @"description": t.summary,
                @"parameters": t.schema,
            },
        }];
    }
    return out;
}

+ (NSArray *)anthropicSchemas {
    NSMutableArray *out = [NSMutableArray array];
    for (AATool *t in [self all]) {
        [out addObject:@{
            @"name": t.name,
            @"description": t.summary,
            @"input_schema": t.schema,
        }];
    }
    return out;
}

+ (NSString *)catalog {
    NSMutableString *s = [NSMutableString string];
    for (AATool *t in [self all]) {
        [s appendFormat:@"- %@ (%@): %@\n", t.name, t.category, t.summary];
    }
    return s;
}

+ (NSString *)runTool:(NSString *)name args:(NSDictionary *)args {
    AATool *t = [self toolNamed:name];
    if (!t) {
        NSMutableString *s = [NSMutableString stringWithFormat:@"未知工具: %@。可用工具:\n", name];
        [s appendString:[self catalog]];
        return s;
    }
    if (![args isKindOfClass:[NSDictionary class]]) args = @{};
    @try {
        NSString *r = t.handler(args);
        return r.length ? r : @"(无返回)";
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"工具 %@ 抛出异常: %@", name, e.reason ?: e.name];
    }
}

@end
