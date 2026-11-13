//
//  AAExecutor.m
//  Real process execution inside the host app (posix_spawn + pipes).
//  No simulation: this is the same syscall path a shell would take.
//

#import "Aether.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>

extern char **environ;

@implementation AAExecutor

+ (NSString *)jbPrefix {
    // roothide / rootless both expose their root through JBROOT or /var/jb.
    const char *env = getenv("JBROOT");
    if (env && strlen(env) > 1) return [NSString stringWithUTF8String:env];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/var/jb/usr/bin"]) return @"/var/jb";
    return @"";
}

+ (NSString *)shellPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *p = [self jbPrefix];
    NSMutableArray *cands = [NSMutableArray array];
    if (p.length) {
        [cands addObject:[p stringByAppendingString:@"/usr/bin/sh"]];
        [cands addObject:[p stringByAppendingString:@"/bin/sh"]];
        [cands addObject:[p stringByAppendingString:@"/usr/bin/bash"]];
    }
    [cands addObjectsFromArray:@[@"/var/jb/usr/bin/sh", @"/var/jb/bin/sh", @"/bin/sh", @"/usr/bin/sh"]];
    for (NSString *c in cands) {
        if ([fm isExecutableFileAtPath:c]) return c;
    }
    return @"/bin/sh";
}

+ (NSString *)environmentPath {
    NSString *p = [self jbPrefix];
    NSMutableArray *parts = [NSMutableArray array];
    if (p.length) {
        [parts addObject:[p stringByAppendingString:@"/usr/bin"]];
        [parts addObject:[p stringByAppendingString:@"/usr/sbin"]];
        [parts addObject:[p stringByAppendingString:@"/bin"]];
        [parts addObject:[p stringByAppendingString:@"/sbin"]];
    }
    [parts addObjectsFromArray:@[@"/var/jb/usr/bin", @"/var/jb/bin",
                                 @"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin",
                                 @"/usr/local/bin"]];
    return [parts componentsJoinedByString:@":"];
}

+ (NSString *)defaultCWD {
    return NSHomeDirectory();
}

+ (NSDictionary *)environmentWithCWD:(NSString *)cwd {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    for (char **e = environ; e && *e; e++) {
        NSString *kv = [NSString stringWithUTF8String:*e];
        if (!kv) continue;
        NSRange r = [kv rangeOfString:@"="];
        if (r.location == NSNotFound) continue;
        env[[kv substringToIndex:r.location]] = [kv substringFromIndex:r.location + 1];
    }
    env[@"PATH"] = [self environmentPath];
    env[@"HOME"] = NSHomeDirectory();
    env[@"TERM"] = @"xterm-256color";
    env[@"LANG"] = @"en_US.UTF-8";
    env[@"PWD"] = cwd ?: [self defaultCWD];
    env[@"AETHER"] = AETHER_VERSION;
    return env;
}

+ (NSString *)quote:(NSString *)s {
    NSString *q = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", q];
}

+ (NSString *)runInternal:(NSString *)command
                      cwd:(NSString *)cwd
                  timeout:(NSTimeInterval)timeout
                   onData:(void (^)(NSString *))onData
                    error:(NSString **)error {

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *workdir = cwd.length ? cwd : [self defaultCWD];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:workdir isDirectory:&isDir] || !isDir) workdir = [self defaultCWD];

    // cd inside the shell keeps the parent process untouched.
    NSString *script = [NSString stringWithFormat:@"cd %@ 2>/dev/null || cd %@; %@",
                        [self quote:workdir], [self quote:[self defaultCWD]], command];

    NSString *shell = [self shellPath];
    NSArray *args = @[shell, @"-lc", script];

    int fds[2];
    if (pipe(fds) != 0) {
        if (error) *error = @"pipe() 失败";
        return @"";
    }
    fcntl(fds[0], F_SETFL, O_NONBLOCK);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    posix_spawn_file_actions_addclose(&actions, fds[1]);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);

    NSUInteger argc = args.count;
    char **argv = calloc(argc + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argc; i++) argv[i] = strdup(args[i].UTF8String ?: "");
    argv[argc] = NULL;

    NSDictionary *envDict = [self environmentWithCWD:workdir];
    char **envp = calloc(envDict.count + 1, sizeof(char *));
    NSUInteger ei = 0;
    for (NSString *k in envDict) {
        NSString *kv = [NSString stringWithFormat:@"%@=%@", k, envDict[k]];
        envp[ei++] = strdup(kv.UTF8String ?: "");
    }
    envp[ei] = NULL;

    pid_t pid = 0;
    int rc = posix_spawn(&pid, shell.UTF8String, &actions, &attr, argv, envp);

    for (NSUInteger i = 0; i < argc; i++) free(argv[i]);
    free(argv);
    for (NSUInteger i = 0; i < ei; i++) free(envp[i]);
    free(envp);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    close(fds[1]);

    if (rc != 0) {
        close(fds[0]);
        if (error) *error = [NSString stringWithFormat:@"启动 %@ 失败 (errno %d)", shell, rc];
        return @"";
    }

    NSMutableData *out = [NSMutableData data];
    const NSUInteger kLimit = 512 * 1024;
    BOOL truncated = NO, timedOut = NO;
    NSTimeInterval deadlineAt = [[NSDate date] timeIntervalSince1970] + (timeout > 0 ? timeout : 30);

    while (1) {
        char buf[8192];
        ssize_t n = read(fds[0], buf, sizeof(buf));
        if (n > 0) {
            if (out.length < kLimit) [out appendBytes:buf length:(NSUInteger)n];
            else truncated = YES;
            if (onData) {
                NSString *s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding];
                if (!s) s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSISOLatin1StringEncoding];
                if (s.length) onData(s);
            }
            continue;
        }
        if (n == 0) break;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if ([[NSDate date] timeIntervalSince1970] > deadlineAt) {
                timedOut = YES;
                kill(-pid, SIGKILL);
                kill(pid, SIGKILL);
                break;
            }
            int st = 0;
            if (waitpid(pid, &st, WNOHANG) == pid) { pid = -1; break; }
            usleep(12000);
            continue;
        }
        break;
    }
    close(fds[0]);

    int status = 0;
    if (pid > 0) {
        NSTimeInterval hardStop = [[NSDate date] timeIntervalSince1970] + 3.0;
        while (waitpid(pid, &status, WNOHANG) == 0) {
            if ([[NSDate date] timeIntervalSince1970] > hardStop) {
                timedOut = YES;
                kill(-pid, SIGKILL);
                kill(pid, SIGKILL);
            }
            usleep(10000);
        }
    }
    if (timedOut) {
        [out appendData:[@"\n[aether] 命令超时，已终止\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    if (truncated) {
        [out appendData:[@"\n[aether] 输出超过 512KB，已截断\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }

    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:out encoding:NSISOLatin1StringEncoding];
    if (error && !timedOut && pid > 0 && WIFEXITED(status) && WEXITSTATUS(status) != 0) {
        *error = [NSString stringWithFormat:@"退出码 %d", WEXITSTATUS(status)];
    }
    return text ?: @"";
}

+ (NSString *)run:(NSString *)command
              cwd:(NSString *)cwd
          timeout:(NSTimeInterval)timeout
            error:(NSString **)error {
    if (!command.length) return @"";
    return [self runInternal:command cwd:cwd timeout:timeout onData:nil error:error];
}

+ (void)run:(NSString *)command
        cwd:(NSString *)cwd
    timeout:(NSTimeInterval)timeout
     onData:(void (^)(NSString *))onData
     onExit:(void (^)(int, BOOL))onExit {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *err = nil;
        [self runInternal:command cwd:cwd timeout:timeout onData:onData error:&err];
        if (onExit) {
            dispatch_async(dispatch_get_main_queue(), ^{ onExit(err ? 1 : 0, err != nil); });
        }
    });
}

@end
