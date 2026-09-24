# 红果漫剧观看记录 App

这是一个本地优先的原生 iOS 项目，用来记录红果漫剧作品、季、集、观看进度、个人评分点评和官方数据历史。

当前源代码版本为 `v1.2.10` / build `13`，本轮保留季数与已看/总集数汇总，移除逐集方格和逐集资料列表，并保留当前集数输入；历史版本仍保留在 `artifacts` 目录。

当前版本已经具备可操作的本地 MVP：作品画廊和搜索、分享链接/手动添加、封面和公开 metadata 读取、分季分集、已看标记、观看进度、红果链接跳转、个人评分点评、统计和评分趋势图。

## 当前开发方式

- Windows：Codex 编辑代码、维护配置和提交 Git。
- GitHub Actions：使用 macOS Runner 生成 Xcode 项目、编译和运行测试。
- iOS Simulator：在 CI 中执行 UI 测试并保存截图和日志。
- 真实 iPhone：只用于 Share Extension、红果跳转和系统行为的阶段性验收。

本项目不依赖本地 macOS 虚拟机。本轮 `v1.2.10` 使用 GitHub Actions macOS Runner 构建；CI 完成后会生成对应版本的未签名真机 IPA，历史版本仍保留在 `artifacts` 目录。

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
4. 使用 iPhoneOS SDK 完成真机架构归档；
5. 生成未签名 IPA，并上传测试结果、截图和构建日志。

签名、TestFlight 和真实设备安装暂不自动化，等模拟器构建稳定后再配置。

本轮 `v1.2.10` CI 将验证季数汇总、当前集数输入、逐集列表移除以及既有公开资料和评分回退回归；主 App 与 Share Extension 均为 build 13。

v1.2.9 IPA：835843 字节；SHA-256 为 `1EC5E5298E9FC3E2000E21070A7FCF7263235ED2EF9F636118D32FDD4F1ADA77`。该 IPA 面向真机架构但未签名，不能直接安装到 iPhone。

v1.2.7 IPA：827153 字节；SHA-256 为 `7D954D19D5EB08560DB9DDEBE7F8F01BCFB44EBA27C88E05CAD4906B140FFC21`。该 IPA 面向真机架构但未签名，不能直接安装到 iPhone。

## 数据边界

当前只处理分享链接能够取得的公开作品资料。红果账号收藏、观看记录、验证码、Cookie、token 不进入项目数据模型；公开资料读取失败时可以手动保存。
