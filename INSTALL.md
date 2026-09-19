# 安装与当前验证方式

## 当前可交付包

GitHub Actions 当前生成的是 `RedFruitTracker-simulator.app.zip`。它是 iOS Simulator 构建包，只能在 macOS 的 iOS Simulator 中安装，不能直接安装到真实 iPhone。

## 真实 iPhone 安装包

真实 iPhone 需要签名后的 `.ipa`。后续需要：

1. Apple Developer 账号和可用的 App ID。
2. iOS Development 或 Ad Hoc 证书。
3. 与证书匹配的 provisioning profile。
4. 将签名材料以 GitHub Actions Secrets 的形式配置到私有仓库。

证书私钥、Apple ID 密码、验证码和 provisioning profile 不应发到对话中。配置完成后，CI 才能生成可安装的 IPA，再通过 TestFlight 或设备分发进行真机验证。

## 验证顺序

1. 先看 Simulator 构建包和 UI 测试截图，验证页面能启动。
2. 再配置签名并生成 IPA。
3. 在真实 iPhone 上验证分享扩展、红果跳转和本地数据保存。
