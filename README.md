# 流云课表 iOS

iOS 原生课程表应用，界面采用 **液态玻璃（Liquid Glass）** 设计语言、**水滴式指示块** 与 **多层半透明卡片** 结构。功能与《流云课表》Android / 小程序版本保持一致，数据只保存在本机。

## 功能

- **多课程表**：创建、切换、删除课程表，每张表独立维护学期信息。
- **周课表**：一周 7 列（可开关周末）、左右切换周次、按开学日期自动推算当前周、一键回到本周。
- **节次自定义**：节数（1–52 周，1–N 节课）与每节课时间均可编辑，支持恢复默认。
- **课程增删改**：课程名、教师、教室、备注、颜色；一门课支持多个上课时段。
- **时间模式**：按节次，或不规则时间（直接填写开始/结束时间）。
- **周次表达**：连续周、单周、双周或任意离散周集合。
- **提醒**：每门课可单独设置提前提醒，或跟随课程表默认值（通知 / 闹钟）。
- **照片导入**：Vision 本机 OCR，识别结果先进入草稿，人工确认后才写入，绝不上传原图。
- **JSON 备份 / 迁移**：导出与导入全部课程表。
- **ICS 分享**：整学期或单门课程导出 `.ics`。
- **Apple 日历**：幂等写入系统日历，重复导入只新增/更新变化项，删除课程时可只清理本应用创建的事件。

## 界面设计

- **液态玻璃**：iOS 26 使用原生 `glassEffect`；iOS 17–25 自动回退为 `ultraThinMaterial` + 高光渐变 + 描边。
- **水滴式指示块**：周次选择与底部导航的选中态通过 `matchedGeometryEffect` 在选项间滑动、拉伸并回弹成水滴。
- **多层结构**：氛围背景（流动色块）→ 玻璃卡片 → 内容层，浮动玻璃导航栏悬浮其上。

设计预览见 [`Docs/ui-preview.html`](Docs/ui-preview.html)。

## 架构

```
CourseTableApp（SwiftUI）
  ├─ GlassKit          液态玻璃设计系统（玻璃修饰符 / 水滴指示块 / 玻璃卡片）
  ├─ RootView          应用外壳 + 浮动玻璃标签栏
  ├─ ScheduleScreen    周课表
  ├─ CourseEditorSheet 课程编辑（多时段）
  ├─ CourseDetailSheet 课程详情 + 日历导出
  ├─ TableManagerSheet 多课程表管理
  ├─ ImportScreen      OCR 导入 + JSON 备份
  ├─ SettingsScreen    课程表设置 / 节次 / 日历
  ├─ CalendarService   EventKit 幂等同步
  ├─ OCRService        Vision 本机识别
  └─ CourseTableCore   领域模型、校验、ICS、传输格式（不依赖 UI 框架）
```

`CourseTableCore` 不导入 SwiftUI / EventKit / Vision，保持可独立测试。

## 构建未签名 IPA

由 GitHub Actions 在 macOS 26 + Xcode 26（iOS 26 SDK）上构建：

- [`ios-unsigned-ipa.yml`](.github/workflows/ios-unsigned-ipa.yml)：编译 `generic/platform=iOS` 的 Release 包，手工组装 `Payload/` 并打包为 `CourseTable-unsigned.ipa`，同时上传模拟器截图。
- [`ios-ci.yml`](.github/workflows/ios-ci.yml)：`swift test` 领域测试 + 模拟器构建 + 资源校验。

产物：`CourseTable-unsigned.ipa`（未签名，可自行签名后安装）。

## 本地构建（需 macOS）

```bash
brew install xcodegen
xcodegen generate
swift test
xcodebuild build -project CourseTable.xcodeproj -scheme CourseTable \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```
