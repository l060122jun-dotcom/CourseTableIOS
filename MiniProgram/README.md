# 课程表微信小程序骨架

这是不依赖 npm 的原生微信小程序目录，可直接用微信开发者工具导入 `MiniProgram/`。当前包含周课表、10 节课时间、不规则时间课程、新建/编辑课程、图片选择、OCR adapter 占位、设置与 storage 持久化。

## 导入与配置

1. 在微信开发者工具中选择“导入项目”，目录选择本目录。
2. 复制 `project.config.example.json` 为 `project.config.json`，在开发者工具中填写真实 AppID；`project.config.json` 已被 `.gitignore` 忽略。
3. 复制 `config.example.js` 为 `config.local.js`，填写云环境 ID、OCR 云函数名和订阅消息模板 ID；本地配置已被 `.gitignore` 忽略。

### 必需配置

- **AppID**：开发管理 → 开发设置 → AppID。没有 AppID 只能用测试号预览。
- **OCR**：推荐开通云开发，创建 `courseTableOCR` 云函数，在 `utils/ocr-adapter.js` 中调用 `wx.cloud.callFunction`；若使用自有 HTTPS OCR 服务，再配置“服务器域名 → request 合法域名”。
- **图片存储**：当前只把临时图片交给 OCR；若要长期保存原图，需要另外配置云存储和 `uploadFile` 合法域名。
- **提醒**：在“功能 → 订阅消息”创建课程提醒模板，把模板 ID 写入 `config.local.js`，并在用户操作时调用 `wx.requestSubscribeMessage`。小程序不能直接写入 Apple 日历。
- **代码上传**：开发者工具登录有权限的微信号；如后台要求，在“开发设置”生成代码上传密钥并维护 IP 白名单。密钥不能提交 GitHub。

### 暂时不需要配置

扫码普通链接、数据周期性更新、数据预拉取、安全键盘证书、消息推送、API 安全密钥和业务域名，目前都不是本课程表 MVP 的必需项；只有启用对应能力时再配置。

### 安全边界

AppSecret、OCR 服务密钥、云函数密钥、代码上传密钥、负责人身份证/手机号/邮箱只放在微信后台或云函数环境变量，不要写入小程序前端和公开 GitHub。

## 测试

- 开发者工具编译后检查“课表”页：应看到 10 行节次和不规则课程卡。
- 点击“新建课程”，分别测试“按节次”和“自定义时间”，保存后返回课表；数据写入 `course-table-document-v1`。
- 图片导入页使用 `wx.chooseMedia`，未配置 OCR 时应看到“尚未配置 OCR 服务”提示。
- 设置页检查提醒适配占位，不会伪称已经写入系统日历。

本目录不包含图标资源，使用文字 tabBar，避免导入后出现缺失图片资源。
