// TiebaClean fix v0.8.8 - my-page: text sweep(免费送240天SVIP) + header cut(消空位) + ban Namoaixud + launch ad + tab/ad removal
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

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
 D2F(@"######## TiebaClean fix v0.8.8 pid=%d path=%@########", getpid(), gPath);
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

// ===== v0.7.0我的页(个人中心)清理:会员 /度小满 /240天SVIP /游戏专区 =====
//静态索引命中: DXMSDKHomePageLendSmallCardView(度小满借钱小卡), TBCSvipPrivilegeView, TBCVipBannerInfo, TBCMemberGuideItem/TBCOpenMemberView
//我的页分层静态查不到(Person/Profile/Card/Game均无页面骨架类) ->用关键字扫描器抓类名+文本+父链+dataSource类,类名带 DXMSDK的直接藏
static NSArray *gKw=nil;
static NSMutableSet *gSeen=nil;
static BOOL gScanStarted=NO;

static BOOL d2kw(NSString *s){
 if(!s){return(NO);}
 if(s.length<1){return(NO);}
 if(!gKw){gKw=@[@"度小满",@"小满",@"SVIP",@"会员",@"游戏专区",@"游戏大厅",@"钱包"];}
 NSUInteger i=0;
 for(i=0;i<gKw.count;i++){
 NSString *k=[gKw objectAtIndex:i];
 if([s rangeOfString:k].location!=NSNotFound){return(YES);}
 }
 return(NO);
}

static NSString *d2txt(UIView *v){
 NSMutableString *m=[NSMutableString string];
 if([v isKindOfClass:[UILabel class]]){NSString *t=((UILabel *)v).text;if(t.length){[m appendString:t];}}
 if([v isKindOfClass:[UITextView class]]){NSString *t=((UITextView *)v).text;if(t.length){[m appendString:t];}}
 if([v isKindOfClass:[UIButton class]]){NSString *t=[((UIButton *)v)titleForState:0];if(t.length){[m appendString:t];}}
 return(m);
}

static NSString *d2pth(UIView *v){
 NSMutableString *m=[NSMutableString string];
 UIView *p=v;
 int d=0;
 while(p&&d<12){
 NSString *one=[NSString stringWithFormat:@"%@<",NSStringFromClass([p class])];
 [m insertString:one atIndex:0];
 p=p.superview;
 d++;
 }
 return(m);
}

static void d2rpt(NSString *key,NSString *msg){
 if(!gSeen){gSeen=[NSMutableSet set];}
 if([gSeen containsObject:key]){return;}
 [gSeen addObject:key];
 D2F(@"[MY] %@",msg);
}

static void d2scan(UIView *v,int dep){
 if(!v){return;}
 if(dep>16){return;}
 NSString *cn=NSStringFromClass([v class]);
 NSString *tx=d2txt(v);
 if(d2kw(cn)||d2kw(tx)){
 d2rpt([NSString stringWithFormat:@"H#%@#%@",cn,tx],
 [NSString stringWithFormat:@"hit cls=%@ txt=%@ frame=%@ h=%d path=%@",cn,tx,NSStringFromCGRect(v.frame),(int)v.hidden,d2pth(v)]);
 if([cn hasPrefix:@"DXMSDK"]){
 if(v.hidden!=YES){
 v.hidden=YES;
 D2F(@"[MYHIDE] %@ frame=%@",cn,NSStringFromCGRect(v.frame));
 }
 }
 }
 if([v isKindOfClass:[UITableView class]]){
 NSString *ds=NSStringFromClass([((UITableView *)v).dataSource class]);
 d2rpt([NSString stringWithFormat:@"T#%@#%@",cn,ds],
 [NSString stringWithFormat:@"tv=%@ ds=%@ frame=%@",cn,ds,NSStringFromCGRect(v.frame)]);
 }
 if([v isKindOfClass:[UICollectionView class]]){
 NSString *ds=NSStringFromClass([((UICollectionView *)v).dataSource class]);
 d2rpt([NSString stringWithFormat:@"C#%@#%@",cn,ds],
 [NSString stringWithFormat:@"cv=%@ ds=%@ frame=%@",cn,ds,NSStringFromCGRect(v.frame)]);
 }
 NSUInteger i=0;
 for(i=0;i<v.subviews.count;i++){
 d2scan([v.subviews objectAtIndex:i],dep+1);
 }
}

static void d2myStart(void){
 __block int n=0;
 NSTimer *t=[NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *tm){
 n++;
 NSArray *ws=[[UIApplication sharedApplication] windows];
 NSUInteger i=0;
 for(i=0;i<ws.count;i++){
 d2scan([ws objectAtIndex:i],0);
 }
 D2F(@"[MYSCAN] pass=%d windows=%d seen=%d",n,(int)ws.count,(int)gSeen.count);
 if(n>=30){[tm invalidate];}
 }];
 (void)t;
}

%hook UIWindow
- (void)makeKeyAndVisible{
 %orig;
 if(!gScanStarted){
 gScanStarted=YES;
 D2F(@"[MYSCAN] start(makeKeyAndVisible)");
 d2myStart();
 }
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated{
 %orig;
 if(!gScanStarted){
 gScanStarted=YES;
 D2F(@"[MYSCAN] start(viewDidAppear)");
 d2myStart();
 }
}
%end

// ===== v0.8.0我的页精确移除:度小满卡(含240天SVIP) /游戏专区卡 /会员banner =====
//取证来源=v0.7.0扫描器真机日志:
//会员banner: UILabel"成为贴吧会员" -> TBCMyTabVipBannerView < TBCImgView < TBCMyTabHeaderView(表头)
//度小满卡 : UILabel"度小满钱包" -> ... < TBCMyTabCommerceCell (DXMSDK只是它里面的子视图,所以0.7.0按DXMSDK藏失败)
//游戏专区 : UILabel"游戏专区" -> TBCMyTabAmusementView < TBCMyTabAmusementCell
//静态索引(TBClient_tieba_v1):
// TBCMyTabCellFactory +cellHeightForCellItem:tableView: +fetchMyTabCellClass:
// TBCMyTabCommerceCell/+TBCMyTabAmusementCell +tableView:rowHeightForObject:
// TBCMyTabHeaderView -vipBannerView/-setVipBannerView: ; TBCMyTabVipBannerView -bindData:/-setupUI
//回退方案:不碰 TBCMyTabParsedDataManager(返回nil可能被addObject:炸掉),只压高度+隐藏

@interface TBCMyTabHeaderView : UIView
- (UIView *)vipBannerView;
@end

@interface TBCMyTabListViewComponent : UIView
- (UITableView *)tableView;
- (UIView *)headerView;
@end

//必须给出父类,否则Logos只生成@class前置声明,self.hidden/self转UIView都会编译失败
@interface TBCMyTabCommerceCell : UITableViewCell
- (void)setupUI;
@end

@interface TBCMyTabAmusementCell : UITableViewCell
- (void)setupUI;
@end

@interface TBCMyTabVipBannerView : UIView
- (void)bindData:(id)d;
- (void)setupUI;
@end

@interface TBCMyTabCellFactory : NSObject
+ (Class)fetchMyTabCellClass:(id)item;
+ (double)cellHeightForCellItem:(id)item tableView:(id)tv;
@end

static BOOL gMyReloaded=NO;

static BOOL d2myBanName(NSString *cn){
 if(!cn){return(NO);}
 //v0.8.1扩容: Namoaixud=度小满反写(34个方法的整卡item) / Banner / Vip / Svip / Member
 NSString *lc=[cn lowercaseString];
 NSArray *w=@[@"commerce",@"amusement",@"namoaixud",@"banner",@"svip",@"member",@"vip"];
 NSUInteger i=0;
 for(i=0;i<w.count;i++){
 if([lc rangeOfString:[w objectAtIndex:i]].location!=NSNotFound){return(YES);}
 }
 return(NO);
}

static void d2myOnce(NSString *k,NSString *msg){
 if(!gSeen){gSeen=[NSMutableSet set];}
 if([gSeen containsObject:k]){return;}
 [gSeen addObject:k];
 D2F(@"[MY0] %@",msg);
}

//把"只装着这个子视图"的空壳一路藏掉(最多4层),遇cell/table/表头就停
static NSString *d2tx2(UIView *v);
static NSMutableSet *gHid=nil;
static void d2restorePage(UITableView *tv);

static NSMutableSet *gDbg4=nil;

static BOOL d2myWl(UIView *v);

static BOOL d2clsHas(UIView *v,NSString *tok){
 if(!v||!tok||tok.length<=0){return(NO);}
 NSString *cn=[[NSStringFromClass([v class]) lowercaseString] copy];
 if([cn rangeOfString:tok].location!=NSNotFound){return(YES);}
 return(NO);
}

static NSString *d2tx3(UIView *v){
 if(!v){return(@"");}
 NSMutableString *o=[NSMutableString string];
 if([v isKindOfClass:[UILabel class]]){
 UILabel *l=(UILabel *)v;
 if(l.text.length>0){[o appendString:l.text];}
 if(l.attributedText.string.length>0){[o appendString:l.attributedText.string];}
 }
 if([v isKindOfClass:[UIButton class]]){
 UIButton *b=(UIButton *)v;
 if(b.titleLabel.text.length>0){[o appendString:b.titleLabel.text];}
 if(b.titleLabel.attributedText.string.length>0){[o appendString:b.titleLabel.attributedText.string];}
 if(b.accessibilityLabel.length>0){[o appendString:b.accessibilityLabel];}
 }
 if([v isKindOfClass:[UITextView class]]){
 UITextView *tv=(UITextView *)v;
 if(tv.text.length>0){[o appendString:tv.text];}
 if(tv.attributedText.string.length>0){[o appendString:tv.attributedText.string];}
 }
 if(o.length<=0&&v.accessibilityLabel.length>0){[o appendString:v.accessibilityLabel];}
 if(o.length<=0&&v.accessibilityValue.length>0){[o appendString:v.accessibilityValue];}
 if(o.length<=0&&[v isKindOfClass:[UIImageView class]]){
 UIImage *im=((UIImageView *)v).image;
 if(im){[o appendFormat:@"img:%@",[im description]];}
 }
 return(o);
}

static BOOL d2prot(UIView *v){
 if(!v){return(NO);}
 UIView *p=v;
 NSInteger i=0;
 while(p&&i<8){
 NSString *cn=[[NSStringFromClass([p class]) lowercaseString] copy];
 if([cn rangeOfString:@"commonfunction"].location!=NSNotFound){return(YES);}
 if([cn rangeOfString:@"commonfounction"].location!=NSNotFound){return(YES);}
 if([cn rangeOfString:@"assistfunction"].location!=NSNotFound){return(YES);}
 if([cn rangeOfString:@"toolsoptions"].location!=NSNotFound){return(YES);}
 if([cn rangeOfString:@"iconlabel"].location!=NSNotFound){return(YES);}
 if([cn rangeOfString:@"communityassets"].location!=NSNotFound){return(YES);}
 p=p.superview;
 i++;
 }
 return(NO);
}

static BOOL d2myWlCls(UIView *v){
 if(!v){return(NO);}
 static NSArray *cw=nil;
 if(!cw){cw=[[NSArray alloc] initWithObjects:@"tools",@"options",@"common",@"assist",@"function",@"favorite",@"collect",@"history",@"dress",nil];}
 UIView *x=v;
 NSInteger g=0;
 while(x&&g<7){
 NSString *cn=[[NSStringFromClass([x class]) lowercaseString] copy];
 NSUInteger i=0;
 for(i=0;i<cw.count;i++){
 if([cn rangeOfString:[cw objectAtIndex:i]].location!=NSNotFound){return(YES);}
 }
 x=[x superview];
 g++;
 }
 return(NO);
}

static void d2dbg4(UIView *v,NSString *tag){
 if(!v||!tag){return;}
 if(!gDbg4){gDbg4=[NSMutableSet set];}
 if(gDbg4.count>=28){return;}
 NSString *k=[NSString stringWithFormat:@"%@|%@|%.0f|%.0f",tag,NSStringFromClass([v class]),v.frame.origin.y,v.frame.size.height];
 if([gDbg4 containsObject:k]){return;}
 [gDbg4 addObject:k];
 UIView *s1=[v superview];
 NSString *n1=s1?NSStringFromClass([s1 class]):@"-";
 NSString *n2=(s1&&[s1 superview])?NSStringFromClass([[s1 superview] class]):@"-";
 NSString *n3=(s1&&[s1 superview]&&[[s1 superview] superview])?NSStringFromClass([[[s1 superview] superview] class]):@"-";
 D2F(@"[MY4] %@ cls=%@ y=%.0f h=%.0f hd=%d sup=%@ sup2=%@ sup3=%@ wl=%d clswl=%d",tag,NSStringFromClass([v class]),v.frame.origin.y,v.frame.size.height,(int)v.hidden,n1,n2,n3,(int)d2myWl(v),(int)d2myWlCls(v));
}

static BOOL d2myWlTx(NSString *t){
 if(!t||t.length<=0){return(NO);}
 static NSArray *w=nil;
 if(!w){w=[[NSArray alloc] initWithObjects:@"常用功能",@"辅助功能",@"我的收藏",@"我的点赞",@"浏览历史",@"历史记录",@"装扮中心",@"龙虾",@"我的等级",@"兑换商城",@"成长任务",@"印记中心",@"我的发贴",@"我的回贴",@"关注的吧",@"我的智能体",@"设置形象",@"贴贝",nil];}
 NSUInteger i=0;
 for(i=0;i<w.count;i++){
 if([t rangeOfString:[w objectAtIndex:i]].location!=NSNotFound){return(YES);}
 }
 return(NO);
}

static BOOL d2myWl(UIView *v){
 if(!v){return(NO);}
 if(d2prot(v)){return(YES);}
 if(d2myWlTx(d2tx3(v))){return(YES);}
 if(d2myWlCls(v)){return(YES);}
 NSMutableArray *st=[NSMutableArray arrayWithObject:v];
 NSInteger g=0;
 while(st.count>0&&g<400){
 g++;
 UIView *x=[st objectAtIndex:0];
 [st removeObjectAtIndex:0];
 NSUInteger i=0;
 for(i=0;i<x.subviews.count;i++){
 UIView *c=[x.subviews objectAtIndex:i];
 if(d2myWlTx(d2tx3(c))){return(YES);}
 if(d2myWlCls(c)){return(YES);}
 [st addObject:c];
 }
 }
 return(NO);
}

static void d2myCollapse(UIView *v){
 if(!v){return;}
 UIView *top=v;
 UIView *p=v.superview;
 int d=0;
 while(p&&d<4){
 if([p isKindOfClass:[UITableViewCell class]]){break;}
 NSString *pn=NSStringFromClass([p class]);
 if([pn hasPrefix:@"UITableView"]||[pn isEqualToString:@"TBCMyTabHeaderView"]){break;}
 BOOL other=NO;
 NSUInteger i=0;
 for(i=0;i<p.subviews.count;i++){
 UIView *sv=[p.subviews objectAtIndex:i];
 if(sv==top){continue;}
 if(sv.hidden){continue;}
 if(sv.frame.size.height>1){other=YES;break;}
 }
 if(other){break;}
 top=p;
 p=p.superview;
 d++;
 }
 if(top.hidden!=YES){
 if(d2myWl(top)||d2prot(top)){D2F(@"[MY3] collapse skip-wl cls=%@ h=%.0f",NSStringFromClass([top class]),top.frame.size.height);}
 else{
 if(!gHid){gHid=[NSMutableSet set];}
 [gHid addObject:[NSString stringWithFormat:@"%p",top]];
 top.hidden=YES;
 }
 }
 CGRect f=top.frame;
 if(f.size.height>0.5){f.size.height=0;top.frame=f;}
 d2myOnce([NSString stringWithFormat:@"CL#%@",NSStringFromClass([top class])],
 [NSString stringWithFormat:@"collapse %@ h=%.0f ->0 (leaf=%@)",NSStringFromClass([top class]),f.size.height,NSStringFromClass([v class])]);
}

static int d2myCount(UIView *v,int dep){
 if(!v){return(0);}
 if(dep>16){return(0);}
 int c=0;
 NSString *cn=NSStringFromClass([v class]);
 NSString *tx=d2txt(v);
 if((d2kw(cn)||d2kw(tx))&&v.hidden!=YES){c++;}
 NSUInteger i=0;
 for(i=0;i<v.subviews.count;i++){c+=d2myCount([v.subviews objectAtIndex:i],dep+1);}
 return(c);
}

static void d2mySweepCells(UITableView *tv);
static void d2myInv(UIView *hdr);
static void d2myPagePass(UIView *tvc){
 if(!tvc){return;}
 UITableView *tv=nil;
 @try{if([tvc isKindOfClass:[UITableView class]]){tv=(UITableView *)tvc;}}@catch(NSException *e){}
 if(!tv){return;}
 NSMutableArray *hit=[NSMutableArray array];
 NSUInteger i=0;
 for(i=0;i<tv.subviews.count;i++){
 UIView *sv=[tv.subviews objectAtIndex:i];
 if(d2myBanName(NSStringFromClass([sv class]))){[hit addObject:sv];}
 }
 for(i=0;i<hit.count;i++){d2myCollapse([hit objectAtIndex:i]);}
 UIView *hdr=tv.tableHeaderView;
 d2mySweepCells(tv);
 d2myInv(hdr);
 D2F(@"[MY1] pass cells=%d banned=%d tvH=%.0f hdr=%@ hdrH=%.0f",
 (int)tv.subviews.count,(int)hit.count,tv.frame.size.height,NSStringFromClass([hdr class]),hdr?hdr.frame.size.height:0.0);
 if(hit.count>0&&!gMyReloaded){
 gMyReloaded=YES;
 d2myOnce(@"RELOAD1",@"banned cell seen -> reloadData once (重算行高)");
 dispatch_async(dispatch_get_main_queue(),^{ [tv reloadData]; });
 }
}

%hook TBCMyTabCellFactory
+ (double)cellHeightForCellItem:(id)item tableView:(id)tv {
 NSString *ic=item?NSStringFromClass([item class]):@"nil";
 NSString *ccn=@"?";
 @try{
 Class cc=(Class)[self fetchMyTabCellClass:item];
 if(cc){ccn=NSStringFromClass(cc);}
 }@catch(NSException *e){}
 BOOL ban=d2myBanName(ic);
 if(!ban&&![ccn isEqualToString:@"?"]){ban=d2myBanName(ccn);}
 if(ban){
 d2myOnce([NSString stringWithFormat:@"FH1#%@#%@",ic,ccn],
 [NSString stringWithFormat:@"factory BAN item=%@ cell=%@ ->0",ic,ccn]);
 return(0.0);
 }
 d2myOnce([NSString stringWithFormat:@"FI1#%@#%@",ic,ccn],
 [NSString stringWithFormat:@"factory item=%@ cell=%@",ic,ccn]);
 return %orig;
}
%end

%hook TBCMyTabCommerceCell
+ (double)tableView:(id)tv rowHeightForObject:(id)o {
 d2myOnce(@"RH#commerce",@"commerce +tableView:rowHeightForObject: ->0");
 return(0.0);
}
- (void)setupUI {
 %orig;
 d2myOnce(@"UI#commerce",@"commerce cell hidden");
 self.hidden=YES;
 d2myCollapse(self);
}
%end

%hook TBCMyTabAmusementCell
+ (double)tableView:(id)tv rowHeightForObject:(id)o {
 d2myOnce(@"RH#amuse",@"amusement +tableView:rowHeightForObject: ->0");
 return(0.0);
}
- (void)setupUI {
 %orig;
 d2myOnce(@"UI#amuse",@"amusement cell hidden");
 self.hidden=YES;
 d2myCollapse(self);
}
%end

%hook TBCMyTabVipBannerView
- (void)bindData:(id)d {
 d2myOnce(@"BD#vipbanner",@"vipBanner bindData skipped(不绑会员卡数据)");
}
- (void)setupUI {
 %orig;
 d2myOnce(@"UI#vipbanner",@"vipBanner setupUI -> hide only(保留占位,表头按实测y剪高)");
 self.hidden=YES;
}
%end

%hook TBCMyTabHeaderView
- (void)setVipBannerView:(id)v {
 %orig(v);
 if(v&&[v isKindOfClass:[UIView class]]){((UIView *)v).hidden=YES;}
}
%end

%hook TBCMyTabListViewComponent
- (void)prepareForDisplay {
 %orig;
 d2myPagePass([self tableView]);
}
- (void)tableViewReloadData:(id)a {
 %orig;
 d2myPagePass([self tableView]);
}
%end


// ===== v0.8.1文本兜底清扫 +表头剪高 =====
//证据:0.8.0日志 hdrH=318恒定(只藏banner不缩表头 => "开通会员"留空位)
//日志里 SVIP计数=0 => "免费送240天贴吧SVIP"不是UILabel(自绘/富文本),扫描器抓不到
//手段:关键词清扫隐藏命中视图 +用vipBannerView实测y把表头高度剪到它上面
static NSArray *d2badWords(void){
 static NSArray *a=nil;
 if(!a){
 a=@[@"免费送",@"240天",@"SVIP",@"svip",@"sVIP",@"度小满",@"立即获得",@"立即开通",@"新客专享",@"低息借款",@"现金红包",@"大额",@"成为贴吧会员",@"开通会员",@"会员卡",@"游戏专区"];
 }
 return(a);
}

static NSString *d2tx2(UIView *v){
 if(!v){return(@"");}
 @try{
 if([v isKindOfClass:[UILabel class]]){return(((UILabel *)v).text?((UILabel *)v).text:@"");}
 if([v isKindOfClass:[UIButton class]]){
 NSString *t=[(UIButton *)v titleForState:UIControlStateNormal];
 if(t.length>0){return(t);}
 }
 if([v isKindOfClass:[UIImageView class]]){
 UIImage *im=((UIImageView *)v).image;
 if(im){return([NSString stringWithFormat:@"<img %@>",im]);}
 }
 NSString *al=v.accessibilityLabel;
 if(al&&al.length>0){return(al);}
 NSString *avl=v.accessibilityValue;
 if(avl&&avl.length>0){return(avl);}
 SEL s1=NSSelectorFromString(@"text");
 if([v respondsToSelector:s1]){
 id t=[v performSelector:s1];
 if([t isKindOfClass:[NSString class]]&&[(NSString *)t length]>0){return((NSString *)t);}
 }
 SEL s2=NSSelectorFromString(@"attributedText");
 if([v respondsToSelector:s2]){
 id t=[v performSelector:s2];
 if([t isKindOfClass:[NSAttributedString class]]&&[((NSAttributedString *)t) string].length>0){return([((NSAttributedString *)t) string]);}
 }
 }@catch(NSException *e){}
 return(@"");
}

static BOOL d2badTx(NSString *t){
 if(!t||t.length<1){return(NO);}
 NSArray *w=d2badWords();
 NSUInteger i=0;
 for(i=0;i<w.count;i++){
 if([t rangeOfString:[w objectAtIndex:i]].location!=NSNotFound){return(YES);}
 }
 return(NO);
}

//清扫子树文本:命中即隐藏;用coord换算记录命中的最小y(表头剪高用)
static NSInteger d2sweepEx(UIView *root,UIView *coord,BOOL doHide,CGFloat *outMinY){
 NSInteger n=0;
 CGFloat my=1e9;
 if(!root||!coord){return(0);}
 NSMutableArray *st=[NSMutableArray arrayWithObject:root];
 NSInteger g=0;
 while(st.count>0&&g<3000){
 g++;
 UIView *v=[st lastObject];
 [st removeLastObject];
 NSString *t=d2tx2(v);
 if(t.length>0&&d2badTx(t)){
 n++;
 CGRect r=[coord convertRect:v.bounds fromView:v];
 if(r.origin.y<my){my=r.origin.y;}
 if(doHide&&v.hidden!=YES){
 if(d2myWl(v)){D2F(@"[MY3] sweep skip-wl cls=%@ txt=%@",NSStringFromClass([v class]),t);}
 else{
 v.hidden=YES;
 if(!gHid){gHid=[NSMutableSet set];}
 [gHid addObject:[NSString stringWithFormat:@"%p",v]];
 D2F(@"[MY1] sweep hide cls=%@ y=%.0f h=%.0f txt=%@",NSStringFromClass([v class]),r.origin.y,r.size.height,t);
 }
 }
 }
 if(d2clsHas(v,@"tools")||d2clsHas(v,@"options")){d2dbg4(v,@"tile");}
 NSUInteger i=0;
 for(i=0;i<v.subviews.count;i++){[st addObject:[v.subviews objectAtIndex:i]];}
 }
 if(outMinY){*outMinY=my;}
 return(n);
}

static UITableView *d2findTV(UIView *v){
 UIView *c=v;
 NSInteger g=0;
 while(c&&g<20){
 if([c isKindOfClass:[UITableView class]]){return((UITableView *)c);}
 c=[c superview];
 g++;
 }
 return(nil);
}

static void d2myInv(UIView *hdr){
 if(!hdr){return;}
 if(!gSeen){gSeen=[NSMutableSet set];}
 if([gSeen containsObject:@"HDRINV1"]){return;}
 [gSeen addObject:@"HDRINV1"];
 NSUInteger i=0;
 D2F(@"[MY1] hdr cls=%@ h=%.0f sub=%d",NSStringFromClass([hdr class]),hdr.frame.size.height,(int)hdr.subviews.count);
 for(i=0;i<hdr.subviews.count;i++){
 UIView *sv=[hdr.subviews objectAtIndex:i];
 D2F(@"[MY1] hdr sub cls=%@ y=%.0f h=%.0f hd=%d txt=%@",NSStringFromClass([sv class]),sv.frame.origin.y,sv.frame.size.height,(int)sv.hidden,d2tx2(sv));
 }
}

static void d2mySweepCells(UITableView *tv){
 if(!tv){return;}
 NSUInteger i=0;
 for(i=0;i<tv.subviews.count;i++){
 UIView *sv=[tv.subviews objectAtIndex:i];
 if(![sv isKindOfClass:[UITableViewCell class]]){continue;}
 CGFloat my=0;
 NSInteger n=d2sweepEx(sv,tv,YES,&my);
 if(n>0){
 d2myOnce([NSString stringWithFormat:@"SW#%@#%d",NSStringFromClass([sv class]),(int)n],
 [NSString stringWithFormat:@"cell内命中 cls=%@ n=%d y=%.0f (只藏命中子视图,不整格隐藏)",NSStringFromClass([sv class]),(int)n,sv.frame.origin.y]);
 }
 }
}

// ===== v0.8.2:探针扩展(图片名/accessibilityLabel) +定时复扫 +整页结构dump =====
//证据:0.8.1日志里 SVIP一次未命中,只有"游戏专区/度小满钱包"两个UILabel命中
//=>免费送240天SVIP不是UILabel(自绘/H5/图片) =>加图片名与accessibility通道 +把整页结构打出来
static NSInteger gBudget=0;

static void d2dumpTree(UIView *root,UIView *coord,NSString *tag,NSInteger maxDepth){
 if(!root||!coord){return;}
 NSMutableArray *st=[NSMutableArray arrayWithObject:root];
 NSMutableArray *dp=[NSMutableArray arrayWithObject:[NSNumber numberWithInt:0]];
 NSInteger g=0;
 while(st.count>0&&g<400){
 g++;
 if(gBudget<=0){return;}
 UIView *v=[st objectAtIndex:0];
 NSInteger d=[[dp objectAtIndex:0] intValue];
 [st removeObjectAtIndex:0];
 [dp removeObjectAtIndex:0];
 if(d>maxDepth){continue;}
 gBudget--;
 CGRect r=[coord convertRect:v.bounds fromView:v];
 D2F(@"[MY2] %@ d=%d %@ y=%.0f h=%.0f w=%.0f hd=%d txt=%@",tag,(int)d,NSStringFromClass([v class]),r.origin.y,r.size.height,r.size.width,(int)v.hidden,d2tx2(v));
 NSUInteger i=0;
 for(i=0;i<v.subviews.count;i++){
 [st addObject:[v.subviews objectAtIndex:i]];
 [dp addObject:[NSNumber numberWithInt:(int)(d+1)]];
 }
 }
}

static void d2dumpPage(UITableView *tv,NSString *tag){
 if(!tv||!tag){return;}
 NSString *key=[NSString stringWithFormat:@"DUMP#%@",tag];
 if(!gSeen){gSeen=[NSMutableSet set];}
 if([gSeen containsObject:key]){return;}
 [gSeen addObject:key];
 gBudget=170;
 D2F(@"[MY2] ==DUMP %@ tvH=%.0f sub=%d vis=%d",tag,tv.contentSize.height,(int)tv.subviews.count,(int)tv.visibleCells.count);
 UIView *hdr=tv.tableHeaderView;
 if(hdr){
 D2F(@"[MY2] ==DUMP %@ header %@ h=%.0f",tag,NSStringFromClass([hdr class]),hdr.frame.size.height);
 d2dumpTree(hdr,hdr,@"h",4);
 }
 NSArray *cs=tv.visibleCells;
 NSUInteger j=0;
 for(j=0;j<cs.count;j++){
 UIView *c=[cs objectAtIndex:j];
 CGRect r=[tv convertRect:c.bounds fromView:c];
 D2F(@"[MY2] ==DUMP %@ cell %@ y=%.0f h=%.0f hd=%d",tag,NSStringFromClass([c class]),r.origin.y,r.size.height,(int)c.hidden);
 d2dumpTree(c,tv,@"c",4);
 }
 D2F(@"[MY2] ==DUMP %@ end budget=%d",tag,(int)gBudget);
}

static void d2cardReport(UITableView *tv){
if(!tv){return;}
NSArray *cs=tv.visibleCells;
NSUInteger ci=0;
for(ci=0;ci<cs.count;ci++){
UIView *c=[cs objectAtIndex:ci];
NSString *cn=[[NSStringFromClass([c class]) lowercaseString] copy];
if([cn rangeOfString:@"function"].location==NSNotFound){continue;}
CGRect r=[tv convertRect:c.bounds fromView:c];
NSInteger hid=0;NSInteger res=0;NSInteger a0=0;NSInteger ti=0;
NSMutableArray *st=[NSMutableArray arrayWithObject:c];
NSMutableArray *all=[NSMutableArray array];
NSInteger g=0;
while(st.count>0&&g<600){
g++;
UIView *w=[st objectAtIndex:0];
[st removeObjectAtIndex:0];
[all addObject:w];
if([w isKindOfClass:NSClassFromString(@"TBCMyTabIconLabelView")]){
ti++;
CGRect tr=[tv convertRect:w.bounds fromView:w];
UIView *p1=w.superview;
UIView *p2=p1?p1.superview:nil;
UIView *p3=p2?p2.superview:nil;
D2F(@"[MY6] tile i=%d ax=%.0f ay=%.0f w=%.0f h=%.0f hd=%d al=%.2f | p1=%@ hd=%d al=%.2f p2=%@ hd=%d al=%.2f p3=%@ hd=%d al=%.2f",(int)ti,tr.origin.x,tr.origin.y,tr.size.width,tr.size.height,(int)w.hidden,(double)w.alpha,NSStringFromClass([p1 class]),(int)p1.hidden,(double)p1.alpha,NSStringFromClass([p2 class]),(int)p2.hidden,(double)p2.alpha,NSStringFromClass([p3 class]),(int)p3.hidden,(double)p3.alpha);
}
NSUInteger kk=0;
for(kk=0;kk<w.subviews.count;kk++){[st addObject:[w.subviews objectAtIndex:kk]];}
}
NSInteger q=0;
for(q=0;q<(NSInteger)all.count;q++){
UIView *w=[all objectAtIndex:q];
if(w.hidden){w.hidden=NO;hid++;res++;}
if(w.alpha<0.01){w.alpha=1.0;a0++;res++;}
UIView *p=w.superview;NSInteger u=0;
while(p&&p!=c&&u<10){u++;if(p.hidden){p.hidden=NO;hid++;res++;}if(p.alpha<0.01){p.alpha=1.0;a0++;res++;}p=p.superview;}
}
D2F(@"[MY6] card cls=%@ y=%.0f h=%.0f hd=%d hid=%d alpha0=%d tiles=%d rescued=%d",NSStringFromClass([c class]),r.origin.y,r.size.height,(int)c.hidden,(int)hid,(int)a0,(int)ti,(int)res);
}
}

static void d2scheduleResweeps(UITableView *tv){
 if(!tv){return;}
 __weak UITableView *wt=tv;
 CGFloat ds[4]={0.4,1.0,2.0,3.6};
 NSInteger k=0;
 for(k=0;k<4;k++){
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(ds[k]*(double)NSEC_PER_SEC)),dispatch_get_main_queue(),^{
 UITableView *t=wt;
 if(!t){return;}
 D2F(@"[MY2] resweep k=%d vis=%d",(int)k,(int)t.visibleCells.count);
 d2mySweepCells(t);
 UIView *h=t.tableHeaderView;
 if(h){[h setNeedsLayout];}
 d2restorePage(t);
 d2cardReport(t);
 if(k==1){d2dumpPage(t,@"P1");}
 if(k==3){d2dumpPage(t,@"P3");}
 });
 }
}

static void d2restorePage(UITableView *tv){
 if(!tv){return;}
 if(!gHid){gHid=[NSMutableSet set];}
 NSMutableArray *roots=[NSMutableArray array];
 UIView *h=tv.tableHeaderView;
 if(h){[roots addObject:h];}
 NSArray *cs=tv.visibleCells;
 NSUInteger j=0;
 for(j=0;j<cs.count;j++){[roots addObject:[cs objectAtIndex:j]];}
 for(j=0;j<roots.count;j++){
 UIView *root=[roots objectAtIndex:j];
 d2dbg4(root,@"root");
 NSMutableArray *st=[NSMutableArray arrayWithObject:root];
 NSInteger g=0;
 while(st.count>0&&g<260){
 g++;
 UIView *v=[st objectAtIndex:0];
 [st removeObjectAtIndex:0];
 if(v.hidden==YES){
 d2dbg4(v,@"hid");
 NSString *cn=[NSStringFromClass([v class]) lowercaseString];
 BOOL ban=NO;
 BOOL known=NO;
 BOOL mine=NO;
 if([cn rangeOfString:@"vip"].location!=NSNotFound){ban=YES;}
 if([cn rangeOfString:@"banner"].location!=NSNotFound){ban=YES;}
 if([cn rangeOfString:@"commerce"].location!=NSNotFound){ban=YES;}
 if([cn rangeOfString:@"amusement"].location!=NSNotFound){ban=YES;}
 if([cn rangeOfString:@"namoaixud"].location!=NSNotFound){ban=YES;}
 if([cn rangeOfString:@"member"].location!=NSNotFound){ban=YES;}
 if([cn rangeOfString:@"function"].location!=NSNotFound){known=YES;}
 if([cn rangeOfString:@"tools"].location!=NSNotFound){known=YES;}
 if([cn rangeOfString:@"options"].location!=NSNotFound){known=YES;}
 if([cn rangeOfString:@"assist"].location!=NSNotFound){known=YES;}
 if([gHid containsObject:[NSString stringWithFormat:@"%p",v]]){mine=YES;}
 if(!d2prot(v)&&!ban&&(mine||known||d2myWlCls(v))&&d2myWl(v)){
 v.hidden=NO;
 D2F(@"[MY3] restore cls=%@ y=%.0f h=%.0f txt=%@",NSStringFromClass([v class]),v.frame.origin.y,v.frame.size.height,d2tx2(v));
 }
 }
 if(d2clsHas(v,@"tools")||d2clsHas(v,@"options")){d2dbg4(v,@"tile");}
 NSUInteger i=0;
 for(i=0;i<v.subviews.count;i++){[st addObject:[v.subviews objectAtIndex:i]];}
 }
 }
}

static CGFloat gHdrCutY=0;

%hook TBCMyTabHeaderView
- (void)layoutSubviews {
 %orig;
 @try{
 CGFloat my=0;
 NSInteger n=d2sweepEx(self,self,YES,&my);
 if(n>0){D2F(@"[MY1] hdr text sweep n=%d minY=%.0f",(int)n,my);}
 d2myInv(self);
 UIView *vb=nil;
 SEL svb=NSSelectorFromString(@"vipBannerView");
 if([self respondsToSelector:svb]){vb=(UIView *)[self performSelector:svb];}
 if(vb&&vb.hidden!=YES){vb.hidden=YES;}
 d2restorePage(d2findTV(self));
 UITableView *dpv=d2findTV(self);
 if(![gSeen containsObject:@"SCHED1"]){[gSeen addObject:@"SCHED1"];d2scheduleResweeps(dpv);d2dumpPage(dpv,@"P0");}
 CGFloat full=self.bounds.size.height;
 if(full<60){return;}
 CGFloat cut=full;
 if(vb&&vb.superview){
 CGRect r=[self convertRect:vb.bounds fromView:vb];
 if(r.size.height>=8&&r.origin.y>full*0.35&&r.origin.y<full-4){if(r.origin.y<cut){cut=r.origin.y;}}
 }
 if(my<1e8&&my>full*0.35&&my<full-4){if(my<cut){cut=my;}}
 if(cut<full-4){gHdrCutY=cut;}
 if(gHdrCutY<60){gHdrCutY=full-136;}
 CGFloat want=(gHdrCutY>59)?gHdrCutY:full;
 if(want<140&&full>=150){want=140;}
 if(want>full){want=full;}
 if(fabs(full-want)>1.0){
 CGRect f=self.frame;
 f.size.height=want;
 self.frame=f;
 UITableView *tv=d2findTV(self);
 if(tv&&tv.tableHeaderView==self){[tv setTableHeaderView:self];}
 D2F(@"[MY1] header cut %.0f -> %.0f",full,want);
 }
 }@catch(NSException *e){
 D2F(@"[MY1] hdr ex %@",e.name);
 }
}
%end
