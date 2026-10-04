// TiebaClean fix v0.6.0 - launch ad removal + TBCSegmentView tab removal + ad row collapse
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

static NSString *gPath = nil;
static NSMutableString *gBuf = nil;
static NSLock *gLock = nil;
static int gLines =0;
static const int gMaxLines =4000;
static NSMutableDictionary *gBanIdx = nil;
static BOOL gReloading = NO;

static void D2Init(void) {
 if (gPath) return;
 gLock = [NSLock new];
 gBuf = [NSMutableString new];
 gBanIdx = [NSMutableDictionary new];
 gPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"tieba_fix.log"];
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
 static const char *keys[] = {"name", "title", "tabName", "tabTitle", "identityText", "text", "fetchTabName", "segmentName", "tabText", "key", "identityTitle", NULL};
 int i =0;
 while (keys[i]) {
 NSString *s = D2Str(it, keys[i]);
 if (s.length >0) return s;
 i++;
 }
 return nil;
}

static BOOL D2Banned(NSString *s) {
 if (![s isKindOfClass:[NSString class]]) return NO;
 NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if (t.length ==0) return NO;
 if ([t isEqualToString:@"有料"]) return YES;
 if ([t isEqualToString:@"直播"]) return YES;
 if ([t isEqualToString:@"有料°"]) return YES;
 return NO;
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
 D2F(@"[FILTER %@] no match count=%lu names=%@", tag, (unsigned long)a.count, D2Names(a));
 return a;
}

static BOOL D2IsAdObject(id o) {
 if (!o) return NO;
 NSString *cn = NSStringFromClass([o class]);
 if ([cn rangeOfString:@"CommercialAd"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"AdItem"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"BearAd"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"Promotion"].location != NSNotFound) return YES;
 if ([cn rangeOfString:@"DXM"].location != NSNotFound) return YES;
 return NO;
}

static NSString *D2CellText(id cell) {
 NSString *s = D2Str(cell, "fetchTabName");
 if (s.length >0) return s;
 UILabel *tl = D2Msg(cell, "textLabel");
 s = D2Text(tl);
 if (s.length >0) return s;
 return nil;
}

static UICollectionView *D2FindCollection(UIView *v) {
 UIView *p = v;
 int i =0;
 while (p && i <12) {
 if ([p isKindOfClass:[UICollectionView class]]) return (UICollectionView *)p;
 p = [p superview];
 i++;
 }
 return nil;
}

static void D2Relayout(UIView *v) {
 if (gReloading) return;
 UICollectionView *cv = D2FindCollection(v);
 if (!cv) return;
 gReloading = YES;
 [cv.collectionViewLayout invalidateLayout];
 [cv reloadData];
 gReloading = NO;
 D2F(@"[RELAYOUT] collection=%@", NSStringFromClass([cv class]));
}

static void D2DumpTree(UIView *v, int d, NSMutableString *sb) {
 if (!v || d >8 || sb.length >40000) return;
 NSMutableString *pad = [NSMutableString string];
 for (int i =0; i < d; i++) [pad appendString:@"| "];
 [sb appendFormat:@"%@%@(%.0f,%.0f,%.0f,%.0f)", pad, NSStringFromClass([v class]), v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height];
 NSString *t = D2Text(v);
 if (t.length >0) [sb appendFormat:@" %@", t];
 if (v.hidden) [sb appendString:@" HIDDEN"];
 [sb appendString:@"\n"];
 for (UIView *s in v.subviews) D2DumpTree(s, d +1, sb);
}

static void D2VerifyWalk(UIView *v, int d, NSMutableString *sb, int *ads) {
 if (!v || d >12) return;
 NSString *cn = NSStringFromClass([v class]);
 if ([cn rangeOfString:@"CommercialAd"].location != NSNotFound && !v.hidden && v.frame.size.height >1.0) {
 *ads = *ads +1;
 }
 if ([cn isEqualToString:@"TBCChoicenessTypeBHeaderView"]) {
 [sb appendString:@"--HEADER\n"];
 D2DumpTree(v,0, sb);
 }
 for (UIView *s in v.subviews) D2VerifyWalk(s, d +1, sb, ads);
}

static void D2Verify(NSString *tag) {
 NSArray *ws = [[UIApplication sharedApplication] windows];
 NSMutableString *sb = [NSMutableString string];
 int ads =0;
 for (UIWindow *w in ws) D2VerifyWalk(w,0, sb, &ads);
 D2F(@"===== VERIFY %@ visibleAdCells=%d banIdx=%@ =====", tag, ads, [[gBanIdx allKeys] componentsJoinedByString:@","]);
 if (sb.length >0) D2W(sb);
}

@interface D2Runner2 : NSObject
- (void)v1;
- (void)v2;
@end

@implementation D2Runner2
- (void)v1 { D2Verify(@"t6"); }
- (void)v2 { D2Verify(@"t14"); }
@end

%hook TBCSegmentView
- (void)setDataSource:(NSArray *)a {
 D2F(@"[HIT] TBCSegmentView setDataSource count=%lu %@", (unsigned long)a.count, D2Names(a));
 %orig(D2Filter(a, @"TBCSegmentView.setDataSource"));
}
- (void)setItems:(NSArray *)a {
 D2F(@"[HIT] TBCSegmentView setItems %@", D2Names(a));
 %orig(D2Filter(a, @"TBCSegmentView.setItems"));
}
- (void)setTabs:(NSArray *)a {
 D2F(@"[HIT] TBCSegmentView setTabs %@", D2Names(a));
 %orig(D2Filter(a, @"TBCSegmentView.setTabs"));
}
- (void)setDelegate:(id)o {
 D2F(@"[HIT] TBCSegmentView setDelegate=%@", NSStringFromClass([o class]));
 %orig;
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
 NSInteger n = %orig;
 D2F(@"[HIT] TBCSegmentView numberOfItems=%ld", (long)n);
 return n;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
 if (gBanIdx[@(ip.item)] != nil) {
 D2F(@"[ZERO] sizeForItem idx=%ld", (long)ip.item);
 return CGSizeMake(0.0,0.0);
 }
 return %orig;
}
- (CGFloat)cellWidthForItem:(id)item {
 NSString *n = D2ItemName(item);
 if (D2Banned(n)) {
 D2F(@"[ZERO] cellWidthForItem name=%@", n);
 return(0.0);
 }
 return %orig;
}
%end

@interface TBCSegmentViewCell : UIView
- (void)bindData:(id)d;
- (NSString *)fetchTabName;
- (NSIndexPath *)indexPath;
- (UILabel *)textLabel;
- (void)setTextLabel:(UILabel *)l;
@end

%hook TBCSegmentViewCell
- (void)bindData:(id)d {
 %orig;
 NSString *n = D2CellText(self);
 if (n.length ==0) return;
 if (!D2Banned(n)) return;
 NSIndexPath *ip = D2Msg(self, "indexPath");
 NSNumber *k = ip ? @(ip.item) : nil;
 BOOL isNew = (k != nil && gBanIdx[k] == nil);
 if (k) gBanIdx[k] = @YES;
 UIView *sv = (UIView *)self;
 sv.hidden = YES;
 sv.alpha =0.0;
 UILabel *tl = D2Msg(self, "textLabel");
 if ([tl isKindOfClass:[UILabel class]]) tl.text = @"";
 D2F(@"[BAN] cell=%@ name=%@ idx=%@ isNew=%d", NSStringFromClass([self class]), n, k, (int)isNew);
 if (isNew) D2Relayout(sv);
}
%end

%hook TBCSegmentedControl
- (void)setItems:(NSArray *)a {
 NSMutableArray *keep = [NSMutableArray array];
 NSMutableArray *drop = [NSMutableArray array];
 for (id it in a) {
 NSString *s = [it isKindOfClass:[NSString class]] ? (NSString *)it : D2ItemName(it);
 if (D2Banned(s)) [drop addObject:(s ? s : @"?")];
 else [keep addObject:it];
 }
 D2F(@"[HIT] SegmentedControl setItems count=%lu drop=%@", (unsigned long)a.count, [drop componentsJoinedByString:@"+"]);
 if (drop.count >0) %orig(keep); else %orig;
}
%end

%hook TBCCommercialAdBaseCell
+ (CGFloat)tableView:(id)tv rowHeightForObject:(id)obj {
 CGFloat h = %orig;
 BOOL ad = D2IsAdObject(obj);
 D2F(@"[ADROW] ad=%d h=%.0f obj=%@", (int)ad, h, NSStringFromClass([obj class]));
 if (ad) return(0.0);
 return h;
}
%end

%hook TBCPBFirstFloorBannerComponent
- (BOOL)shouldShowAd { D2F(@"[AD] shouldShowAd -> NO"); return NO; }
- (BOOL)shouldShowGameAdBannerView { D2F(@"[AD] shouldShowGameAdBannerView -> NO"); return NO; }
- (BOOL)shouldShowRecommendAdRecreationView { D2F(@"[AD] shouldShowRecommendAdRecreationView -> NO"); return NO; }
- (BOOL)shouldShowRecommendADXLiveView { D2F(@"[AD] shouldShowRecommendADXLiveView -> NO"); return NO; }
- (BOOL)isHaveBearAd { D2F(@"[AD] isHaveBearAd -> NO"); return NO; }
%end

%ctor {
 @autoreleasepool {
 D2Init();
 D2F(@"######## TiebaClean fix v0.6.0 pid=%d path=%@########", getpid(), gPath);
 D2Runner2 *r = [D2Runner2 new];
 [NSTimer scheduledTimerWithTimeInterval:6.0 target:r selector:@selector(v1) userInfo:nil repeats:NO];
 [NSTimer scheduledTimerWithTimeInterval:14.0 target:r selector:@selector(v2) userInfo:nil repeats:NO];
 }
}

// ===== v0.6.0: launch(splash) ad removal =====
//依据静态索引: TBClientAppDelegate -shouldShowLaunchAd B16@0:8 / launchAdVc @16@0:8
// TBCLaunchADViewController: startShowAdvertisingIfNeed v16@0:8 / startShowADWithAdType: v24@0:8q16
// dismissADWithAnimation: v20@0:8B16

@interface TBCLaunchADViewController : UIViewController
- (void)startShowAdvertisingIfNeed;
- (void)startShowADWithAdType:(long long)t;
- (void)dismissADWithAnimation:(BOOL)a;
- (void)splashWillAppear;
- (void)splashDidAppear;
@end

%hook TBClientAppDelegate
- (BOOL)shouldShowLaunchAd {
 BOOL o = %orig;
 D2F(@"[LGATE] shouldShowLaunchAd orig=%d -> NO", (int)o);
 return NO;
}
%end

%hook TBCLaunchADViewController
- (void)viewDidLoad {
 D2F(@"[LHIT] LaunchADVC viewDidLoad (vc created)");
 %orig;
}
- (void)startShowAdvertisingIfNeed {
 D2F(@"[LHIT] startShowAdvertisingIfNeed");
 %orig;
}
- (void)startShowADWithAdType:(long long)t {
 D2F(@"[LHIT] startShowADWithAdType=%lld", t);
 %orig;
}
- (void)splashWillAppear {
 D2F(@"[LHIT] splashWillAppear");
 %orig;
}
- (void)splashDidAppear {
 D2F(@"[LHIT] splashDidAppear");
 %orig;
}
- (void)viewDidAppear:(BOOL)a {
 %orig;
 BOOL onWin = (self.view.window != nil);
 D2F(@"[LHIT] adVC viewDidAppear window=%d", (int)onWin);
 if (onWin) {
 D2F(@"[LFAST] dismiss launch ad now");
 [self dismissADWithAnimation:NO];
 }
}
%end
