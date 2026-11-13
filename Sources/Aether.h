//
//  Aether.h
//  Aether — in-app AI agent for jailbroken iOS (rootless / roothide)
//
//  A single header that declares every module boundary so that the whole
//  project can be compiled as a plain Mach-O dylib injected into any app.
//

#ifndef AETHER_H
#define AETHER_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <sqlite3.h>
#include <unistd.h>
#include <stdlib.h>

#define AETHER_VERSION      @"1.0.0"
#define AETHER_BUILD        @"1.0.0.1"

#define AALog(fmt, ...)     NSLog((@"[Aether] " fmt), ##__VA_ARGS__)

#pragma mark - Utilities / theme

@interface AAU : NSObject

+ (BOOL)isDark;

+ (UIColor *)bg;          // window backdrop
+ (UIColor *)card;        // raised surface
+ (UIColor *)card2;       // secondary surface (inputs)
+ (UIColor *)stroke;      // hairline
+ (UIColor *)text;
+ (UIColor *)textDim;
+ (UIColor *)accent;      // brand
+ (UIColor *)accent2;     // gradient partner
+ (UIColor *)ok;
+ (UIColor *)warn;
+ (UIColor *)err;

+ (UIFont *)ui:(CGFloat)size;
+ (UIFont *)ui:(CGFloat)size weight:(UIFontWeight)w;
+ (UIFont *)mono:(CGFloat)size;

+ (void)round:(UIView *)v radius:(CGFloat)r;
+ (void)border:(UIView *)v color:(UIColor *)c width:(CGFloat)w;
+ (void)blur:(UIView *)host style:(int)style;   // 0 = dark, 1 = light, 2 = ultra
+ (void)haptic:(NSInteger)style;               // 0 light 1 medium 2 heavy 3 success 4 error
+ (void)toast:(NSString *)text;

+ (NSString *)homePath;
+ (NSString *)dataDir;
+ (NSString *)ensureDataDir;
+ (NSString *)shortPath:(NSString *)path;
+ (NSString *)humanBytes:(unsigned long long)b;
+ (NSString *)humanTime:(NSTimeInterval)ts;
+ (UIColor *)colorForTool:(NSString *)name;

@end

#pragma mark - Config

@interface AAConfig : NSObject

+ (instancetype)shared;

@property (nonatomic, copy)   NSString *provider;      // "openai" | "anthropic"
@property (nonatomic, copy)   NSString *baseURL;
@property (nonatomic, copy)   NSString *apiKey;
@property (nonatomic, copy)   NSString *model;
@property (nonatomic, copy)   NSString *systemPrompt;
@property (nonatomic, assign) NSInteger maxContext;    // tokens, 0 = auto
@property (nonatomic, assign) NSInteger maxSteps;      // agent loop budget
@property (nonatomic, assign) double    temperature;
@property (nonatomic, assign) BOOL      stream;
@property (nonatomic, assign) BOOL      allowTools;
@property (nonatomic, assign) BOOL      visionInput;
@property (nonatomic, assign) BOOL      showReasoning;
@property (nonatomic, assign) BOOL      autoApprove;
@property (nonatomic, assign) BOOL      haptics;
@property (nonatomic, assign) double    ballOpacity;
@property (nonatomic, assign) CGPoint   ballCenter;
@property (nonatomic, assign) BOOL      ballHidden;
@property (nonatomic, copy)   NSString *lastSessionID;

- (void)save;
- (void)reset;
- (BOOL)isConfigured;
- (NSInteger)effectiveMaxContext;
- (NSDictionary *)requestHeaders;

@end

#pragma mark - Models

@interface AASession : NSObject
@property (nonatomic, copy) NSString *sid;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, assign) NSInteger tokens;
@property (nonatomic, assign) NSInteger steps;
@end

@interface AAMessage : NSObject
@property (nonatomic, copy) NSString *mid;
@property (nonatomic, copy) NSString *sid;
@property (nonatomic, copy) NSString *role;          // system|user|assistant|tool
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSString *reasoning;
@property (nonatomic, copy) NSString *toolName;
@property (nonatomic, copy) NSString *toolCallId;
@property (nonatomic, copy) NSString *toolArgs;
@property (nonatomic, copy) NSString *toolResult;
@property (nonatomic, assign) BOOL     isToolCall;
@property (nonatomic, assign) BOOL     isError;
@property (nonatomic, assign) BOOL     pending;
@property (nonatomic, assign) NSTimeInterval ts;
@property (nonatomic, assign) NSInteger tokens;
@end

@interface AAStore : NSObject

+ (instancetype)shared;

- (void)bootstrap;

- (NSArray<AASession *> *)sessions;
- (AASession *)session:(NSString *)sid;
- (AASession *)createSession:(NSString *)title;
- (void)renameSession:(NSString *)sid title:(NSString *)title;
- (void)deleteSession:(NSString *)sid;
- (void)touchSession:(NSString *)sid tokens:(NSInteger)tokens steps:(NSInteger)steps;

- (NSArray<AAMessage *> *)messages:(NSString *)sid;
- (void)insertMessage:(AAMessage *)m;
- (void)updateMessage:(AAMessage *)m;
- (void)deleteMessages:(NSString *)sid;

@end

#pragma mark - Tokenizer

@interface AAToken : NSObject
+ (NSInteger)count:(NSString *)text;
+ (NSInteger)countMessages:(NSArray<AAMessage *> *)msgs;
@end

#pragma mark - Network client

typedef void (^AADeltaBlock)(NSString *text, NSString *reasoning);
typedef void (^AAToolBlock)(NSArray<NSDictionary *> *calls);   // {id,name,args}
typedef void (^AAUsageBlock)(NSInteger prompt, NSInteger completion);
typedef void (^AAFinishBlock)(NSError *error);

@interface AAClient : NSObject

+ (instancetype)shared;

- (void)fetchModels:(void (^)(NSArray<NSString *> *models, NSError *error))done;

- (void)sendMessages:(NSArray *)messages           // AAMessage list
                tools:(NSArray *)tools             // AATool list
              onDelta:(AADeltaBlock)onDelta
             onToolCall:(AAToolBlock)onTool
                onUsage:(AAUsageBlock)onUsage
               onFinish:(AAFinishBlock)onFinish;

- (void)cancel;
- (BOOL)isBusy;

@end

#pragma mark - Shell executor

@interface AAExecutor : NSObject

+ (NSString *)shellPath;
+ (NSString *)defaultCWD;
+ (NSString *)environmentPath;

// Blocking; returns combined stdout+stderr.
+ (NSString *)run:(NSString *)command
              cwd:(NSString *)cwd
          timeout:(NSTimeInterval)timeout
            error:(NSString **)error;

// Streaming; callbacks fire on a background queue.
+ (void)run:(NSString *)command
        cwd:(NSString *)cwd
    timeout:(NSTimeInterval)timeout
     onData:(void (^)(NSString *chunk))onData
     onExit:(void (^)(int status, BOOL timedOut))onExit;

@end

#pragma mark - UI automation bridge

@interface AAElement : NSObject
@property (nonatomic, copy) NSString *eid;      // stable id usable by ui_tap_element
@property (nonatomic, copy) NSString *cls;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *image;
@property (nonatomic, assign) CGRect frame;     // screen coords
@property (nonatomic, assign) BOOL tappable;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, assign) NSInteger index;
@end

@interface AAUIBridge : NSObject

+ (instancetype)shared;

- (NSArray<AAElement *> *)dumpHierarchy;
- (NSString *)hierarchyDescription;                     // compact text tree
- (NSArray<AAElement *> *)find:(NSString *)query;

- (BOOL)tapPoint:(CGPoint)pt;
- (BOOL)swipeFrom:(CGPoint)a to:(CGPoint)b duration:(double)duration;
- (BOOL)longPress:(CGPoint)pt duration:(double)duration;
- (BOOL)tapElement:(NSString *)eid;
- (BOOL)inputText:(NSString *)text;
- (BOOL)scrollBy:(CGFloat)dy;

- (UIImage *)screenshot;
- (BOOL)saveScreenshot:(NSString *)path;

+ (NSString *)foregroundBundleID;
+ (NSDictionary *)appInfo;

@end

#pragma mark - Tools

@interface AATool : NSObject
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *summary;
@property (nonatomic, strong) NSDictionary *schema;     // {type:object, properties:..., required:...}
@property (nonatomic, copy)   NSString *category;       // shell|fs|ui|app|net|misc
@property (nonatomic, copy)   NSString *(^handler)(NSDictionary *args);
@end

@interface AATools : NSObject
+ (NSArray<AATool *> *)all;
+ (AATool *)toolNamed:(NSString *)name;
+ (NSString *)runTool:(NSString *)name args:(NSDictionary *)args;
+ (NSArray *)openAISchemas;
+ (NSArray *)anthropicSchemas;
+ (NSString *)catalog;
@end

#pragma mark - Agent

@interface AAAgent : NSObject

+ (instancetype)shared;

@property (nonatomic, copy) void (^onDelta)(NSString *text, NSString *reasoning);
@property (nonatomic, copy) void (^onToolStart)(AAMessage *call);
@property (nonatomic, copy) void (^onToolEnd)(AAMessage *call);
@property (nonatomic, copy) void (^onStatus)(NSString *status);
@property (nonatomic, copy) void (^onUsage)(NSInteger used, NSInteger max);
@property (nonatomic, copy) void (^onFinish)(NSString *error);
@property (nonatomic, readonly) BOOL running;

- (void)startTask:(NSString *)task session:(NSString *)sid;
- (void)cancel;

@end

#pragma mark - Overlay / UI

@interface AAOverlay : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) UIView *container;
@property (nonatomic, readonly) UIWindow *window;

+ (void)boot;                       // attach to the current app
- (void)showBall:(BOOL)show;
- (void)openPanel;
- (void)closePanel;
- (BOOL)isPanelOpen;
- (void)pulse;

- (UIEdgeInsets)safeInsets;
- (void)reloadChat;

@end

#endif /* AETHER_H */
