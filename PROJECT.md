# 红果漫剧观看记录App

| 项目状态 | 创建日期 | 最近更新 |
| --- | --- | --- |
| v1.2.29 重做热度周期趋势图并恢复彩色气泡指标，待 CI/真机验收 | 2026-11-03 | 进行中 |

## 一句话目标

构建基于 Windows + GitHub Actions macOS Runner 的原生 iOS 红果漫剧观看记录 App，支持分享链接导入公开资料、本地观看记录和趋势统计。

## 范围

### 包含

- 原生 iOS App，第一阶段以 iOS 17+ 为目标。
- Windows 工作区编写代码，GitHub Actions macOS Runner 负责构建和模拟器测试。
- SwiftUI 书架/画廊、搜索、统计和编辑页面。
- 红果漫剧分享链接接收入口，公开 HTML 元数据读取和手动填写兜底。
- 作品、季、集、个人观看进度、个人评分和官方数据快照的本地模型。
- App Icon、作品/季/集跳转链接和评分趋势图。
- 模拟器 UI 测试、截图和日志作为 CI 产物。

### 不包含

- Windows 本机安装或运行 macOS 虚拟机。
- 红果账号验证码登录、收藏同步、观看历史同步或读取 Cookie/token。
- 第一阶段服务器、多人账号和云端数据同步。
- 自建视频播放器。
- 在没有 Apple Developer 签名配置前发布 TestFlight。

## 当前状态

- 已完成：Windows + GitHub Actions macOS Runner 路线；SwiftUI/SwiftData 本地模型；Share Extension；书架搜索、作品编辑、分季分集、已看标记、观看进度、个人评分点评、官方数据字段和趋势页；公开网页元数据读取接口；App Icon；单元测试和 UI 测试；CI 模拟器编译、真机架构归档和未签名 IPA。
- 已完成：首页使用固定封面尺寸的横向作品卡片，显示总集数、官方热度、评分回退、多级标签和个人进度；详情页复刻深色沉浸式信息层级，简介默认折叠并可展开，移除相关作品/猜你喜欢主区块；当前详情页只保留作品信息、简介和整部作品评分点评；增加长标题 UI 回归样例；标题清理补充免费看片/免费观看前缀。
- v1.2.0 修复：首页卡片封面和右侧内容使用明确的固定/弹性布局，避免封面撑宽后覆盖标题；选集按钮增大间距和点击区域，去掉数字下方的圆形勾选及当前描边，仅用颜色区分状态；公开资料读取增加人物海报/封面候选排序，并在添加作品页允许从候选图中选择最终封面。
- v1.2.1 修复：识别红果官方详情页的预加载主图、JSON-LD `TVSeries.image` 和标题对应人物海报；横幅、背景、相关作品缩略图、锁图和其他 UI 图片不再抢占封面；低置信度图片只进入候选列表，不自动保存为封面。
- v1.2.2 修复：解析官方 SSR `detail_page.seriesDetail.series_cover`，优先使用当前作品卡的竖版人物海报；`videoList` 相关作品封面不再抢占当前作品；增加官方结构夹具和当前作品封面回归测试。
- v1.2.3 修复：封面组件改为显式固定尺寸和内部裁剪，详情页官方评分、热度和标签移到稳定的全宽信息区；移除详情页全局暗色方案切换，避免从首页进入和返回时黑白闪烁；SSR `seriesDetail` 增加简介、评分、热度、标签字段读取；增加详情页元数据和返回书架 UI 回归断言。
- v1.2.4 修复：首页和详情页封面使用固定列与固定裁剪边界，避免异步图片撑开布局；首页/详情页官方评分、热度和标签保留稳定位置，资料缺失时显示待读取状态；书架启动时自动补抓已有分享链接的公开资料；补充封面、标题、官方字段不越界的 UI 回归断言，并明确书架导航栏颜色以降低返回时黑白闪烁。
- v1.2.4 CI 已通过：Run `35556208404`，13 个单元测试和 2 个 UI 测试全部通过；截图确认首页/详情页封面、标题和官方字段没有越界，返回书架正常。
- v1.2.5 修复：详情页滚动内容为底部固定打开按钮预留足够空间，避免最后一排选集被遮挡；Run `35556774826` 已通过，13 个单元测试和 2 个 UI 测试全部通过，并生成无签名 IPA。
- v1.2.5 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.5-build8.ipa`，805152 字节；SHA-256 为 `05CBA12DDAB347644BB60F3A15C7D80C48E97092D3E85A345F9A8B5AF461A957`。未签名，仍需用户侧签名后安装。
- v1.2.6 已验证：自动刷新不再弹出快照提示；公开 SSR 读取 `seriesSocialInfo` 评分/热度、当前作品总集数和 `vid_list`，并按作品名合并相关季；详情页官方信息移到封面右侧，选集格和个人评分星星压缩。Run `35570088726` 通过，15 个单元测试和 2 个 UI 测试通过，并生成无签名 IPA。
- v1.2.6 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.6-build9.ipa`，826323 字节；SHA-256 为 `9411BAC95C1BF324BAB2DA0E948C09D37371DC1DF3106DA48D8BDBFFACA38772`。未签名，仍需用户侧签名后安装。
- v1.2.7 修复：适配红果漫剧分享页 `_ROUTER_DATA.loaderData["video-animation-share_page"].pageData`，统一读取当前作品标题、官方封面、热度、标签和章节数据；相关推荐不再被当成当前作品或其他季；分享页缺少官方封面时不再误用视频首帧或通用 `og:image`。
- v1.2.7 数据边界：用户提供的分享页公开数据包含热度 `38927338`、标签“玄幻、穿越、系统、修真、异界”和总集数 `245`；该页没有官方评分，也没有可用于推断其他季的列表，因此这些字段仍显示缺失或只显示已确认的当前季数据。
- v1.2.7 CI 已通过：Run `35806047811`，17 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成。
- v1.2.7 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.7-build10.ipa`，827153 字节；SHA-256 为 `7D954D19D5EB08560DB9DDEBE7F8F01BCFB44EBA27C88E05CAD4906B140FFC21`。未签名，仍需用户侧签名后安装。
- v1.2.8 已完成：按作品基础标题归并独立的第一、二、三季分享链接；每季保留自己的分享 URL、集数和公开数据，书架只显示一个作品；选集只突出唯一当前集，再次点击当前集可取消定位，历史已看数据仍保留用于统计。
- v1.2.8 真实公开数据核对：`天幕直播：古人每周来我家` 三个分享页分别读取到 148、168、176 集；三个页面没有官方评分字段，热度和标签按季读取。
- v1.2.8 CI 已通过：Run `35813922101`，21 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成；主 App 与 Share Extension 均为 build 11。
- v1.2.8 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.8-build11.ipa`，843048 字节；SHA-256 为 `62A51574E0470C299CA411EFBFF043FAAD1344A5841220FD8005C28BB3E8C6C3`。未签名，仍需用户侧签名后安装。
- v1.2.9 已完成：删除 `1-100`、`101-...` 区间按钮，选择季后直接展示本季 `1...总集数`；官方评分缺失时回退显示明确标注的“我的评分”；详情页查询按作品/季过滤，集数网格使用一次性索引配合 `LazyVGrid`，减少重复计算。
- v1.2.9 CI 已通过：Run `35942565874`，25 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成；主 App 与 Share Extension 均为 build 12。
- v1.2.9 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.9-build12.ipa`，835843 字节；SHA-256 为 `1EC5E5298E9FC3E2000E21070A7FCF7263235ED2EF9F636118D32FDD4F1ADA77`。未签名，仍需用户侧签名后安装。
- v1.2.10 已完成：保留季数、已看数量和总集数汇总；移除主详情页和季详情页的逐集方格/逐集资料列表；当前集数仍可手动输入并写入本地观看记录；主 App 与 Share Extension 版本更新为 build 13。
- v1.2.10 CI 已通过：Run `35960738893`，23 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成；主 App 与 Share Extension 均为 build 13。
- v1.2.10 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.10-build13.ipa`，820950 字节；SHA-256 为 `D4FFBDBF800759E7CA4118A2E4B9A6A56E80743C365F079412551DF148471954`。未签名，仍需用户侧签名后安装。
- v1.2.11 已完成：书架导航标题/搜索改为直接挂在可滚动列表，顶部大标题按原生行为收起；作品卡片底部移除当前观看季/集，改显示 `共 X 季`；分享扩展兼容 URL、文本和 Data 内容，入队后尽力唤起主 App，主 App 回到前台自动抓取公开资料并保存记录；主 App 与 Share Extension 更新为 build 14。
- v1.2.11 CI 已通过：Run `37083661180`，25 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成。
- v1.2.11 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.11-build14.ipa`，826511 字节；SHA-256 为 `C93140EE09BBD71583B67AA4FC28A488450EC90FA249A73F74C113818AEA8734`。未签名，仍需用户侧签名后安装。
- v1.2.12 已完成：书架大标题和搜索区改为列表首行，向下滚动时不再固定占据顶部；移除卡片底部季数留白，将 `共 X 季` 移到热度右侧；保留右滑删除；主 App 与 Share Extension 更新为 build 15。
- v1.2.12 CI 已通过：Run `37111337645`，25 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成。
- v1.2.12 产物：`artifacts/37111337645/artifacts/RedFruitTracker-unsigned-device-v1.2.12-build15.ipa`，840920 字节；SHA-256 为 `926B582FFCBD3234A6E25783D65379804282B230FFA9AA33F47C8CEFD78A7070`。未签名，仍需用户侧签名后安装。
- v1.2.13 已完成：书架信息 pill 收紧图标、文字和相邻间距；详情页使用参考图的中性灰背景，增加“打开红果漫剧”按钮；进入详情先显示本地旧资料，再后台刷新公开资料并自动更新当前页面；书架状态新增“弃剧”，进度输入不会覆盖手动弃剧；整部作品和每季评分改为 0-10 分、0.5 分步进，并在升级首次启动时迁移旧 1-5 星评分。
- v1.2.13 CI 已通过：Run `37133588002`，27 个单元测试和 2 个 UI 测试全部通过，模拟器包、真机架构归档和未签名 IPA 均已生成；主 App 与 Share Extension 均为 build 16。
- v1.2.13 产物：`artifacts/37133588002/artifacts/RedFruitTracker-unsigned-device-v1.2.13-build16.ipa`，874290 字节；SHA-256 为 `1D98AF92643A904D7F95B53A12876D31F4483482DAE7FACB487B14ED8FAD7354`。未签名，仍需用户侧签名后安装。
- v1.2.14 已完成：评分编辑改为原生离散菜单，去掉进度条样式；封面加载增加缓存、请求头和可信人物海报候选过滤；红果分享通过 URL scheme 和 App Group 队列直达导入；增加已完结/未完结、后台公开资料更新、隐藏季集历史变化记录、官方热度/评分 K 线和统计页实用指标。
- v1.2.14 CI 已通过：Run `37310763734`，30 个单元测试和 2 个 UI 测试全部通过，模拟器构建、真机架构归档和未签名 IPA 均成功；主 App 与 Share Extension 均为 build 17。
- v1.2.14 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.14-build17.ipa`，954668 字节；SHA-256 为 `9BF9460677F7173334FAF9DCEFD11C817F570231DF174CA17AE797F7AA79C0BF`。包内含 Share Extension，但未签名，仍需用户侧签名后安装。
- v1.2.15 已完成：书架和详情页增加观看状态标签；完结状态改为手动选择，公开资料更新不再覆盖；统计页支持作品状态筛选并保留季集数变化记录入口；个人评分显示为纯数值；趋势图改用独立语义色面板；封面候选只自动采用实际探测到的竖版图片，缺图时显示带标题的占位。
- v1.2.15 CI 已通过：Run `37327307931`，32 个单元测试和 2 个 UI 测试全部通过，模拟器构建、真机架构归档和未签名 IPA 均成功；主 App 与 Share Extension 均为 build 18。
- v1.2.15 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.15-build18.ipa`，1,031,636 字节；SHA-256 为 `813D8197A33766981EC1C5E67BA0C63C98D7620C7B85F6512E1EA2C5BD59AFCB`。包内含 Share Extension 和 App Icon，但没有 `_CodeSignature` 或 `embedded.mobileprovision`，仍需用户侧签名后安装。
- v1.2.16 已完成：剧级封面按真实图片尺寸选择，新增独立追更/预约状态和统计筛选；季链接读取到的多季资料归并到同一部作品，趋势图改为固定评分范围、少量坐标和语义背景。版本号为 build 19。
- v1.2.18 本轮：分享页提取 `video_id` 后优先读取官方详情页，使用详情页 `seriesDetail.series_cover` 并下载检查真实图像方向，只接受竖版剧级海报；详情页公开字段优先于分享页回退字段。分享扩展把完整链接写入 App Group，只发送短唤醒 URL，主 App 前台读取队列并延迟重试后自动打开导入页。主 App 与 Share Extension 更新为 build 21。
- v1.2.18 CI 已通过：Run `38132924380`（最终修复提交 `c18afd2`），38 个单元测试和 2 个 UI 测试全部通过，模拟器构建、真机架构归档和未签名 IPA 均成功。
- v1.2.18 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.18-build21.ipa`，1,088,606 字节；SHA-256 为 `1D446C0E456405B50CCDF8283DC3B696C6649A01B7E1B02A931CD11B2375DF74`。包内含主 App、Share Extension 和 App Icon，但无 `_CodeSignature` 或 `embedded.mobileprovision`，仍需用户侧签名后安装。
- v1.2.20 / build 23：候选封面按 Byteimg 作品资源 ID 合并 CDN/尺寸变体；整库刷新从请求开始写入 24 小时尝试冷却；书架显示创建时间并分开展示官方与个人评分；趋势快照只写本次真实热度，不再回填旧热度或新写官方评分历史；季集解析支持 snake_case 列表、`video_data.video_list[].vid_index`，并合并详情页与分享页季信息。CI 与真机尚未验证。
- v1.2.16 CI 已通过：Run `38099393357`，34 个单元测试和 2 个 UI 测试全部通过，模拟器构建、真机架构归档和未签名 IPA 均成功；主 App 与 Share Extension 均为 build 19。
- v1.2.16 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.16-build19.ipa`，1,065,434 字节；SHA-256 为 `4BB4D4679965FA8A0CF3AD8E09CCEC094103D3C83DAB248199E053C385F2ABBF`。包内含 Share Extension 和 App Icon，但没有 `_CodeSignature` 或 `embedded.mobileprovision`，仍需用户侧签名后安装。
- 本轮详情页与删除调整已完成：主详情页移除“选集”起始的季数、集数、当前进度和打开当前入口，保留作品信息、简介以及“我的评分与点评”；书架作品行支持 trailing swipe action 的 `List`，确认后删除作品及其季、集、个人记录和公开快照。
- 本轮封面规则：分享页横向 `video_meta` 的 `series_cover` 及同 URL 的通用图片字段不再自动作为封面；若存在不同 URL 的 `series_cover_fallback`/`poster`，优先使用备用人物海报；若页面只提供横向视频图，自动封面保持为空并等待候选或手动选择。当前真实分享页的主图和 fallback 是同一横向图，仍需真实竖版字段或真机候选验证。
- 待验收：真实 iPhone 上的分享扩展、App Groups、本地数据保存、公开封面加载和红果跳转；CI 结构与自动化测试已通过。
- 下一步：在真机用用户提供的真实分享文本验收 Share Extension、封面、季集数据和跳转；若页面实际提供另一张人物海报，再依据真实字段补充候选规则。

## 关键决策

- 产品技术路线：SwiftUI + SwiftData + Share Extension。
- 开发环境：Windows 编写代码；不安装本地 macOS 虚拟机。
- 构建验证：GitHub Actions macOS Runner；每次提交编译和单元测试，需要时运行 UI 测试并上传截图。
- 数据策略：第一阶段本地优先，代码中保留 Repository/RemoteStore 扩展边界。
- 账号边界：只采集分享链接可公开取得的作品资料，不实现红果账号私有数据同步。

## 复盘与全局沉淀

- 不满意的结果、错误或弯路：暂无。
- 已验证、未来可复用的方法：暂无。
- 已同步到全局复利与踩坑日志：否。

## 运行与验证

```text
macOS Runner:
  brew install xcodegen
  xcodegen generate --spec project.yml
  xcodebuild build -project RedFruitTracker.xcodeproj -scheme RedFruitTracker \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO

Windows:
  负责编辑代码和检查项目结构；没有 Xcode 时不能替代 macOS Runner 执行 iOS 编译。
```

## 完成标准

- [x] GitHub Actions 能生成 Xcode 项目并完成无签名模拟器构建。
- [x] 单元测试和 UI 测试能在 macOS Runner 执行。
- [x] CI 能保存 UI 截图、测试结果和构建日志。
- [x] 主 App 已具备作品、季、集、本地进度、整部作品评分点评和每季独立评分点评界面。
- [x] 首页卡片与详情页已针对长标题、封面尺寸、深色层级和选集网格完成布局修复。
- [x] 首页封面固定尺寸、右侧信息使用剩余宽度，选集状态改为更宽松的纯色块。
- [x] 公开图片候选增加人物海报/封面优先级，并提供候选封面选择入口。
- [x] UI 测试覆盖空书架和样例作品详情页截图。
- [x] 公开 HTML metadata 可写入本地数据库，并建立作品、季、集关系。
- [x] 混合分享文本可提取网页链接，作品名称可自动清理并写入记录。
- [x] 观看进度按季保留已看/总集数汇总和当前集数输入，不展开逐集方格或逐集列表。
- [x] 官方评分缺失时以“我的评分”作为明确标注的显示回退。
- [x] 详情页和选集网格完成按范围查询、集数索引和懒加载优化。
- [x] App Icon 已进入 Asset Catalog 和真机 IPA。
- [ ] Share Extension 已在真实红果漫剧页面验证。
- [ ] 真实 iPhone 已验证分享入口、详情页稳定布局和红果跳转降级链路。
- [x] 已记录剩余限制和下一步。

## CI 证据

- v1.2.2 GitHub Actions Run：`35486159993`（提交 `a3fa21a`）。
- v1.2.2 结果：XcodeGen、模拟器编译、12 个单元测试、2 个 UI 测试、模拟器包、无签名真机归档和 IPA 打包全部成功。
- v1.2.2 新增测试全部通过：当前 `seriesDetail.series_cover` 优先于预加载主视觉和相关作品，官方转义 URL 可解析，低置信度图片回退规则保持有效。
- v1.2.2 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.2-build5.ipa`，777922 字节；SHA-256 为 `6AE5689F4D8000F84608013F8CA2176F0D1776F4BCCAD7BC02EF952B60CFFC7F`。未签名，仍需用户侧签名后安装。
- v1.2.1 结果：XcodeGen、模拟器编译、10 个单元测试、2 个 UI 测试、模拟器包、无签名真机归档和 IPA 打包全部成功。
- v1.2.1 新增测试全部通过：官方详情页预加载主图/JSON-LD 主图提取、人物海报优先于相关作品和 UI 图片、低置信度图片不自动选用。
- v1.2.1 产物：`artifacts/RedFruitTracker-unsigned-device-v1.2.1-build4.ipa`，771003 字节；SHA-256 为 `6BB25427BF01F47205503A6E7A76595B4B6D7C7682B7329AAA224BD081A8475A`。未签名，仍需用户侧签名后安装。
- v1.2.1 截图：`artifacts/v1.2.1-library-card.png`、`artifacts/v1.2.1-series-detail.png`、`artifacts/v1.2.1-add-series.png`。首页和详情页布局未回归；固定 UI 样例没有真实封面 URL，因此显示占位图，不能替代真实分享链接的封面加载验收。
- 历史 CI Run：`35431700494`（提交 `c7973d4`）；此前的模拟器编译、5 个单元测试、2 个 UI 测试、截图、无签名真机归档和 IPA 打包也全部成功。
- 历史产物：`artifacts/RedFruitTracker-unsigned-device-v1.1.0-build2.ipa`，738262 字节；SHA-256 为 `9B624BC148F042F8D6220A76AF2F27AD7937E47B25DFE7FFEBB68BFB3F97BDB0`。未签名，仍需用户侧签名后安装。
- 解析边界：公开网页没有提供季/集专属链接时，应用不能凭空生成真实精准链接，会回退到本季或作品链接。

## v1.2.10 剩余验证

- 代码版本为 `1.2.10`、构建号 `13`，GitHub Actions 已完成 Xcode 编译、23 个单元测试、2 个 UI 测试、未签名真机归档和 IPA 打包；仍需真实 iPhone 验证安装、分享扩展、本地数据保存、封面加载和红果跳转。
- 真实用户分享链接仍需在真机验证网络、官方人物海报加载、Share Extension、红果跳转和页面季集数据。

## 交接包

- 已生成桌面交接包 `C:\Users\F\Desktop\红果漫剧观看记录App_项目交接包_v1.2.10.zip`，包含当前源代码、完整需求与决策、技术架构、版本验证、全部历史 IPA、视觉参考和下一步开发提示词。
- 交接包内另有 `项目源码/交接说明_v1.2.10.md` 和 `交接包清单.txt`，用于在另一台设备上继续开发。
- 交接包不包含 `.git`、构建缓存、证书、私钥、验证码、token 或个人隐私；GitHub 仓库和提交历史摘要已记录在交接文档中。
