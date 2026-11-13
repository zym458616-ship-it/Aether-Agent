//
//  AAUI.h
//  Internal UI interfaces shared between the overlay and its sub-views.
//

#ifndef AA_UI_H
#define AA_UI_H

#import "Aether.h"

@class AAPanel;

#pragma mark - Markdown-lite renderer

NSAttributedString *AARenderMarkdown(NSString *text, CGFloat size, UIColor *color);

#pragma mark - Chat

@interface AAChatView : UIView

@property (nonatomic, copy) void (^onSend)(NSString *text, BOOL withShot);
@property (nonatomic, copy) void (^onStop)(void);
@property (nonatomic, copy) void (^onNewTask)(void);

- (void)reload;
- (void)showEmptyState;
- (void)beginStreaming;
- (void)appendStream:(NSString *)text reasoning:(NSString *)reasoning;
- (void)endStreaming;
- (void)setStatus:(NSString *)status;
- (void)setUsage:(NSInteger)used max:(NSInteger)max;
- (void)setBusy:(BOOL)busy;
- (void)scrollToBottom;

@end

#pragma mark - Terminal

@interface AATerminalView : UIView
- (void)focusInput;
- (void)clear;
@end

#pragma mark - Settings

@interface AASettingsView : UIView
- (void)reloadUI;
@end

#pragma mark - History

@interface AAHistoryView : UIView
@property (nonatomic, copy) void (^onSelect)(NSString *sid);
- (void)reloadData;
@end

#pragma mark - Panel

@interface AAPanel : UIView

@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onHeightChange)(void);

- (void)selectTab:(NSInteger)tab;
- (void)refreshAll;
- (void)newTask;
- (void)setUsageProgress:(double)p;
@property (nonatomic, strong) AAChatView *chat;
@property (nonatomic, strong) AATerminalView *terminal;
@property (nonatomic, strong) AASettingsView *settings;
@property (nonatomic, strong) AAHistoryView *history;

- (void)setSession:(NSString *)sid;

@end

#endif
