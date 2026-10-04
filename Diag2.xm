// TiebaClean fix v0.8.1 - my-page: text sweep(免费送240天SVIP) + header cut(消空位) + ban Namoaixud + launch ad + tab/ad removal
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
 if(top.hidden!=YES){top.hidden=YES;}
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
 a=@[@"免费送",@"240天",@"SVIP",@"sVIP",@"度小满",@"立即获得",@"立即开通",@"新客专享",@"低息借款",@"现金红包",@"大额",@"成为贴吧会员",@"开通会员",@"会员卡",@"游戏专区"];
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
 v.hidden=YES;
 D2F(@"[MY1] sweep hide cls=%@ y=%.0f h=%.0f txt=%@",NSStringFromClass([v class]),r.origin.y,r.size.height,t);
 }
 }
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
 d2myOnce([NSString stringWithFormat:@"SW#%@",NSStringFromClass([sv class])],
 [NSString stringWithFormat:@"cell文本命中 cls=%@ n=%d y=%.0f (已隐藏,待按item归零)",NSStringFromClass([sv class]),(int)n,sv.frame.origin.y]);
 sv.hidden=YES;
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
 CGFloat full=self.bounds.size.height;
 if(full<60){return;}
 CGFloat cut=full;
 if(vb&&vb.superview){
 CGRect r=[self convertRect:vb.bounds fromView:vb];
 if(r.size.height>=8&&r.origin.y>full*0.35&&r.origin.y<full-4){if(r.origin.y<cut){cut=r.origin.y;}}
 }
 if(my<1e8&&my>full*0.35&&my<full-4){if(my<cut){cut=my;}}
 if(cut<full-4){gHdrCutY=cut;}
 CGFloat want=(gHdrCutY>59)?gHdrCutY:full;
 if(want<60){want=60;}
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
