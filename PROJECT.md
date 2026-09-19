# 红果漫剧观看记录App

| 项目状态 | 创建日期 | 最近更新 |
| --- | --- | --- |
| v1.1.0 UI 修复批次待 CI/真机验收 | 2026-09-18 | 2026-09-19 |

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
- 本轮新增：首页改为固定封面尺寸的横向作品卡片，显示总集数、官方热度、官方评分、多级标签和个人进度；详情页复刻深色沉浸式信息层级，简介默认折叠并可展开，移除相关作品/猜你喜欢主区块；选集改为横向区间切换和自适应逐集网格；增加长标题 UI 回归样例；标题清理补充免费看片/免费观看前缀。
- 正在做：等待 GitHub Actions 完成本轮 v1.1.0 编译和 UI 截图验证，再等待真实 iPhone 验证分享扩展、App Groups、本地数据保存、封面加载和红果跳转。
- 下一步：根据 CI 截图和真机结果修复签名或跨 App 行为；用真实红果漫剧分享文本验证标题清理和页面季集结构，必要时补充红果专用解析规则。

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
- [x] UI 测试覆盖空书架和样例作品详情页截图。
- [x] 公开 HTML metadata 可写入本地数据库，并建立作品、季、集关系。
- [x] 混合分享文本可提取网页链接，作品名称可自动清理并写入记录。
- [x] 观看进度支持按季、100 集区间和逐集网格标记。
- [x] App Icon 已进入 Asset Catalog 和真机 IPA。
- [ ] Share Extension 已在真实红果漫剧页面验证。
- [ ] 真实 iPhone 已验证分享入口和红果跳转降级链路。
- [x] 已记录剩余限制和下一步。

## 本轮 CI 证据

- GitHub Actions Run：`35428368577`
- 结果：模拟器编译、5 个单元测试、1 个 UI 测试、无签名真机归档和 IPA 打包全部成功。
- 产物：`artifacts/RedFruitTracker-unsigned-device-v2.ipa`，约 650 KiB；未签名，仍需用户侧签名后安装。
- 解析边界：公开网页没有提供季/集专属链接时，应用不能凭空生成真实精准链接，会回退到本季或作品链接。
