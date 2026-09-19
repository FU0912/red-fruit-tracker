# 红果漫剧观看记录 App

这是一个本地优先的原生 iOS 项目，用来记录红果漫剧作品、季、集、观看进度和官方数据历史。

## 当前开发方式

- Windows：Codex 编辑代码、维护配置和提交 Git。
- GitHub Actions：使用 macOS Runner 生成 Xcode 项目、编译和运行测试。
- iOS Simulator：在 CI 中执行 UI 测试并保存截图和日志。
- 真实 iPhone：只用于 Share Extension、红果跳转和系统行为的阶段性验收。

本项目不依赖本地 macOS 虚拟机。

## 生成项目

项目文件由 XcodeGen 根据 `project.yml` 生成，不直接提交生成的 `.xcodeproj`：

```bash
brew install xcodegen
xcodegen generate --spec project.yml
```

## CI

工作流位于 `.github/workflows/ios.yml`，当前目标是：

1. 在 macOS Runner 上生成 Xcode 项目；
2. 完成无签名 iOS Simulator 构建；
3. 运行单元测试和 UI 测试；
4. 上传测试结果、截图和构建日志。

签名、TestFlight 和真实设备安装暂不自动化，等模拟器构建稳定后再配置。

## 数据边界

第一阶段只处理分享链接能够取得的公开作品资料。红果账号收藏、观看记录、验证码、Cookie、token 不进入项目数据模型。
