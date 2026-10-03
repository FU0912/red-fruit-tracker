# 安装与当前验证方式

## 最近一次已验证包

当前代码版本为 `v1.2.12` / build `15`；本轮代码已提交，CI 尚未完成。最近一次已通过的版本为 `v1.2.11` / build `14`，Run `37083661180`。

`v1.2.12` 的 IPA 尚未生成。CI 完成前请使用下方的 `v1.2.11` 已验证包，不要把当前源码版本误认为已打包版本。

`artifacts/RedFruitTracker-unsigned-device-v1.2.11-build14.ipa`

已验证包体 826511 字节，SHA-256：

`C93140EE09BBD71583B67AA4FC28A488450EC90FA249A73F74C113818AEA8734`

上一版已验证包：`artifacts/RedFruitTracker-unsigned-device-v1.2.9-build12.ipa`

已验证包体 835843 字节，SHA-256：

`1EC5E5298E9FC3E2000E21070A7FCF7263235ED2EF9F636118D32FDD4F1ADA77`

旧版本仍保留：

- `artifacts/RedFruitTracker-unsigned-device-v1.2.1-build4.ipa`
- `artifacts/RedFruitTracker-unsigned-device-v1.2.4-build7.ipa`（本轮之前的已验证版本）
- `artifacts/RedFruitTracker-unsigned-device-v1.2.5-build8.ipa`
- `artifacts/RedFruitTracker-unsigned-device-v1.2.6-build9.ipa`
- `artifacts/RedFruitTracker-unsigned-device-v1.2.7-build10.ipa`
- `artifacts/RedFruitTracker-unsigned-device-v2.ipa`
- `artifacts/RedFruitTracker-unsigned-device-mvp.ipa`

包内已确认包含 Assets.car、iPhone/iPad App Icon、主 App 和 Share Extension。

GitHub Actions 当前生成的是 `RedFruitTracker-simulator.app.zip`。它是 iOS Simulator 构建包，只能在 macOS 的 iOS Simulator 中安装，不能直接安装到真实 iPhone。

`RedFruitTracker-unsigned-device-v1.2.11-build14.ipa` 是面向真实 iPhone 架构的未签名测试包，不能直接安装；可以在 Windows 上用 Sideloadly 或 AltStore 由你自己的 Apple ID 进行本地签名。免费 Apple ID 通常有设备数和有效期限制，分享扩展/App Groups 也可能需要付费开发者账号。

## 真实 iPhone 安装包

真实 iPhone 需要签名后的 `.ipa`。后续需要：

1. Apple Developer 账号和可用的 App ID。
2. iOS Development 或 Ad Hoc 证书。
3. 与证书匹配的 provisioning profile。
4. 将签名材料以 GitHub Actions Secrets 的形式配置到私有仓库。

证书私钥、Apple ID 密码、验证码和 provisioning profile 不应发到对话中。配置完成后，CI 才能生成可安装的 IPA，再通过 TestFlight 或设备分发进行真机验证。

## 验证顺序

1. 先看 Simulator 构建包和 UI 测试截图，验证页面能启动。
2. 当前使用 `v1.2.11` / build `14` 的 `RedFruitTracker-unsigned-device-v1.2.11-build14.ipa`；历史版本 IPA 继续保留在 `artifacts` 目录。
3. 在真实 iPhone 上验证作品添加、季集记录、进度、评分点评、分享扩展、红果跳转和本地数据保存。
