# 红果漫剧观看记录 App

这是一个本地优先的原生 iOS 项目，用来记录红果漫剧作品、季、集、观看进度、个人评分点评和官方数据历史。

当前源代码版本为 `v1.2.75` / build `78`。统计页顶部只保留预约入口，观看类型区域可直接进入连续对比排行；预约卡片使用紧凑对齐布局；搜索标签会同步显示多个 `#标签` 查询。

当前版本已经具备可操作的本地 MVP：作品画廊和搜索、分享链接/手动添加、封面和公开 metadata 读取、分季分集、已看标记、观看进度、红果链接跳转、个人评分点评和统计。官方热度快照仍保存在本地，详情页暂不展示趋势图。

## 当前开发方式

- Windows：Codex 编辑代码、维护配置和提交 Git。
- GitHub Actions：使用 macOS Runner 生成 Xcode 项目、编译和运行测试。
- iOS Simulator：在 CI 中执行 UI 测试并保存截图和日志。
- 真实 iPhone：只用于 Share Extension、红果跳转和系统行为的阶段性验收。

本项目不依赖本地 macOS 虚拟机。`v1.2.75` 使用 GitHub Actions `macos-15-intel` Runner 构建验证；未签名 IPA 仍需用户侧签名后安装，分享扩展唤起、剪贴板提示与 Widget 显示仍需真机确认。

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

本轮 `v1.2.16` CI 已通过：Run `38099393357`，34 个单元测试和 2 个 UI 测试全部通过，模拟器构建、真机架构归档和未签名 IPA 均成功；主 App 与 Share Extension 统一为 build 19。

v1.2.16 IPA：1,065,434 字节；SHA-256 为 `4BB4D4679965FA8A0CF3AD8E09CCEC094103D3C83DAB248199E053C385F2ABBF`。包内已确认包含主 App、Share Extension 和 App Icon；没有 `_CodeSignature` 或 `embedded.mobileprovision`，仍需在用户侧签名后安装到 iPhone。

v1.2.15 IPA：1,031,636 字节；SHA-256 为 `813D8197A33766981EC1C5E67BA0C63C98D7620C7B85F6512E1EA2C5BD59AFCB`。包内已确认包含主 App、Share Extension 和 App Icon；没有 `_CodeSignature` 或 `embedded.mobileprovision`，仍需在用户侧签名后安装到 iPhone。

v1.2.14 IPA：954668 字节；SHA-256 为 `9BF9460677F7173334FAF9DCEFD11C817F570231DF174CA17AE797F7AA79C0BF`。该 IPA 面向真机架构但未签名，需要先签名后安装到 iPhone。包内已确认包含主 App、Share Extension 和 App Icon。

v1.2.13 IPA：874290 字节；SHA-256 为 `1D98AF92643A904D7F95B53A12876D31F4483482DAE7FACB487B14ED8FAD7354`。该 IPA 面向真机架构但未签名，需要先签名后安装到 iPhone。

v1.2.12 IPA：840920 字节；SHA-256 为 `926B582FFCBD3234A6E25783D65379804282B230FFA9AA33F47C8CEFD78A7070`。该 IPA 面向真机架构但未签名，需要先签名后安装到 iPhone。

v1.2.11 IPA：826511 字节；SHA-256 为 `C93140EE09BBD71583B67AA4FC28A488450EC90FA249A73F74C113818AEA8734`。该 IPA 面向真机架构但未签名，不能直接安装到 iPhone。

上一版 v1.2.9 IPA：835843 字节；SHA-256 为 `1EC5E5298E9FC3E2000E21070A7FCF7263235ED2EF9F636118D32FDD4F1ADA77`，仍保留在 `artifacts` 目录。

v1.2.7 IPA：827153 字节；SHA-256 为 `7D954D19D5EB08560DB9DDEBE7F8F01BCFB44EBA27C88E05CAD4906B140FFC21`。该 IPA 面向真机架构但未签名，不能直接安装到 iPhone。

## 数据边界

当前只处理分享链接能够取得的公开作品资料。红果账号收藏、观看记录、验证码、Cookie、token 不进入项目数据模型；公开资料读取失败时可以手动保存。
