// TiebaClean Diag2 v0.4.0 — deep tree dump + TBC segment hooks + hedged data-array filter
//目标：1)打印顶栏真实视图类名(深度30)2)若命中数据数组则直接删除有料/直播
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *gPath = nil;
static NSLock *gLock = nil;
static int gCount =0;
static const int gMax =8000;

static void D2Init(void) {
 if (gPath) return;
 gLock = [NSLock new];
 gPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"tieba_diag2.log"];
 remove([gPath fileSystemRepresentation]);
 [@"" writeToFile:gPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void D2W(NSString *s) {
 if (!s.length) return;
 D2Init();
 [gLock lock];
 if (gCount >= gMax) { [gLock unlock]; return; }
 gCount++;
 NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gPath];
 [fh seekToEndOfFile];
 [fh writeData:[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
 [fh closeFile];
 [gLock unlock];
}

static void D2F(NSString *fmt, ...) {
 va_list ap; va_start(ap, fmt);
 NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
 va_end(ap);
 D2W(s);
}

static NSString *D2Text(id v) {
 if (!v) return nil;
 @try {
 if ([v isKindOfClass:[UILabel class]]) return [(UILabel *)v text];
 if ([v respondsToSelector:@selector(currentTitle)]) { id t = [v performSelector:@selector(currentTitle)]; if ([t isKindOfClass:[NSString class]]) return t; }
 if ([v respondsToSelector:@selector(titleForState:)]) { id t = [v performSelector:@selector(titleForState:) withObject:(id)0]; if ([t isKindOfClass:[NSString class]]) return t; }
 if ([v respondsToSelector:@selector(title)]) { id t = [v performSelector:@selector(title)]; if ([t isKindOfClass:[NSString class]]) return t; }
 if ([v respondsToSelector:@selector(text)]) { id t = [v performSelector:@selector(text)]; if ([t isKindOfClass:[NSString class]]) return t; }
 } @catch (__unused NSException *e) {}
 return nil;
}

static BOOL D2IsRemoved(NSString *s) {
 if (![s isKindOfClass:[NSString class]]) return NO;
 NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if ([t isEqualToString:@"有料"] || [t isEqualToString:@"直播"] || [t isEqualToString:@"有料°"] || [t isEqualToString:@"有料·"] || [t isEqualToString:@"LIVE"] || [t isEqualToString:@"live"]) return YES;
 return NO;
}

static NSString *D2ItemName(id it) {
 if (!it) return nil;
 @try {
 NSArray *sels = @[ @"name", @"title", @"tabName", @"tabTitle", @"text", @"displayName", @"segmentTitle" ];
 for (NSString *sn in sels) {
 if ([it respondsToSelector:NSSelectorFromString(sn)]) {
 id n = [it performSelector:NSSelectorFromString(sn)];
 if ([n isKindOfClass:[NSString class]] && [(NSString *)n length]) return n;
 }
 }
 } @catch (__unused NSException *e) {}
 return nil;
}

static NSString *D2Names(NSArray *a) {
 NSMutableArray *o = [NSMutableArray array];
 if ([a isKindOfClass:[NSArray class]]) {
 for (id it in a) {
 NSString *n = D2ItemName(it);
 [o addObject:(n ? [NSString stringWithFormat:@"%@<%@>", n, NSStringFromClass([it class])] : NSStringFromClass([it class]))];
 }
 }
 return [o componentsJoinedByString:@" | "];
}

static NSArray *D2Filter(NSArray *a, NSString *tag) {
 if (![a isKindOfClass:[NSArray class]] || a.count ==0) return a;
 NSMutableArray *out = [NSMutableArray array];
 NSMutableArray *dropped = [NSMutableArray array];
 for (id it in a) {
 NSString *n = D2ItemName(it);
 if (D2IsRemoved(n)) [dropped addObject:n];
 else [out addObject:it];
 }
 if (dropped.count) {
 D2F(@"[FILTER %@] %lu -> %lu dropped=%@", tag, (unsigned long)a.count, (unsigned long)out.count, dropped);
 return out;
 }
 return a;
}

static NSString *D2Chain(UIView *v) {
 NSMutableArray *a = [NSMutableArray array];
 UIView *c = v;
 int i =0;
 while (c && i <14) { [a addObject:NSStringFromClass([c class])]; c = [c superview]; i++; }
 return [a componentsJoinedByString:@" < "];
}

static BOOL D2AncestorLooksLikeTabBar(UIView *v) {
 UIView *c = v;
 int i =0;
 while (c && i <12) {
 NSString *cn = NSStringFromClass([c class]);
 if ([cn rangeOfString:@"Choiceness"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"HomeChange"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"Segment"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"TabBar"].location != NSNotFound) return YES;
 c = [c superview]; i++;
 }
 return NO;
}

static void D2Dump(UIView *v, int d, NSMutableString *sb) {
 if (!v || d >30) return;
 if (sb.length >30000) { [sb appendString:@"...TRUNC...\n"]; return; }
 NSString *txt = D2Text(v);
 NSMutableString *pad = [NSMutableString string];
 for (int i =0; i < d; i++) [pad appendString:@" "];
 [sb appendFormat:@"%@%@(%.0f,%.0f,%.0f,%.0f)", pad, NSStringFromClass([v class]), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height];
 if (v.hidden) [sb appendString:@" HIDDEN"];
 if (v.alpha <1.0) [sb appendFormat:@" alpha=%.2f", v.alpha];
 if (txt) [sb appendFormat:@" \"%@\"", txt];
 if (v.accessibilityLabel.length) [sb appendFormat:@" ax=\"%@\"", v.accessibilityLabel];
 [sb appendString:@"\n"];
 for (UIView *s in v.subviews) D2Dump(s, d +1, sb);
}

static void D2Focus(UIView *v, int d, NSMutableString *sb) {
 if (!v || d >40) return;
 NSString *cn = NSStringFromClass([v class]);
 BOOL hit = ([cn rangeOfString:@"Choiceness"].location != NSNotFound)
 || ([cn rangeOfString:@"HomeChange"].location != NSNotFound)
 || ([cn rangeOfString:@"SecondBar"].location != NSNotFound)
 || ([cn rangeOfString:@"ScrollSegment"].location != NSNotFound)
 || ([cn rangeOfString:@"SegmentTabs"].location != NSNotFound);
 if (hit) {
 [sb appendFormat:@"---- FOCUS %@ frame=%.0f,%.0f,%.0f,%.0f chain=%@\n", cn, v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height, D2Chain(v)];
 D2Dump(v,0, sb);
 }
 for (UIView *s in v.subviews) D2Focus(s, d +1, sb);
}

static NSArray *D2Windows(void) {
 NSMutableArray *ws = [NSMutableArray array];
 @try {
 for (UIWindow *w in [[UIApplication sharedApplication] windows]) [ws addObject:w];
 if (ws.count ==0) { UIWindow *k = [[UIApplication sharedApplication] keyWindow]; if (k) [ws addObject:k]; }
 } @catch (__unused NSException *e) {}
 return ws;
}

static void D2DumpAll(NSString *tag) {
 @autoreleasepool {
 NSMutableString *sb = [NSMutableString string];
 NSArray *ws = D2Windows();
 [sb appendFormat:@"===== DUMP %@ windows=%lu =====", tag, (unsigned long)ws.count];
 for (UIView *w in ws) D2Dump(w,0, sb);
 D2W(sb);
 }
}

static void D2FocusAll(NSString *tag) {
 @autoreleasepool {
 NSMutableString *sb = [NSMutableString string];
 [sb appendFormat:@"===== FOCUS %@ =====", tag];
 for (UIView *w in D2Windows()) D2Focus(w,0, sb);
 D2W(sb);
 }
}

//扫一遍：把文本为有料/直播的控件就地收掉，并记录它的真实类名与父链
static int D2KillScan(UIView *v, int d) {
 if (!v || d >30) return0;
 int n =0;
 @try {
 NSString *txt = D2Text(v);
 if (D2IsRemoved(txt) && D2AncestorLooksLikeTabBar(v)) {
 D2F(@"[KILL] class=%@ frame=%.0f,%.0f,%.0f,%.0f text=%@ chain=%@", NSStringFromClass([v class]), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height, txt, D2Chain(v));
 v.hidden = YES;
 v.alpha =0.0;
 n++;
 }
 } @catch (__unused NSException *e) {}
 for (UIView *s in v.subviews) n += D2KillScan(s, d +1);
 return n;
}

static void D2KillAll(NSString *tag) {
 int n =0;
 for (UIView *w in D2Windows()) n += D2KillScan(w,0);
 if (n) D2F(@"[KILLSCAN %@] killed=%d", tag, n);
}

%hook TBCChoicenessTypeBHeaderView
- (void)setSegmentView:(id)v { D2F(@"[HIT] TypeBHeader.setSegmentView class=%@ frame=%@", NSStringFromClass([v class]), NSStringFromCGRect([(UIView *)v frame])); %orig; }
- (void)setSegmentGradientView:(id)v { D2F(@"[HIT] TypeBHeader.setSegmentGradientView class=%@", NSStringFromClass([v class])); %orig; }
- (void)setRightButtonsContainer:(id)v { D2F(@"[HIT] TypeBHeader.setRightButtonsContainer class=%@", NSStringFromClass([v class])); %orig; }
- (void)setLiveView:(id)v { D2F(@"[HIT] TypeBHeader.setLiveView class=%@", NSStringFromClass([v class])); %orig; }
- (void)setMoreView:(id)v { D2F(@"[HIT] TypeBHeader.setMoreView class=%@", NSStringFromClass([v class])); %orig; }
- (void)layoutSegmentContentView { D2F(@"[HIT] TypeBHeader.layoutSegmentContentView"); %orig; }
- (void)layoutSegmentViewAndRightButtons { D2F(@"[HIT] TypeBHeader.layoutSegmentViewAndRightButtons"); %orig; }
- (void)clickLiveBtn { D2F(@"[HIT] TypeBHeader.clickLiveBtn"); %orig; }
%end

%hook TBCChoicenessHeaderView
- (void)setSegmentView:(id)v { D2F(@"[HIT] ChoicenessHeader.setSegmentView class=%@", NSStringFromClass([v class])); %orig; }
%end

%hook TBCSegmentView
- (void)setDataSource:(id)v { D2F(@"[HIT] TBCSegmentView.setDataSource %@", NSStringFromClass([v class])); %orig; }
- (void)setDelegate:(id)v { D2F(@"[HIT] TBCSegmentView.setDelegate %@", NSStringFromClass([v class])); %orig; }
- (void)setItems:(NSArray *)a { D2F(@"[HIT] TBCSegmentView.setItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setItems")); }
- (void)setTabItems:(NSArray *)a { D2F(@"[HIT] TBCSegmentView.setTabItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setTabItems")); }
- (void)setSegmentItems:(NSArray *)a { D2F(@"[HIT] TBCSegmentView.setSegmentItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setSegmentItems")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] TBCSegmentView.setTabs %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"TBCSegmentView.setTabs")); }
- (NSInteger)collectionView:(id)cv numberOfItemsInSection:(NSInteger)s { NSInteger n = %orig; D2F(@"[HIT] TBCSegmentView.numberOfItems=%ld", (long)n); return n; }
%end

%hook TBCScrollSegmentView
- (void)setDataSource:(id)v { D2F(@"[HIT] ScrollSegment.setDataSource %@", NSStringFromClass([v class])); %orig; }
- (void)setDelegate:(id)v { D2F(@"[HIT] ScrollSegment.setDelegate %@", NSStringFromClass([v class])); %orig; }
- (void)setItems:(NSArray *)a { D2F(@"[HIT] ScrollSegment.setItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"ScrollSegment.setItems")); }
- (void)setTabItems:(NSArray *)a { D2F(@"[HIT] ScrollSegment.setTabItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"ScrollSegment.setTabItems")); }
- (void)setSegmentItems:(NSArray *)a { D2F(@"[HIT] ScrollSegment.setSegmentItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"ScrollSegment.setSegmentItems")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] ScrollSegment.setTabs %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"ScrollSegment.setTabs")); }
- (NSInteger)collectionView:(id)cv numberOfItemsInSection:(NSInteger)s { NSInteger n = %orig; D2F(@"[HIT] ScrollSegment.numberOfItems=%ld", (long)n); return n; }
%end

%hook TBCSegmentTabsView
- (id)initWithFrame:(CGRect)f tabs:(NSArray *)tabs { D2F(@"[HIT] TabsView.init tabs=%lu %@", (unsigned long)tabs.count, D2Names(tabs)); return %orig(f, D2Filter(tabs, @"TabsView.init")); }
- (void)setTabs:(NSArray *)t { D2F(@"[HIT] TabsView.setTabs %lu %@", (unsigned long)t.count, D2Names(t)); %orig(D2Filter(t, @"TabsView.setTabs")); }
- (NSArray *)tabs { return D2Filter(%orig, @"TabsView.tabs"); }
- (NSInteger)collectionView:(id)cv numberOfItemsInSection:(NSInteger)s { NSInteger n = %orig; D2F(@"[HIT] TabsView.numberOfItems=%ld", (long)n); return n; }
%end

%hook TBCSecondBarSegmentView
- (id)initWithFrame:(CGRect)f andItems:(NSArray *)items { D2F(@"[HIT] SecondBar.init items=%lu %@", (unsigned long)items.count, D2Names(items)); return %orig(f, D2Filter(items, @"SecondBar.init")); }
- (void)setSegmentItems:(NSArray *)a { D2F(@"[HIT] SecondBar.setSegmentItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"SecondBar.setSegmentItems")); }
- (NSArray *)segmentItems { return D2Filter(%orig, @"SecondBar.segmentItems"); }
%end

%hook TBCSegmentedControl
- (void)setItems:(NSArray *)a { D2F(@"[HIT] SegmentedControl.setItems %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"SegmentedControl.setItems")); }
- (void)setTabs:(NSArray *)a { D2F(@"[HIT] SegmentedControl.setTabs %lu %@", (unsigned long)a.count, D2Names(a)); %orig(D2Filter(a, @"SegmentedControl.setTabs")); }
- (void)setTitles:(NSArray *)a { D2F(@"[HIT] SegmentedControl.setTitles %lu %@", (unsigned long)a.count, [a componentsJoinedByString:@" | "]); %orig; }
%end

%hook TBCSegmentedLabelConfig
- (void)setText:(NSString *)t { D2F(@"[HIT] LabelConfig.setText %@", t); %orig; }
%end

%hook TBCSegmentedLabel
- (void)bindData:(id)d { D2F(@"[HIT] SegmentedLabel.bindData %@ text=%@", NSStringFromClass([d class]), D2Text(d)); %orig; }
%end

%hook TBCSegmentTabsItem
- (void)setName:(NSString *)n { D2F(@"[HIT] TabsItem.setName %@", n); %orig; }
%end

%hook TBCSegmentTabsCell
- (void)bindItem:(id)it { D2F(@"[HIT] TabsCell.bindItem %@ name=%@", NSStringFromClass([it class]), D2ItemName(it)); %orig; }
- (void)layoutSubviews { %orig; NSString *t = D2Text([self valueForKey:@"titleLabel"]); if (t.length) D2F(@"[HIT] TabsCell.layout text=%@ frame=%@", t, NSStringFromCGRect([(UIView *)self frame])); }
%end

%hook TBCHomeChangeHeaderManager
- (void)setAdvancedTabName:(id)n { D2F(@"[HIT] HomeChangeMgr.setAdvancedTabName %@", n); %orig; }
- (id)advancedTabName { id r = %orig; D2F(@"[HIT] HomeChangeMgr.advancedTabName %@", r); return r; }
%end

%hook UILabel
- (void)setText:(NSString *)t {
 %orig;
 if (D2IsRemoved(t) && D2AncestorLooksLikeTabBar(self)) {
 D2F(@"[KILL-LABEL] %@ frame=%@ chain=%@", t, NSStringFromCGRect(self.frame), D2Chain(self));
 self.hidden = YES;
 self.alpha =0.0;
 }
}
%end

%ctor {
 @autoreleasepool {
 D2Init();
 D2F(@"######## diag2 v0.4.0 pid=%d path=%@########", getpid(), gPath);
 NSArray *t = @[ @1.5, @4.0, @9.0, @16.0, @26.0 ];
 for (NSNumber *n in t) {
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([n doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
 D2DumpAll([NSString stringWithFormat:@"t%.1f", [n doubleValue]]);
 D2FocusAll([NSString stringWithFormat:@"t%.1f", [n doubleValue]]);
 D2KillAll([NSString stringWithFormat:@"t%.1f", [n doubleValue]]);
 });
 }
 NSArray *k = @[ @2.0, @6.0, @11.0, @20.0, @31.0 ];
 for (NSNumber *n in k) {
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([n doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
 D2KillAll([NSString stringWithFormat:@"scan%.1f", [n doubleValue]]);
 });
 }
 }
}
