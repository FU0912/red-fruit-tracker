# 红果漫剧观看记录 App

这是一个本地优先的原生 iOS 项目，用来记录红果漫剧作品、季、集、观看进度、个人评分点评和官方数据历史。

当前源代码版本为 `v1.2.5` / build `8`，本轮补充详情页底部安全留白，避免固定打开按钮遮挡最后一排选集；`v1.2.4` / build `7` 已修复首页/详情页封面溢出、返回时配色闪烁，以及官方评分、热度、简介和标签的稳定显示与已有作品自动补抓。历史版本产物仍保留在 `artifacts` 目录。

当前版本已经具备可操作的本地 MVP：作品画廊和搜索、分享链接/手动添加、封面和公开 metadata 读取、分季分集、已看标记、观看进度、红果链接跳转、个人评分点评、统计和评分趋势图。

## 当前开发方式

- Windows：Codex 编辑代码、维护配置和提交 Git。
- GitHub Actions：使用 macOS Runner 生成 Xcode 项目、编译和运行测试。
- iOS Simulator：在 CI 中执行 UI 测试并保存截图和日志。
- 真实 iPhone：只用于 Share Extension、红果跳转和系统行为的阶段性验收。

本项目不依赖本地 macOS 虚拟机。最新已验证的未签名真机包来自 GitHub Actions Run `35556774826`，文件为 `artifacts/RedFruitTracker-unsigned-device-v1.2.5-build8.ipa`；历史版本仍保留在 `artifacts` 目录。

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

最近一次 CI Run 为 `35556774826`，13 个单元测试和 2 个 UI 测试全部通过，并生成模拟器包和无签名真机 IPA。当前版本新增首页/详情页固定布局、官方字段稳定显示、返回路径回归断言和详情页底部安全留白；CI fixture 使用占位封面，因此截图中的占位图不代表真实红果分享链接的最终封面。

v1.2.5 IPA：805152 字节；SHA-256 为 `05CBA12DDAB347644BB60F3A15C7D80C48E97092D3E85A345F9A8B5AF461A957`。

## 数据边界

当前只处理分享链接能够取得的公开作品资料。红果账号收藏、观看记录、验证码、Cookie、token 不进入项目数据模型；公开资料读取失败时可以手动保存。
