# App Store 发布清单

## 已在公开仓库完成

- `macos-15` + Xcode 16.4 CI 构建
- Swift 领域测试、iOS 模拟器构建和无签名设备归档
- 包内隐私清单校验
- AppIcon 1024×1024 资源
- 模拟器启动截图验证
- 课程表图片导入入口

## 发布前必须由账号持有人配置

公开仓库不能保存任何证书、私钥或 App Store Connect 密钥。请在 Apple Developer 和 GitHub Environments 中配置：

1. Apple Developer Team ID
2. 已注册的正式 Bundle ID（替换 `com.codex.coursetable.app`）
3. Apple Distribution 证书与 App Store provisioning profile
4. App Store Connect API Key（Key ID、Issuer ID、私钥）或受保护的发布机密
5. App 名称、隐私政策 URL、支持 URL、年龄分级和商店截图

配置完成后，使用受保护环境执行 Release archive、`-exportArchive`、签名校验和 TestFlight 上传。当前 CI 的 unsigned archive 只用于验证源码能编译，不能直接提交 App Store。

## 真机验收

- 相册选择图片、图片方向和 OCR 低置信度确认
- 新建、编辑、删除普通课程与不规则时间课程
- 日历权限允许/拒绝、重复导出和提醒
- 重启恢复数据、时区/DST、升级迁移
- iPhone 多尺寸和深色模式截图
