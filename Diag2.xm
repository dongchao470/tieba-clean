// TiebaClean diag v0.4.0 - deep tree + TBC segment hooks + hedged tab filter
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

static NSString *gPath = nil;
static NSMutableString *gBuf = nil;
static NSLock *gLock = nil;
static int gLines =0;
static const int gMaxLines =8000;

static void D2Init(void) {
 if (gPath) return;
 gLock = [NSLock new];
 gBuf = [NSMutableString new];
 gPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"tieba_diag.log"];
 remove([gPath fileSystemRepresentation]);
}

static void D2W(NSString *s) {
 D2Init();
 if (!s) return;
 [gLock lock];
 if (gLines < gMaxLines) {
 [gBuf appendString:s];
 [gBuf appendString:@"\n"];
 gLines++;
 } else if (gLines == gMaxLines) {
 [gBuf appendString:@"[LOG CAPPED]\n"];
 gLines++;
 }
 NSString *out = [gBuf copy];
 [gBuf setString:@""];
 [gLock unlock];
 if (out.length ==0) return;
 NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gPath];
 if (!fh) {
 [@"" writeToFile:gPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
 fh = [NSFileHandle fileHandleForWritingAtPath:gPath];
 }
 [fh seekToEndOfFile];
 [fh writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
 [fh closeFile];
}

static void D2F(NSString *fmt, ...) {
 va_list ap;
 va_start(ap, fmt);
 NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
 va_end(ap);
 D2W(s);
}

static id D2Msg(id o, const char *name) {
 if (!o) return nil;
 SEL sel = sel_registerName(name);
 if (![o respondsToSelector:sel]) return nil;
 return ((id (*)(id, SEL))objc_msgSend)(o, sel);
}

static NSString *D2Str(id o, const char *name) {
 id v = D2Msg(o, name);
 return [v isKindOfClass:[NSString class]] ? (NSString *)v : nil;
}

static NSString *D2Text(id v) {
 if (!v) return nil;
 NSString *s = D2Str(v, "text");
 if (s) return s;
 s = D2Str(v, "currentTitle");
 if (s) return s;
 return D2Str(v, "title");
}

static NSString *D2ItemName(id it) {
 NSString *s = D2Str(it, "name");
 if (s) return s;
 s = D2Str(it, "title");
 if (s) return s;
 return D2Str(it, "tabName");
}

static BOOL D2Banned(NSString *s) {
 if (![s isKindOfClass:[NSString class]]) return NO;
 NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if (t.length ==0) return NO;
 if ([t isEqualToString:@"有料"]) return YES;
 if ([t isEqualToString:@"直播"]) return YES;
 return [t isEqualToString:@"有料°"];
}

static NSString *D2Names(NSArray *a) {
 if (![a isKindOfClass:[NSArray class]]) return @"-";
 NSMutableArray *o = [NSMutableArray array];
 for (id it in a) {
 NSString *n = D2ItemName(it);
 NSString *cn = NSStringFromClass([it class]);
 [o addObject:(n ? [NSString stringWithFormat:@"%@(%@)", n, cn] : cn)];
 }
 return [o componentsJoinedByString:@"|"];
}

static NSArray *D2Filter(NSArray *a, NSString *tag) {
 if (![a isKindOfClass:[NSArray class]] || a.count ==0) return a;
 NSMutableArray *keep = [NSMutableArray array];
 NSMutableArray *drop = [NSMutableArray array];
 for (id it in a) {
 NSString *n = D2ItemName(it);
 if (D2Banned(n)) [drop addObject:n];
 else [keep addObject:it];
 }
 if (drop.count >0) {
 D2F(@"[FILTER %@] before=%lu after=%lu drop=%@", tag, (unsigned long)a.count, (unsigned long)keep.count, [drop componentsJoinedByString:@"+"]);
 return keep;
 }
 return a;
}

static BOOL D2InTabArea(UIView *v) {
 UIView *p = v;
 int n =0;
 while (p && n <24) {
 NSString *cn = NSStringFromClass([p class]);
 if ([cn rangeOfString:@"Choiceness"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"HomeChange"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"Segment"].location != NSNotFound) return YES;
 p = [p superview];
 n++;
 }
 return NO;
}

static void D2Dump(UIView *v, int d, NSMutableString *sb) {
 if (!v || d >30) return;
 if (sb.length >120000) return;
 NSString *cn = NSStringFromClass([v class]);
 NSString *t = D2Text(v);
 NSMutableString *pad = [NSMutableString string];
 for (int i =0; i < d; i++) [pad appendString:@"| "];
 [sb appendFormat:@"%@%@(%.0f,%.0f,%.0f,%.0f)", pad, cn, v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height];
 if (t.length >0) [sb appendFormat:@" \"%@\"", t];
 if (v.hidden) [sb appendString:@" HIDDEN"];
 if (v.alpha <0.05) [sb appendString:@" ALPHA0"];
 if (v.accessibilityLabel.length >0) [sb appendFormat:@" ax=%@", v.accessibilityLabel];
 [sb appendString:@"\n"];
 for (UIView *s in v.subviews) D2Dump(s, d +1, sb);
}

static void D2FocusWalk(UIView *v, int d, NSMutableString *sb) {
 if (!v || d >40 || sb.length >120000) return;
 NSString *cn = NSStringFromClass([v class]);
 BOOL hit = NO;
 if ([cn rangeOfString:@"Choiceness"].location != NSNotFound) hit = YES;
 if ([cn rangeOfString:@"HomeChange"].location != NSNotFound) hit = YES;
 if ([cn rangeOfString:@"Segment"].location != NSNotFound) hit = YES;
 if ([cn rangeOfString:@"TabBar"].location != NSNotFound) hit = YES;
 if (hit) {
 [sb appendFormat:@"--FOCUS %@\n", cn];
 D2Dump(v, d, sb);
 }
 for (UIView *s in v.subviews) D2FocusWalk(s, d +1, sb);
}

static void D2Scan(UIView *v, int d, NSMutableString *sb) {
 if (!v || d >30) return;
 NSString *t = D2Text(v);
 if (D2Banned(t) && D2InTabArea(v)) {
 [sb appendFormat:@" KILL %@ frame=%.0f,%.0f,%.0f,%.0f text=%@ parent=%@", NSStringFromClass([v class]), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height, t, NSStringFromClass([[v superview] class])];
 v.hidden = YES;
 v.alpha =0.0;
 }
 for (UIView *s in v.subviews) D2Scan(s, d +1, sb);
}

static void D2DumpWindows(NSString *tag) {
 NSArray *ws = [[UIApplication sharedApplication] windows];
 NSMutableString *sb = [NSMutableString string];
 [sb appendFormat:@"===== DUMP %@ windows=%lu =====", tag, (unsigned long)ws.count];
 [sb appendString:@"\n"];
 for (UIWindow *w in ws) D2Dump(w,0, sb);
 D2W(sb);
}

static void D2Focus(void) {
 NSArray *ws = [[UIApplication sharedApplication] windows];
 NSMutableString *sb = [NSMutableString string];
 for (UIWindow *w in ws) D2FocusWalk(w,0, sb);
 if (sb.length >0) D2F(@"===== FOCUS =====\n%@", sb);
}

static void D2KillScan(void) {
 NSArray *ws = [[UIApplication sharedApplication] windows];
 NSMutableString *sb = [NSMutableString string];
 for (UIWindow *w in ws) D2Scan(w,0, sb);
 if (sb.length >0) D2F(@"[KILLSCAN]\n%@", sb);
}

@interface D2Runner : NSObject
- (void)tick1;
- (void)tick2;
- (void)tick3;
- (void)tick4;
- (void)tick5;
@end

@implementation D2Runner
- (void)tick1 { D2DumpWindows(@"t3"); D2Focus(); D2KillScan(); }
- (void)tick2 { D2Focus(); D2KillScan(); }
- (void)tick3 { D2Focus(); D2KillScan(); }
- (void)tick4 { D2DumpWindows(@"t16"); D2Focus(); D2KillScan(); }
- (void)tick5 { D2DumpWindows(@"t28"); D2Focus(); D2KillScan(); }
@end

%hook TBCChoicenessTypeBHeaderView
- (void)setSegmentView:(UIView *)v { D2F(@"[HIT] TypeBHeader setSegmentView class=%@ frame=%.0f,%.0f,%.0f,%.0f", NSStringFromClass([v class]), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height); %orig; }
- (void)setSegmentGradientView:(UIView *)v { D2F(@"[HIT] TypeBHeader setSegmentGradientView class=%@", NSStringFromClass([v class])); %orig; }
- (void)setRightButtonsContainer:(UIView *)v { D2F(@"[HIT] TypeBHeader setRightButtonsContainer class=%@", NSStringFromClass([v class])); %orig; }
- (void)setLiveView:(UIView *)v { D2F(@"[HIT] TypeBHeader setLiveView class=%@", NSStringFromClass([v class])); %orig; }
- (void)layoutSegmentContentView { D2F(@"[HIT] TypeBHeader layoutSegmentContentView"); %orig; }
- (void)layoutSegmentViewAndRightButtons { D2F(@"[HIT] TypeBHeader layoutSegmentViewAndRightButtons"); %orig; }
- (void)clickLiveBtn { D2F(@"[HIT] TypeBHeader clickLiveBtn"); %orig; }
%end

%hook TBCChoicenessHeaderView
- (void)setSegmentView:(UIView *)v { D2F(@"[HIT] ChoicenessHeader setSegmentView class=%@", NSStringFromClass([v class])); %orig; }
%end

%hook TBCHomeChangeHeaderView
- (void)setAdvancedTabName:(NSString *)n { D2F(@"[HIT] HomeChangeHeader setAdvancedTabName=%@", n); %orig; }
- (void)setTabName:(NSString *)n { D2F(@"[HIT] HomeChangeHeader setTabName=%@", n); %orig; }
%end

%hook TBCSegmentView
- (void)setDataSource:(id)o { D2F(@"[HIT] TBCSegmentView setDataSource=%@", NSStringFromClass([o class])); %orig; }
- (void)setDelegate:(id)o { D2F(@"[HIT] TBCSegmentView setDelegate=%@", NSStringFromClass([o class])); %orig; }
- (void)setItems:(NSArray *)a { D2F(@"[HIT] TBCSegmentView setItems %@", D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setItems")); }
- (void)setTabItems:(NSArray *)a { D2F(@"[HIT] TBCSegmentView setTabItems %@", D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setTabItems")); }
- (void)setSegmentItems:(NSArray *)a { D2F(@"[HIT] TBCSegmentView setSegmentItems %@", D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setSegmentItems")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] TBCSegmentView setTabs %@", D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setTabs")); }
%end

%hook TBCScrollSegmentView
- (void)setDataSource:(id)o { D2F(@"[HIT] ScrollSegmentView setDataSource=%@", NSStringFromClass([o class])); %orig; }
- (void)setDelegate:(id)o { D2F(@"[HIT] ScrollSegmentView setDelegate=%@", NSStringFromClass([o class])); %orig; }
- (void)setItems:(NSArray *)a { D2F(@"[HIT] ScrollSegmentView setItems %@", D2Names(a)); %orig(D2Filter(a, @"ScrollSegmentView.setItems")); }
- (void)setTabItems:(NSArray *)a { D2F(@"[HIT] ScrollSegmentView setTabItems %@", D2Names(a)); %orig(D2Filter(a, @"ScrollSegmentView.setTabItems")); }
- (void)setSegmentItems:(NSArray *)a { D2F(@"[HIT] ScrollSegmentView setSegmentItems %@", D2Names(a)); %orig(D2Filter(a, @"ScrollSegmentView.setSegmentItems")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] ScrollSegmentView setTabs %@", D2Names(a)); %orig(D2Filter(a, @"ScrollSegmentView.setTabs")); }
%end

%hook TBCSegmentTabsView
- (id)initWithFrame:(CGRect)f tabs:(NSArray *)tabs { D2F(@"[HIT] TabsView init tabs=%@", D2Names(tabs)); return %orig(f, D2Filter(tabs, @"TabsView.init")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] TabsView setTabs %@", D2Names(a)); %orig(D2Filter(a, @"TabsView.setTabs")); }
%end

%hook TBCSecondBarSegmentView
- (id)initWithFrame:(CGRect)f andItems:(NSArray *)items { D2F(@"[HIT] SecondBar init items=%@", D2Names(items)); return %orig(f, D2Filter(items, @"SecondBar.init")); }
- (void)setSegmentItems:(NSArray *)a { D2F(@"[HIT] SecondBar setSegmentItems %@", D2Names(a)); %orig(D2Filter(a, @"SecondBar.setSegmentItems")); }
- (void)setSegmentItemsArray:(NSArray *)a { D2F(@"[HIT] SecondBar setSegmentItemsArray %@", D2Names(a)); %orig(D2Filter(a, @"SecondBar.setSegmentItemsArray")); }
%end

%hook TBCSegmentedControl
- (void)setItems:(NSArray *)a { D2F(@"[HIT] SegmentedControl setItems %@", D2Names(a)); %orig(D2Filter(a, @"SegmentedControl.setItems")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] SegmentedControl setTabs %@", D2Names(a)); %orig(D2Filter(a, @"SegmentedControl.setTabs")); }
%end

%hook TBCSlideSegmentControl
- (void)setItems:(NSArray *)a { D2F(@"[HIT] SlideSegmentControl setItems %@", D2Names(a)); %orig(D2Filter(a, @"SlideSegmentControl.setItems")); }
%end

%hook TBCSegmentedLabelConfig
- (void)setText:(NSString *)t { D2F(@"[HIT] LabelConfig setText=%@", t); %orig; }
%end

%hook TBCSegmentedLabel
- (void)bindData:(id)d { D2F(@"[HIT] SegmentedLabel bindData class=%@ text=%@", NSStringFromClass([d class]), D2Text(d)); %orig; }
- (void)setText:(NSString *)t { D2F(@"[HIT] SegmentedLabel setText=%@", t); %orig; }
%end

%hook TBCSegmentTabsItem
- (void)setName:(NSString *)n { D2F(@"[HIT] TabsItem setName=%@", n); %orig; }
%end

%hook TBCSegmentTabsCell
- (void)bindItem:(id)it { D2F(@"[HIT] TabsCell bindItem name=%@", D2ItemName(it)); %orig; }
%end

%ctor {
 @autoreleasepool {
 D2Init();
 D2F(@"######## TiebaClean diag v0.4.0 pid=%d path=%@########", getpid(), gPath);
 D2Runner *r = [D2Runner new];
 [NSTimer scheduledTimerWithTimeInterval:2.0 target:r selector:@selector(tick1) userInfo:nil repeats:NO];
 [NSTimer scheduledTimerWithTimeInterval:5.0 target:r selector:@selector(tick2) userInfo:nil repeats:NO];
 [NSTimer scheduledTimerWithTimeInterval:9.0 target:r selector:@selector(tick3) userInfo:nil repeats:NO];
 [NSTimer scheduledTimerWithTimeInterval:16.0 target:r selector:@selector(tick4) userInfo:nil repeats:NO];
 [NSTimer scheduledTimerWithTimeInterval:28.0 target:r selector:@selector(tick5) userInfo:nil repeats:NO];
 }
}
