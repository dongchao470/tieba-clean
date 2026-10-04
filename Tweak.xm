//
// TiebaClean ——百度贴吧精简补丁
//
//功能：
//1)去掉首页顶栏的「有料」/「直播」入口
//2)去掉信息流里的商业广告卡（度小满之类）
//3)去掉帖子 /吧内列表里插入的广告（七猫免费小说之类）
//
//目标 App：com.baidu.tieba（主程序 TBClient）
//越狱方案：roothide / arm64e / iOS15+
//
//说明：下面所有类名、selector、typeEncoding均来自 app-method-index对 TBClient主程序的
//静态索引结果，没有编造任何符号。本补丁只压缩 UI展示与广告插入链路，不改动正常内容请求。
//

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define TBClog(fmt, ...) NSLog(@"[TiebaClean] " fmt, ##__VA_ARGS__)

#pragma mark -声明（均由静态索引确认存在）

@interface BLPMultiTabItemView : UIView
- (void)setText:(id)text;
- (id)text;
- (id)titleLabel;
@end

@interface BLPMultiTabItem : NSObject
- (id)title;
- (id)view;
- (BOOL)isDisplayed;
@end

@interface BLPRecommendFeedTabBar : UIView
- (void)initSubView;
- (void)configTabItems;
- (void)configWithFeedSource;
- (void)configMultiTabItem:(id)item;
- (id)startLiveButton;
- (id)createStartLiveButton;
- (void)setStartLiveButton:(id)button;
- (void)setupWithTabItems:(id)items tab:(id)tab;
@end

//顶栏横向 tab控件：持有 items数组，逐项计算 frame（layoutTabItemWithItem:frame:idx:）
@interface BLPMultiTabBar : UIView
- (id)items;
- (void)setItems:(id)items;
- (CGRect)layoutTabItemWithItem:(id)item frame:(CGRect)frame idx:(unsigned long long)idx;
@end

@interface TBCFeedAdFilter : NSObject
+ (id)filterAdList:(id)adList fromFeedList:(id)feedList statTag:(id)statTag extInfo:(id)extInfo minAdSpace:(long long)minAdSpace firstAdLocate:(long long)firstAdLocate;
@end

@interface TBCPromotionItem : NSObject
+ (BOOL)isPromotionValid:(id)item;
@end

@interface TBCCommercialAdBaseCell : UITableViewCell
- (void)setObject:(id)object;
@end

@interface TBCPluginFrsFeedAd : NSObject
- (void)handleAndInsertAds:(id)ads;
- (void)handleAds:(id)ads adList:(id)adList minAdSpace:(long long)minAdSpace firstAdLocate:(long long)firstAdLocate;
@end

#pragma mark -工具

static id TBCCall(id obj, SEL sel) {
 if (!obj || !sel) return nil;
 if (![obj respondsToSelector:sel]) return nil;
 return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

// 「有料」「直播」两个入口的文案判定
static BOOL TBCIsRemovedTabText(id text) {
 if (!text || ![text isKindOfClass:[NSString class]]) return NO;
 NSString *s = [(NSString *)text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if (s.length ==0) return NO;
 if ([s isEqualToString:@"有料"]) return YES;
 if ([s isEqualToString:@"直播"]) return YES;
 return NO;
}

//一个 tab条目是否要被整个拿掉（item级判定：title在 item或 view上都认）
static BOOL TBCItemIsRemovedTab(id item) {
 if (!item) return NO;
 if (TBCIsRemovedTabText(TBCCall(item, @selector(title)))) return YES;
 id v = TBCCall(item, @selector(view));
 if ([v isKindOfClass:[UIView class]] && TBCIsRemovedTabText(TBCCall(v, @selector(text)))) return YES;
 return NO;
}

//把「直播」按钮收成0尺寸，避免隐藏后仍占位
static void TBCKillLiveButton(id btn) {
 if (![btn isKindOfClass:[UIView class]]) return;
 UIView *v = (UIView *)btn;
 v.hidden = YES;
 v.alpha =0.0;
 v.frame = CGRectMake(v.frame.origin.x, v.frame.origin.y,0.0,0.0);
}

//广告类视图的类名兜底判定（用于未知具体子类的情况）
static BOOL TBCClassNameLooksLikeAdView(NSString *cn) {
 if (cn.length ==0) return NO;
 unichar c0 = [cn characterAtIndex:0];
 if (c0 != 'T' && c0 != 'B' && c0 != 'A' && c0 != 'D' && c0 != 'L' && c0 != 'S') return NO;
 NSString *l = [cn lowercaseString];
 if ([l containsString:@"legoadcard"]) return YES;
 if ([l containsString:@"commercialad"]) return YES;
 if ([l containsString:@"promotioncell"]) return YES;
 if ([l containsString:@"adcardcell"]) return YES;
 return NO;
}

//在 tab bar子树里找出「有料」「直播」条目并隐藏
static int TBCHideRemovedTabsInView(UIView *view, int depth) {
 if (!view || depth >8) return (0);
 int hit =0;
 NSString *cn = NSStringFromClass([view class]);
 if ([cn containsString:@"MultiTabItemView"]) {
 id text = TBCCall(view, @selector(text));
 if (TBCIsRemovedTabText(text)) {
 view.hidden = YES;
 view.alpha =0.0;
 hit++;
 }
 }
 if ([view isKindOfClass:[UIButton class]]) {
 UIButton *btn = (UIButton *)view;
 NSString *title = [btn titleForState:UIControlStateNormal];
 if (title.length ==0) title = btn.currentTitle;
 if (TBCIsRemovedTabText(title) && view.bounds.size.width <200.0) {
 view.hidden = YES;
 view.alpha =0.0;
 hit++;
 }
 }
 for (UIView *sub in view.subviews) {
 hit += TBCHideRemovedTabsInView(sub, depth +1);
 }
 return hit;
}

static void TBCApplyTabFilter(UIView *bar) {
 if (!bar) return;
 TBCKillLiveButton(TBCCall(bar, @selector(startLiveButton)));
 int n = TBCHideRemovedTabsInView(bar,0);
 if (n >0) TBClog(@"hided %d tab entry(ies)", n);
 //顶栏是异步数据驱动的，再补一刀
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
 dispatch_get_main_queue(), ^{
 TBCHideRemovedTabsInView(bar,0);
 });
}

#pragma mark -1.顶栏「有料」「直播」

%hook BLPMultiTabItemView

- (void)setText:(id)text {
 %orig;
 if (TBCIsRemovedTabText(text)) {
 self.hidden = YES;
 self.alpha =0.0;
 }
}

//零宽/隐藏后不吃点击，免得空位误触
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
 if (self.hidden || self.frame.size.width <=0.0) return nil;
 return %orig;
}

%end

%hook BLPMultiTabItem

- (BOOL)isDisplayed {
 if (TBCItemIsRemovedTab(self)) return NO;
 return %orig;
}

%end

%hook BLPRecommendFeedTabBar

- (void)initSubView {
 %orig;
 TBCApplyTabFilter(self);
}

- (void)configTabItems {
 %orig;
 TBCApplyTabFilter(self);
}

- (void)configWithFeedSource {
 %orig;
 TBCApplyTabFilter(self);
}

- (void)configMultiTabItem:(id)item {
 %orig;
 if (TBCItemIsRemovedTab(item)) {
 id v = TBCCall(item, @selector(view));
 if ([v isKindOfClass:[UIView class]]) ((UIView *)v).hidden = YES;
 }
 TBCApplyTabFilter(self);
}

//「直播」入口是在这里现造的，造完直接收成0尺寸
- (id)createStartLiveButton {
 id btn = %orig;
 TBCKillLiveButton(btn);
 return btn;
}

- (void)setStartLiveButton:(id)button {
 %orig;
 TBCKillLiveButton(button);
}

- (void)setupWithTabItems:(id)items tab:(id)tab {
 %orig;
 TBCApplyTabFilter(self);
}

%end

#pragma mark -1b.横向 tab控件：被干掉的条目不给宽度（消除空位）

%hook BLPMultiTabBar

- (CGRect)layoutTabItemWithItem:(id)item frame:(CGRect)frame idx:(unsigned long long)idx {
 if (TBCItemIsRemovedTab(item)) {
 id v = TBCCall(item, @selector(view));
 if ([v isKindOfClass:[UIView class]]) {
 ((UIView *)v).hidden = YES;
 ((UIView *)v).alpha =0.0;
 }
 //宽给0、起点保持不变：后面的 tab顺势左移，空位消失
 return CGRectMake(frame.origin.x, frame.origin.y,0.0, frame.size.height);
 }
 return %orig;
}

%end

#pragma mark -2.信息流广告（数据层过滤）

%hook TBCFeedAdFilter

+ (id)filterAdList:(id)adList fromFeedList:(id)feedList statTag:(id)statTag extInfo:(id)extInfo minAdSpace:(long long)minAdSpace firstAdLocate:(long long)firstAdLocate {
 id result = %orig;
 if ([result isKindOfClass:[NSArray class]] && [(NSArray *)result count] >0) {
 TBClog(@"dropped %lu feed ad(s)", (unsigned long)[(NSArray *)result count]);
 return @[];
 }
 return result;
}

%end

%hook TBCPromotionItem

//推广项一律判定为无效，避免进入渲染与埋点链路
+ (BOOL)isPromotionValid:(id)item {
 return NO;
}

%end

#pragma mark -3.帖子流插入的广告

%hook TBCPluginFrsFeedAd

//不执行原实现：该插件负责往帖子/吧内列表里插入广告 item，跳过即不插入
- (void)handleAndInsertAds:(id)ads {
 TBClog(@"skip frs feed ad insert");
}

//广告列表置空后再走原流程，保证插件内部状态自洽
- (void)handleAds:(id)ads adList:(id)adList minAdSpace:(long long)minAdSpace firstAdLocate:(long long)firstAdLocate {
 %orig(ads, @[], minAdSpace, firstAdLocate);
}

%end

#pragma mark -4. UI兜底：广告 cell /广告卡不显示

%hook TBCCommercialAdBaseCell

- (void)setObject:(id)object {
 %orig;
 self.hidden = YES;
 self.alpha =0.0;
}

%end

%hook UIView

- (void)didMoveToSuperview {
 %orig;
 NSString *cn = NSStringFromClass([self class]);
 if (TBCClassNameLooksLikeAdView(cn)) {
 if (!self.hidden) self.hidden = YES;
 if (self.alpha !=0.0) self.alpha =0.0;
 }
}

%end

#pragma mark -入口

%ctor {
 TBClog(@"loaded v0.2.0 (bundle=%s)", [NSBundle.mainBundle.bundleIdentifier UTF8String]);
}
