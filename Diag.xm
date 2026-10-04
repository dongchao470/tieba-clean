//诊断模块：把窗口视图树 +候选类调用记录写到贴吧沙盒 Documents/tieba_diag.log
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

static NSString *TBCDiagPath(void) {
 static NSString *p = nil;
 if (!p) {
 p = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"tieba_diag.log"];
 }
 return p;
}

static void TBCDiagWrite(NSString *line) {
 if (line.length ==0) return;
 NSString *text = [line stringByAppendingString:@"\n"];
 NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
 if (!data) return;
 NSString *path = TBCDiagPath();
 NSFileManager *fm = [NSFileManager defaultManager];
 if (![fm fileExistsAtPath:path]) {
 [data writeToFile:path atomically:YES];
 return;
 }
 NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
 if (!fh) return;
 @try {
 [fh seekToEndOfFile];
 [fh writeData:data];
 } @catch (NSException *e) {
 }
 [fh closeFile];
}

static id TBCDiagSend(id obj, NSString *sel) {
 if (!obj) return nil;
 SEL s = NSSelectorFromString(sel);
 if (![obj respondsToSelector:s]) return nil;
 return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}

static NSString *TBCDiagStr(id v) {
 if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
 if (v) return [v description];
 return @"(nil)";
}

static BOOL TBCDiagHasKey(NSString *s) {
 if (s.length ==0) return NO;
 NSArray *keys = @[@"有料", @"直播", @"推荐", @"关注", @"视频", @"广告", @"精选"];
 for (NSString *k in keys) {
 if ([s containsString:k]) return YES;
 }
 return NO;
}

static NSString *TBCDiagFrameDesc(UIView *v, UIView *root) {
 CGRect f = v.frame;
 if (root && v.superview) f = [v convertRect:v.bounds toView:root];
 NSMutableString *s = [NSMutableString string];
 [s appendFormat:@"%@(%.0f,%.0f,%.0f,%.0f)", NSStringFromClass([v class]), f.origin.x, f.origin.y, f.size.width, f.size.height];
 if (v.hidden) [s appendString:@" HIDDEN"];
 if (v.alpha <0.99) [s appendFormat:@" alpha=%.2f", v.alpha];
 return s;
}

static void TBCDiagWalk(UIView *v, UIView *root, int depth, NSMutableArray *chain, NSMutableString *out, int *nodes) {
 if (!v || depth >14 || *nodes >5000) return;
 *nodes = *nodes +1;
 CGRect wf = root ? [v convertRect:v.bounds toView:root] : v.frame;
 NSMutableString *texts = [NSMutableString string];
 if ([v isKindOfClass:[UILabel class]]) {
 NSString *t = ((UILabel *)v).text;
 if (t.length) [texts appendFormat:@" label=\"%@\"", t];
 }
 if ([v isKindOfClass:[UIButton class]]) {
 NSString *t = [((UIButton *)v) titleForState:UIControlStateNormal];
 if (t.length) [texts appendFormat:@" btn=\"%@\"", t];
 }
 NSString *ax = v.accessibilityLabel;
 if (ax.length) [texts appendFormat:@" ax=\"%@\"", ax];
 BOOL topStrip = (wf.origin.y <220.0 && wf.size.width >6.0 && wf.size.height >6.0);
 BOOL matched = topStrip || TBCDiagHasKey(texts) || TBCDiagHasKey(ax);
 if (matched) {
 NSMutableString *line = [NSMutableString string];
 [line appendFormat:@"d=%d %@%@", depth, TBCDiagFrameDesc(v, root), texts.length ? texts : @""];
 NSUInteger cn = chain.count;
 NSUInteger from = cn >5 ? cn -5 :0;
 NSArray *tail = [chain subarrayWithRange:NSMakeRange(from, cn - from)];
 [line appendFormat:@" | chain: %@", [tail componentsJoinedByString:@" > "]];
 [out appendFormat:@"%@\n", line];
 }
 BOOL structural = (wf.size.width >30.0 && wf.size.height >16.0);
 if (structural) [chain addObject:TBCDiagFrameDesc(v, root)];
 for (UIView *sub in v.subviews) {
 TBCDiagWalk(sub, root, depth +1, chain, out, nodes);
 }
 if (structural) [chain removeLastObject];
}

static void TBCDumpTree(NSString *tag) {
 @autoreleasepool {
 UIApplication *app = [UIApplication sharedApplication];
 NSMutableArray *wins = [NSMutableArray array];
 if (app.keyWindow) [wins addObject:app.keyWindow];
 for (UIWindow *w in app.windows) {
 if (![wins containsObject:w]) [wins addObject:w];
 }
 NSMutableString *out = [NSMutableString string];
 [out appendFormat:@"\n===== TREE %@ wins=%lu =====\n", tag, (unsigned long)wins.count];
 for (UIWindow *w in wins) {
 NSMutableArray *chain = [NSMutableArray array];
 int nodes =0;
 [out appendFormat:@"-- window %@ hidden=%d level=%.0f frame=%@\n", NSStringFromClass([w class]), (int)w.hidden, w.windowLevel, NSStringFromCGRect(w.frame)];
 TBCDiagWalk(w, w,0, chain, out, &nodes);
 [out appendFormat:@"-- nodes=%d\n", nodes];
 }
 TBCDiagWrite(out);
 }
}

__attribute__((constructor)) static void TBCDiagInit(void) {
 @autoreleasepool {
 TBCDiagWrite([NSString stringWithFormat:@"\n######## diag init build=0.3.0-diag pid=%d########", (int)getpid()]);
 }
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ TBCDumpTree(@"t1_5"); });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ TBCDumpTree(@"t4"); });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(9.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ TBCDumpTree(@"t9"); });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ TBCDumpTree(@"t16"); });
}

@interface BLPRecommendFeedTabBar : UIView
- (void)initSubView;
- (void)configTabItems;
- (void)configWithFeedSource;
- (void)configMultiTabItem:(id)item;
- (id)createStartLiveButton;
- (void)setStartLiveButton:(id)button;
- (void)setupWithTabItems:(id)items tab:(id)tab;
- (id)startLiveButton;
@end

@interface BLPMultiTabBar : UIView
- (id)items;
- (void)setItems:(id)items;
@end

@interface BLPMultiTabItem : NSObject
- (id)title;
- (id)view;
@end

%hook BLPRecommendFeedTabBar

- (void)initSubView {
 TBCDiagWrite(@"HIT BLPRecommendFeedTabBar -initSubView");
 %orig;
}

- (void)configTabItems {
 TBCDiagWrite(@"HIT BLPRecommendFeedTabBar -configTabItems");
 %orig;
}

- (void)configWithFeedSource {
 TBCDiagWrite(@"HIT BLPRecommendFeedTabBar -configWithFeedSource");
 %orig;
}

- (void)configMultiTabItem:(id)item {
 TBCDiagWrite([NSString stringWithFormat:@"HIT -configMultiTabItem: %@ title=%@", NSStringFromClass([item class]), TBCDiagStr(TBCDiagSend(item, @"title"))]);
 %orig;
}

- (id)createStartLiveButton {
 id b = %orig;
 TBCDiagWrite([NSString stringWithFormat:@"HIT -createStartLiveButton -> %@", NSStringFromClass([b class])]);
 return b;
}

- (void)setStartLiveButton:(id)button {
 TBCDiagWrite([NSString stringWithFormat:@"HIT -setStartLiveButton: %@", NSStringFromClass([button class])]);
 %orig;
}

- (void)setupWithTabItems:(id)items tab:(id)tab {
 TBCDiagWrite([NSString stringWithFormat:@"HIT -setupWithTabItems:tab: items=%@", TBCDiagStr(items)]);
 %orig;
}

- (id)startLiveButton {
 id b = %orig;
 TBCDiagWrite([NSString stringWithFormat:@"HIT -startLiveButton -> %@", NSStringFromClass([b class])]);
 return b;
}

%end

%hook BLPMultiTabBar

- (id)items {
 id it = %orig;
 TBCDiagWrite([NSString stringWithFormat:@"HIT BLPMultiTabBar -items -> %@", TBCDiagStr(it)]);
 return it;
}

- (void)setItems:(id)items {
 TBCDiagWrite([NSString stringWithFormat:@"HIT BLPMultiTabBar -setItems: %@", TBCDiagStr(items)]);
 %orig;
}

%end

%hook BLPMultiTabItem

- (id)title {
 id t = %orig;
 TBCDiagWrite([NSString stringWithFormat:@"HIT BLPMultiTabItem -title -> %@", TBCDiagStr(t)]);
 return t;
}

%end
