# 红果桌面版封面、跨季与追更研究

研究日期：2026-10-11（Asia/Shanghai）
目标：核对用户提供的 `waligoraamodio288-rgb/hongguo-desktop-releases`，并追踪其公开关联客户端 `zhangbaio/hongguo` 中能够复核的封面、季集合和收藏/状态证据。

## 结论摘要

1. **桌面版展示的剧目封面来自内容服务，不是从视频抽帧。** 发行仓库 README 只说明截图中的封面“来自内容服务”，并没有公开桌面应用的实现源码。公开 Python 客户端则直接读取接口 JSON 的 `cover`、`series_cover` 和 `horiz_cover` 字段；详情解析优先使用剧级 `series_cover`，才以第一集 `episode_cover`/`cover` 兜底。
2. **不应把横向封面或第一集封面当成用户要的正式人物海报。** 在当前 App 中，应把剧级 `series_cover`（或搜索/分类结果的 `cover`）作为正式候选，并检查实际图像尺寸/方向；只有剧级字段为空时才显示占位或进入候选，不应自动保存第一集图像，更不应从视频画面抽帧。
3. **跨季没有被公开客户端证明为一个可直接枚举的 season-group API。** 桌面版 1.0.12 的公开说明是按剧名找候选，用户核对完整标题、季数和版本后手动选择；说明明确提示同名条目可能不完整或属于不同版本。因此 App 应按稳定的作品主体键（优先官方 series ID，缺失时规范化标题）归并，保存各季为子记录，并提供候选核对/合并，而不是要求用户把每一季当成独立作品。
4. **追更/预约应是本 App 的本地观看意图，不要误当成官方完结状态。** 公开客户端只返回 `followed_cnt`（关注人数统计），没有看到收藏写入或预约动作；发行 README 只声明“收藏”和本机观看记录。建议保留官方 `完结/连载中` 作为只读元数据，另设本地状态：`想看/追更/等待更新/观看中/已看完/暂时搁置/弃剧`，并按“等待更新”筛选。

## 发行仓库：能证明什么

发行仓库 `main` 当前提交为 [`9825724`](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/commit/98257240012f72399a897c02957c4299e70679e6)。它是发行与反馈仓库，不是桌面应用源码仓库。README 在 [第 87 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/98257240012f72399a897c02957c4299e70679e6/README.md#L87)明确写明“不包含私有应用源码或签名私钥”。因此，该仓库不足以推导出桌面 WebView/服务端的具体封面解析代码。

同一 README 对截图的说明是封面“来自内容服务”([README 第 15 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/98257240012f72399a897c02957c4299e70679e6/README.md#L15))。这支持“服务返回海报 URL”的结论，但本身没有给出字段名或 URL 规则。

跨季行为在 1.0.12 的发行说明中有明确产品证据：播放时点击“查找其他季”，滚动候选、核对“完整标题、季数和版本”后选择；不带季数后缀的同名条目仍需核对([README 第 31-33 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/10f8ed3485dca8742b3e8bf3eacae04152a9de6f/README.md#L31-L33))。更新说明进一步说该结果来自标题匹配，可能不完整，也可能包含同季不同版本([README 第 43 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/10f8ed3485dca8742b3e8bf3eacae04152a9de6f/README.md#L43))。

发行 README 的产品入口写“搜索、收藏、本机观看进度”([README 第 3 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/98257240012f72399a897c02957c4299e70679e6/README.md#L3))，并明确观看进度不与手机红果账号/历史同步([README 第 25 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/98257240012f72399a897c02957c4299e70679e6/README.md#L25))；跨设备同步 Issue 也说明收藏和观看记录仅保存在当前电脑([README 第 59 行](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/98257240012f72399a897c02957c4299e70679e6/README.md#L59))。这些是本地产品能力的证据，不是官方账号收藏 API 的证据。

## 公开客户端：封面字段和解析路径

以下代码引用固定到公开仓库提交 [`5f8a58d`](https://github.com/zhangbaio/hongguo/commit/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9)，避免随 `main` 变化导致行号漂移。

### 搜索/分类结果

`_parse_search_cell` 先从 `book_id`/`search_result_id` 得到作品 ID，再读取 `video_data`。返回结果把 `vdata.cover` 优先于嵌套 `video_detail.series_cover`，同时保留 `horiz_cover` ([`hongguo.py` 第 291-323 行](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py#L291-L323))：

```python
"cover": vdata.get("cover") or inner.get("series_cover") or "",
"horiz_cover": vdata.get("horiz_cover") or "",
```

分类浏览也直接把列表项的 `it["cover"]` 作为 `cover` 返回，同时暴露 `horiz_cover` ([`hongguo.py` 第 735-784 行](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py#L735-L784))。这说明正确方向是消费红果返回的剧目海报字段，而不是从 `vid` 下载视频后取帧。

### 详情/剧集结果

详情接口请求使用 `/novel/player/multi_video_detail/v1/`，请求体只带 `series_id` 和图像缩放参数 ([`hongguo.py` 第 371-377 行](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py#L371-L377))。解析时：

- 每集的图片字段是 `episode_cover`，回退到该集的 `cover`（第 380-387 行）。
- 整剧元数据的 `cover` 先取 `vd.series_cover`，为空才取第一集封面（第 389-405 行）。
- 详情元数据同时包含 `series_status`（映射为“完结/连载中”）和 `followed_cnt`（关注人数计数），并没有本地用户状态字段（第 394-405 行）。

对应代码见 [`hongguo.py` 第 380-407 行](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py#L380-L407)：

```python
"cover": (vd or {}).get("series_cover") or first_ep_cover,
"status": "完结" if (vd or {}).get("series_status") == 1 else "连载中",
"followed_cnt": (vd or {}).get("followed_cnt", 0),
```

这条回退链正是当前 App 需要收紧的地方：`first_ep_cover` 可能是横向视频图或抽帧式图，不应代替人物海报。若 `series_cover` 缺失，应标记“官方海报缺失”并保留手动候选，而不是自动落到第一集图。

### 官方完结状态筛选

公开客户端的分类接口把官方创作状态作为 `creation_status` 维度，仅支持“已完结/连载中”两个映射值 ([`hongguo.py` 第 683-704 行](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py#L683-L704))，并将它作为请求筛选条件传给 `select_items` ([`hongguo.py` 第 735-763 行](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py#L735-L763))。这与用户自己的“想看/追更/等待更新/已看完”等观看意图是两个维度，不应共用一个字段。

## 对 RedFruitTracker 的落地建议

### 封面

1. 解析优先级：`series_cover`/剧级 `cover` > 可信的独立 `poster`/人物海报字段 > 手动候选；明确排除 `horiz_cover`、`episode_cover`、视频 `main_url` 和视频首帧。
2. 下载后做真实图像探测：确认响应是图像、宽高有效、竖版比例符合海报；失败时保留 URL 作为候选并显示“待选海报”，不要把错误图写进正式 `coverURL`。
3. 对同一作品保存 `coverSource`/`coverConfidence` 或等价审计字段，记录字段名和探测时间，便于后续 API 变化时追溯。

### 跨季

建议数据关系：

```text
SeriesGroup (作品主体：规范化标题/官方主体键)
  └─ Season (seasonNumber、seriesID、title、episodeCount、sourceURL)
       └─ Episode (seasonID、episodeNumber、vid、episodeURL)
```

导入新链接时先用官方 `seriesID` 归并；没有稳定主体键时用去除“第X季/季数/版本”等后缀的规范化标题做候选，不直接强合并。显示层只展示“共 N 季”，详情/审计页保存每季链接、季数、集数和变化时间。标题匹配的候选必须让用户确认，沿用发行版“查找其他季”的产品证据。

### 追更/预约

在 `SeriesGroup` 上增加本地 `watchIntent`（例如 `wantToWatch`、`following`、`waitingForUpdate`、`watching`、`completed`、`paused`、`dropped`）和可选 `reminderNote`/`nextCheckAt`。官方 `seriesStatus` 继续保留为只读 `finished/ongoing`。书架和统计页分别支持“等待更新/预约”筛选；它不会被官方数据刷新覆盖。

## 未证实边界

- 发行仓库没有桌面应用源码，公开材料未能确认其 WebView 实际使用的是哪个具体 CDN 图片字段、是否在服务端做了图片转换，或是否有专门的海报 API。
- `zhangbaio/hongguo` 是公开 API 客户端/下载器，能证明字段和解析策略，但不等于发行版桌面播放器的完整实现。
- 公开代码只显示 `followed_cnt` 计数，没有收藏/预约写入接口；“收藏”能力的持久化实现属于发行版私有代码或本地数据库，需通过真机/桌面运行验证。

## 来源索引

- [hongguo-desktop-releases README @ 9825724](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/blob/98257240012f72399a897c02957c4299e70679e6/README.md)
- [hongguo-desktop-releases v1.0.12 release notes](https://github.com/waligoraamodio288-rgb/hongguo-desktop-releases/releases/tag/v1.0.12)
- [zhangbaio/hongguo hongguo.py @ 5f8a58d](https://github.com/zhangbaio/hongguo/blob/5f8a58d10f48954bc9b6a58c9cd6418bf499feb9/hongguo.py)
