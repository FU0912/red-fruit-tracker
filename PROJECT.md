# 红果漫剧观看记录App

| 项目状态 | 创建日期 | 最近更新 |
| --- | --- | --- |
| 规划中 | 2026-09-18 | 2026-09-18 |

## 一句话目标

构建基于 Windows + GitHub Actions macOS Runner 的原生 iOS 红果漫剧观看记录 App，支持分享链接导入公开资料、本地观看记录和趋势统计。

## 范围

### 包含

- 原生 iOS App，第一阶段以 iOS 17+ 为目标。
- Windows 工作区编写代码，GitHub Actions macOS Runner 负责构建和模拟器测试。
- SwiftUI 页面骨架与 SwiftData 本地模型。
- 红果漫剧分享链接接收入口，后续接入公开详情资料解析。
- 作品、季、集、个人观看进度、个人评分和官方数据快照的模型边界。
- 模拟器 UI 测试、截图和日志作为 CI 产物。

### 不包含

- Windows 本机安装或运行 macOS 虚拟机。
- 红果账号验证码登录、收藏同步、观看历史同步或读取 Cookie/token。
- 第一阶段服务器、多人账号和云端数据同步。
- 自建视频播放器。
- 在没有 Apple Developer 签名配置前发布 TestFlight。

## 当前状态

- 已完成：项目初始化；确认 Windows + GitHub Actions macOS Runner 路线；确认日常 UI 使用模拟器测试和截图产物，真机只做跨 App 能力验收；完成 SwiftUI/SwiftData、Share Extension、单元测试和 UI 测试骨架；完成 CI 工作流；首次构建修复 Bundle 元数据后，第二次 CI 已完整通过。
- 正在做：生成可下载的 Simulator App 压缩包，并准备真实 iPhone 签名流程。
- 下一步：下载新的 Simulator App 压缩包；如果要安装到真实 iPhone，先完成 Apple Developer 签名配置；随后接入公开分享链接解析。

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

- [ ] GitHub Actions 能生成 Xcode 项目并完成无签名模拟器构建。
- [ ] 单元测试和 UI 测试能在 macOS Runner 执行。
- [ ] CI 能保存 UI 截图、测试结果和构建日志。
- [ ] Share Extension 能接收真实红果漫剧分享链接。
- [ ] 公开资料能写入本地数据库并建立作品、季、集关系。
- [ ] 真实 iPhone 已验证分享入口和红果跳转降级链路。
- [ ] 已记录剩余限制和下一步。
