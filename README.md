# TiebaClean

百度贴吧（com.baidu.tieba）精简补丁，roothide / arm64e。

##功能

1.去掉首页顶栏的「有料」「直播」入口（`BLPRecommendFeedTabBar` / `BLPMultiTabItemView`）
2.去掉信息流里的商业广告卡，例如「度小满」（`TBCFeedAdFilter` / `TBCPromotionItem`）
3.去掉帖子/吧内列表里插入的广告，例如「七猫免费小说」下载卡（`TBCPluginFrsFeedAd`）

##构建

推送到 main或手动 workflow_dispatch触发 GitHub Actions云编译（theos + roothide scheme），产物为 `TiebaClean-deb`。

##原理

-所有类名/selector均来自 app-method-index对 TBClient主程序的静态索引，未编造符号。
-仅压缩 UI展示与广告插入链路：数据层过滤广告列表 +关键视图隐藏，不改动正常内容请求。

