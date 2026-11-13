//
//  AAStore.m
//  Session / message persistence on top of sqlite3 (real, queryable, durable).
//

#import "Aether.h"

#pragma mark - Models

@implementation AASession
@end

@implementation AAMessage
- (instancetype)init {
    self = [super init];
    if (self) {
        _mid = [[NSUUID UUID] UUIDString];
        _ts = [[NSDate date] timeIntervalSince1970];
        _role = @"user";
        _content = @"";
    }
    return self;
}
@end

#pragma mark - Tokenizer

@implementation AAToken

+ (NSInteger)count:(NSString *)text {
    if (!text.length) return 0;
    // Cheap but decent estimator: CJK runs ~1 token per char, latin ~1 per 4 chars.
    NSInteger cjk = 0, ascii = 0;
    NSUInteger len = text.length;
    unichar *buf = malloc(sizeof(unichar) * len);
    if (!buf) return len / 4 + 1;
    [text getCharacters:buf range:NSMakeRange(0, len)];
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = buf[i];
        if (c >= 0x2E80 && c <= 0x9FFF) cjk++;
        else if (c >= 0xAC00 && c <= 0xD7AF) cjk++;
        else if (c >= 0xFF00 && c <= 0xFFEF) cjk++;
        else ascii++;
    }
    free(buf);
    return cjk + (ascii / 4) + 1;
}

+ (NSInteger)countMessages:(NSArray<AAMessage *> *)msgs {
    NSInteger total = 0;
    for (AAMessage *m in msgs) {
        total += [self count:m.content] + [self count:m.toolArgs] + [self count:m.toolResult] + 6;
    }
    return total;
}

@end

#pragma mark - Store

@interface AAStore () {
    sqlite3 *_db;
}
@end

@implementation AAStore

+ (instancetype)shared {
    static AAStore *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[AAStore alloc] init]; [s bootstrap]; });
    return s;
}

- (void)dealloc {
    if (_db) sqlite3_close(_db);
}

- (void)bootstrap {
    if (_db) return;
    [AAU ensureDataDir];
    NSString *path = [[AAU dataDir] stringByAppendingPathComponent:@"aether.db"];
    if (sqlite3_open_v2(path.UTF8String, &_db,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        AALog(@"sqlite open failed: %s", sqlite3_errmsg(_db));
        return;
    }
    sqlite3_busy_timeout(_db, 3000);
    const char *sql1 =
        "CREATE TABLE IF NOT EXISTS sessions ("
        " sid TEXT PRIMARY KEY, title TEXT, created REAL, updated REAL, tokens INTEGER DEFAULT 0, steps INTEGER DEFAULT 0);";
    const char *sql2 =
        "CREATE TABLE IF NOT EXISTS messages ("
        " mid TEXT PRIMARY KEY, sid TEXT, role TEXT, content TEXT, reasoning TEXT,"
        " tool_name TEXT, tool_call_id TEXT, tool_args TEXT, tool_result TEXT,"
        " is_tool_call INTEGER DEFAULT 0, is_error INTEGER DEFAULT 0, ts REAL, tokens INTEGER DEFAULT 0);";
    const char *sql3 = "CREATE INDEX IF NOT EXISTS idx_msg_sid ON messages(sid, ts);";
    char *err = NULL;
    sqlite3_exec(_db, sql1, NULL, NULL, &err);
    if (err) { AALog(@"sql1 %s", err); sqlite3_free(err); err = NULL; }
    sqlite3_exec(_db, sql2, NULL, NULL, &err);
    if (err) { AALog(@"sql2 %s", err); sqlite3_free(err); err = NULL; }
    sqlite3_exec(_db, sql3, NULL, NULL, &err);
    if (err) { AALog(@"sql3 %s", err); sqlite3_free(err); err = NULL; }
}

#pragma mark sessions

- (NSArray<AASession *> *)sessions {
    [self bootstrap];
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "SELECT sid,title,created,updated,tokens,steps FROM sessions ORDER BY updated DESC;", -1, &st, NULL) != SQLITE_OK)
        return out;
    while (sqlite3_step(st) == SQLITE_ROW) {
        AASession *s = [[AASession alloc] init];
        const unsigned char *sid = sqlite3_column_text(st, 0);
        const unsigned char *title = sqlite3_column_text(st, 1);
        s.sid = sid ? @((const char *)sid) : @"";
        s.title = title ? @((const char *)title) : @"未命名任务";
        s.createdAt = sqlite3_column_double(st, 2);
        s.updatedAt = sqlite3_column_double(st, 3);
        s.tokens = sqlite3_column_int(st, 4);
        s.steps = sqlite3_column_int(st, 5);
        [out addObject:s];
    }
    sqlite3_finalize(st);
    return out;
}

- (AASession *)session:(NSString *)sid {
    if (!sid.length) return nil;
    [self bootstrap];
    AASession *s = nil;
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "SELECT sid,title,created,updated,tokens,steps FROM sessions WHERE sid=?1;", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(st) == SQLITE_ROW) {
            s = [[AASession alloc] init];
            s.sid = sid;
            const unsigned char *t = sqlite3_column_text(st, 1);
            s.title = t ? @((const char *)t) : @"未命名任务";
            s.createdAt = sqlite3_column_double(st, 2);
            s.updatedAt = sqlite3_column_double(st, 3);
            s.tokens = sqlite3_column_int(st, 4);
            s.steps = sqlite3_column_int(st, 5);
        }
    }
    sqlite3_finalize(st);
    return s;
}

- (AASession *)createSession:(NSString *)title {
    [self bootstrap];
    AASession *s = [[AASession alloc] init];
    s.sid = [[NSUUID UUID] UUIDString];
    s.title = title.length ? title : @"新任务";
    s.createdAt = s.updatedAt = [[NSDate date] timeIntervalSince1970];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "INSERT INTO sessions(sid,title,created,updated,tokens,steps) VALUES(?1,?2,?3,?4,0,0);", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, s.sid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(st, 2, s.title.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(st, 3, s.createdAt);
        sqlite3_bind_double(st, 4, s.updatedAt);
        if (sqlite3_step(st) != SQLITE_DONE) AALog(@"insert session: %s", sqlite3_errmsg(_db));
    }
    sqlite3_finalize(st);
    return s;
}

- (void)renameSession:(NSString *)sid title:(NSString *)title {
    if (!sid.length || !title.length) return;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "UPDATE sessions SET title=?2, updated=?3 WHERE sid=?1;", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(st, 2, title.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(st, 3, [[NSDate date] timeIntervalSince1970]);
        sqlite3_step(st);
    }
    sqlite3_finalize(st);
}

- (void)deleteSession:(NSString *)sid {
    if (!sid.length) return;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "DELETE FROM sessions WHERE sid=?1;", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(st);
    }
    sqlite3_finalize(st);
    if (sqlite3_prepare_v2(_db, "DELETE FROM messages WHERE sid=?1;", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(st);
    }
    sqlite3_finalize(st);
}

- (void)touchSession:(NSString *)sid tokens:(NSInteger)tokens steps:(NSInteger)steps {
    if (!sid.length) return;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "UPDATE sessions SET updated=?2, tokens=?3, steps=?4 WHERE sid=?1;", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(st, 2, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_int(st, 3, (int)tokens);
        sqlite3_bind_int(st, 4, (int)steps);
        sqlite3_step(st);
    }
    sqlite3_finalize(st);
}

#pragma mark messages

- (NSArray<AAMessage *> *)messages:(NSString *)sid {
    NSMutableArray *out = [NSMutableArray array];
    if (!sid.length) return out;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db,
        "SELECT mid,sid,role,content,reasoning,tool_name,tool_call_id,tool_args,tool_result,is_tool_call,is_error,ts,tokens"
        " FROM messages WHERE sid=?1 ORDER BY ts ASC, rowid ASC;", -1, &st, NULL) != SQLITE_OK)
        return out;
    sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
    while (sqlite3_step(st) == SQLITE_ROW) {
        AAMessage *m = [[AAMessage alloc] init];
        const unsigned char *c;
        c = sqlite3_column_text(st, 0); if (c) m.mid = @((const char *)c);
        c = sqlite3_column_text(st, 1); if (c) m.sid = @((const char *)c);
        c = sqlite3_column_text(st, 2); if (c) m.role = @((const char *)c);
        c = sqlite3_column_text(st, 3); if (c) m.content = @((const char *)c);
        c = sqlite3_column_text(st, 4); if (c) m.reasoning = @((const char *)c);
        c = sqlite3_column_text(st, 5); if (c) m.toolName = @((const char *)c);
        c = sqlite3_column_text(st, 6); if (c) m.toolCallId = @((const char *)c);
        c = sqlite3_column_text(st, 7); if (c) m.toolArgs = @((const char *)c);
        c = sqlite3_column_text(st, 8); if (c) m.toolResult = @((const char *)c);
        m.isToolCall = sqlite3_column_int(st, 9) != 0;
        m.isError = sqlite3_column_int(st, 10) != 0;
        m.ts = sqlite3_column_double(st, 11);
        m.tokens = sqlite3_column_int(st, 12);
        [out addObject:m];
    }
    sqlite3_finalize(st);
    return out;
}

- (void)insertMessage:(AAMessage *)m {
    if (!m || !m.sid.length) return;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    const char *sql = "INSERT OR REPLACE INTO messages"
        "(mid,sid,role,content,reasoning,tool_name,tool_call_id,tool_args,tool_result,is_tool_call,is_error,ts,tokens)"
        " VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13);";
    if (sqlite3_prepare_v2(_db, sql, -1, &st, NULL) != SQLITE_OK) return;
    sqlite3_bind_text(st, 1, m.mid.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, m.sid.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 3, m.role.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 4, m.content.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 5, m.reasoning.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 6, m.toolName.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 7, m.toolCallId.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 8, m.toolArgs.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 9, m.toolResult.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(st, 10, m.isToolCall ? 1 : 0);
    sqlite3_bind_int(st, 11, m.isError ? 1 : 0);
    sqlite3_bind_double(st, 12, m.ts);
    sqlite3_bind_int(st, 13, (int)m.tokens);
    if (sqlite3_step(st) != SQLITE_DONE) AALog(@"insert msg: %s", sqlite3_errmsg(_db));
    sqlite3_finalize(st);
}

- (void)updateMessage:(AAMessage *)m {
    if (!m || !m.mid.length) return;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    const char *sql = "UPDATE messages SET content=?2, reasoning=?3, tool_result=?4, is_error=?5, tokens=?6 WHERE mid=?1;";
    if (sqlite3_prepare_v2(_db, sql, -1, &st, NULL) != SQLITE_OK) return;
    sqlite3_bind_text(st, 1, m.mid.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, m.content.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 3, m.reasoning.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 4, m.toolResult.UTF8String ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(st, 5, m.isError ? 1 : 0);
    sqlite3_bind_int(st, 6, (int)m.tokens);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (void)deleteMessages:(NSString *)sid {
    if (!sid.length) return;
    [self bootstrap];
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, "DELETE FROM messages WHERE sid=?1;", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, sid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(st);
    }
    sqlite3_finalize(st);
}

@end
