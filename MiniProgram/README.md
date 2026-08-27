# 课程表微信小程序骨架

这是不依赖 npm 的原生微信小程序目录，可直接用微信开发者工具导入 `MiniProgram/`。当前包含周课表、10 节课时间、不规则时间课程、新建/编辑课程、图片 OCR 导入、单课程/整学期 ICS 日历导出、设置与 storage 持久化。

## 导入与配置

1. 在微信开发者工具中选择“导入项目”，目录选择本目录。
2. 复制 `project.config.example.json` 为 `project.config.json`，在开发者工具中填写真实 AppID；`project.config.json` 已被 `.gitignore` 忽略。
3. 复制 `config.example.js` 为 `config.local.js`，填写云环境 ID、OCR 云函数名和订阅消息模板 ID；本地配置已被 `.gitignore` 忽略。

### 必需配置

- **AppID**：开发管理 → 开发设置 → AppID。没有 AppID 只能用测试号预览。
- **OCR**：推荐开通云开发，创建 `courseTableOCR` 云函数，在 `utils/ocr-adapter.js` 中调用 `wx.cloud.callFunction`；若使用自有 HTTPS OCR 服务，再配置“服务器域名 → request 合法域名”。
- **图片存储**：当前只把临时图片交给 OCR；若要长期保存原图，需要另外配置云存储和 `uploadFile` 合法域名。
- **提醒**：在“功能 → 订阅消息”创建课程提醒模板，把模板 ID 写入 `config.local.js`，并在用户操作时调用 `wx.requestSubscribeMessage`。小程序不能静默写入系统日历，但可生成标准 ICS 文件供用户确认导入。
- **代码上传**：开发者工具登录有权限的微信号；如后台要求，在“开发设置”生成代码上传密钥并维护 IP 白名单。密钥不能提交 GitHub。

### 从零配置的点击顺序

1. 登录 `mp.weixin.qq.com`，进入目标小程序，打开“开发管理 → 开发设置”，复制 AppID。
2. 在电脑上复制 `project.config.example.json` 为 `project.config.json`，把 `appid` 替换为真实 AppID；用微信开发者工具重新导入 `MiniProgram/`。
3. 点击开发者工具顶部“云开发”，创建环境并复制环境 ID。选择与小程序主体一致的地域，创建后不要删除或频繁切换环境。
4. 使用仓库中的 `cloudfunctions/courseTableOCR` 云函数（名称必须和配置一致）。云函数输入是 `{ fileID }`，返回 `{ draft, meta }`；`meta.functionVersion` 用于确认实际运行的是不是最新部署。
5. 复制 `config.example.js` 为 `config.local.js`，填写：
   ```js
   module.exports = {
     ocr: { mode: 'cloud-function', envId: '你的云环境ID', functionName: 'courseTableOCR' },
     subscribeMessageTemplateIds: ['你的订阅消息模板ID']
   }
   ```
6. 右键 `cloudfunctions/courseTableOCR`，选择“上传并部署：云端安装依赖”。部署后先在开发者工具控制台调用健康检查：

   ```js
   wx.cloud.callFunction({ name: 'courseTableOCR', data: { action: 'health' } }).then(console.log)
   ```

   返回的 `health.functionVersion` 应为源码中的版本，且 `health.arkConfigured` 应为 `true`。默认会用当前 Chat Completions 的 `thinking: { type: 'disabled' }` 关闭推理；课程表 JSON 输出上限为 4096 token，并要求模型只返回紧凑单行 JSON，以兼顾完整课表和 30 秒同步调用边界，同时仍保留 2 MB 响应体硬限制和结构化截断恢复。若端点报“不支持 thinking 参数”，可在云函数环境变量中把 `ARK_THINKING_FIELD` 设为 `none`；只有旧端点文档明确要求时才设为 `thinking_type`。三个模式互斥，不会同时发送两个字段。`health.thinkingField` 和 `health.maxOutputTokens` 可确认实际配置，`health.endpointCapabilityHint` 会提示端点必须绑定支持图片输入的视觉/多模态模型。

   再打开“导入”页选择图片；客户端会先压缩并限制到 2 MB，云函数日志会依次出现 `download.start`、`download.end`、`image.ready`、`ark.request.start`、`ark.connection.ready`、`ark.response.headers` 和 `complete`。失败日志只包含阶段、耗时、大小和错误码，不包含 API Key。

   当前源码版本为 `2026.08.27-timeout-26s-v9`。该版本兼容 `courses/courseList/schedule` 容器，以及 `weekday/day/weekDay`、`startPeriod/section/start/end` 等常见字段，并把 `[1-16周]`、`第1-2节` 等网页课表文本规范为数字；还会清理 BOM/零宽字符、解析前后说明和代码围栏，并在模型 JSON 被截断时恢复 `courses` 数组中已经闭合的完整课程。确认页的 `parseDiagnostics.status` 会显示 `parsed/recovered/empty/invalid`，不会再把解析失败表现成静默空白。方舟无响应超时为 26 秒、方舟请求上限为 27 秒；端到端仍受约 30 秒平台边界限制，使用 29 秒硬预算，并从方舟可用时间中扣除图片下载耗时，因此不会把下载 5 秒和方舟 27 秒直接叠成 32 秒，也不能改成 60 秒。健康检查应返回 `arkTimeoutMs=26000`、`arkTotalTimeoutMs=27000`、`syncBudgetMs=29000`。如果健康检查仍返回旧版本，说明云函数没有重新部署，需再次右键该目录执行“上传并部署：云端安装依赖”。如果导入仍失败，按最后一个日志阶段判断：

   - `DOWNLOAD_TIMEOUT`：云存储下载或 fileID 权限问题；
   - `ARK_CONNECT_TIMEOUT`：云函数到火山方舟的 DNS/TLS/出网问题；
   - `ARK_RESPONSE_TIMEOUT` 或 `ARK_TOTAL_TIMEOUT`：接入点响应过慢，先用更小的图片测试，并确认该 `ep-` 接入点支持视觉图片输入；
   - `ARK_HTTP_ERROR`：请求已到达方舟，查看 `statusCode` 和 `arkLogId`，通常是接入点、请求格式或图片类型问题；
   - `complete` 但 `courseCount: 0`：模型已返回但没有结构化课程，检查原图清晰度和识别结果确认页。
7. 进入后台“功能 → 订阅消息”，申请课程提醒模板；将模板 ID 写入 `config.local.js`，再在用户点击提醒功能时请求订阅。模板消息发送必须由云函数/后端完成。
8. 如果 OCR 使用外部 HTTPS 服务，进入“开发管理 → 开发设置 → 服务器域名”，把 HTTPS 域名加入 `request` 合法域名；不要在小程序前端放 API Secret。
9. 发布前在开发者工具关闭“本地设置 → 不校验合法域名”，重新测试真机；然后上传体验版，配置体验成员，最后提交审核。

### ICS 系统日历导出

- 设置中的“第一周周一”是所有课程日期计算的基准；请先确认该日期和各节次时间。
- 课程编辑页可导出当前已保存课程，设置页可导出全部课程。每个明确周次会生成一个独立 `VEVENT`，因此不连续周次、单双周/隔周与自定义上课时间不会被错误扩展。
- 文件使用 UTC 时间并标记 `Asia/Shanghai`，包含课程名、地点、教师和课程自身的提前提醒分钟数；文本按 ICS 规则转义并进行 75 字节折行。
- 小程序通过 `wx.getFileSystemManager().writeFile` 生成 `.ics`，再尝试用 `wx.openDocument` 打开；部分微信或系统版本不支持直接预览 ICS 时会尝试 `wx.saveFile` 并给出明确提示。生成文件不等于已经写入日历，用户仍需在 iOS/Android 系统界面确认导入。

### 云函数返回格式

最小返回格式：

```js
return { draft: { text: 'OCR 原文', warning: '请确认课程名和时间' } }
```

建议返回结构化候选：

```js
return { draft: {
  text: 'OCR 原文',
  warning: '',
  courses: [{ name: '高等数学', weekday: 1, startPeriod: 1, endPeriod: 2, startWeek: 1, endWeek: 18 }]
} }
```

### 暂时不需要配置

扫码普通链接、数据周期性更新、数据预拉取、安全键盘证书、消息推送、API 安全密钥和业务域名，目前都不是本课程表 MVP 的必需项；只有启用对应能力时再配置。

### 安全边界

AppSecret、OCR 服务密钥、云函数密钥、代码上传密钥、负责人身份证/手机号/邮箱只放在微信后台或云函数环境变量，不要写入小程序前端和公开 GitHub。

## 测试

- 开发者工具编译后检查“课表”页：应看到 10 行节次和不规则课程卡。
- 点击“新建课程”，分别测试“按节次”和“自定义时间”，保存后返回课表；数据写入 `course-table-document-v1`。
- 图片导入页使用 `wx.chooseMedia`，未配置 OCR 时应看到“尚未配置 OCR 服务”提示。
- 打开已保存课程，点击“添加到系统日历”，确认 ICS 中只包含该课程的实际周次；再在设置页测试“导出整学期日历”。导入必须由用户在系统界面确认，不会静默写入。
- 提醒授权：复制 `config.example.js` 为 `config.local.js`，填写微信后台申请的 `subscribeMessageTemplateIds`，再点击设置页“订阅课程提醒”。本骨架只负责请求用户授权，不包含服务端发送。

本地可运行 `node utils/ics.test.js` 检查 UTC 日期、单双周/隔周、转义、提醒和折行。目录不包含图标资源，使用文字 tabBar，避免导入后出现缺失图片资源。`config.local.js` 仅用于本地配置，不要提交。
