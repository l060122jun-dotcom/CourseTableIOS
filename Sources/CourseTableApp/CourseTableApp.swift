import Foundation
import SwiftUI
import CourseTableCore
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@main
struct CourseTableApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}

private enum PreviewScreen: String {
    case `import` = "import"
    case newCourse = "new-course"
    case detail
    case settings

    init?(arguments: [String]) {
        guard let value = arguments.first(where: { $0.hasPrefix("--screen=") })?.split(separator: "=", maxSplits: 1).last else { return nil }
        self.init(rawValue: String(value))
    }

    var tab: Int {
        switch self { case .import: return 1; case .settings: return 2; case .newCourse, .detail: return 0 }
    }
}

private struct RootView: View {
    @State private var document: ScheduleDocument
    @State private var showingNewCourse = false
    @State private var showingDetailPreview = false
    @State private var selectedTab = 0
    @State private var storageLocked: Bool
    @State private var storageMessage: String?

    init() {
        let previewScreen = PreviewScreen(arguments: ProcessInfo.processInfo.arguments)
        if ProcessInfo.processInfo.arguments.contains("--demo-data") || previewScreen != nil {
            _document = State(initialValue: .preview)
            _selectedTab = State(initialValue: previewScreen?.tab ?? 0)
            _showingNewCourse = State(initialValue: previewScreen == .newCourse)
            _showingDetailPreview = State(initialValue: previewScreen == .detail)
            _storageLocked = State(initialValue: false)
            return
        }
        switch ScheduleStore.load() {
        case .success(let stored):
            _document = State(initialValue: stored ?? .empty())
            _storageLocked = State(initialValue: false)
        case .failure(let error):
            _document = State(initialValue: .empty())
            _storageLocked = State(initialValue: true)
            _storageMessage = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScheduleView(document: document, addAction: beginAddingCourse)
                    .navigationTitle("课程表")
            }
                .tabItem { Label("课表", systemImage: "calendar") }.tag(0)
            NavigationStack {
                ImportView(table: document.table, periods: document.periods, onSave: append)
                    .navigationTitle("图片导入")
            }
                .tabItem { Label("导入", systemImage: "viewfinder") }.tag(1)
            NavigationStack { SettingsView(document: document).navigationTitle("设置") }
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .sheet(isPresented: $showingNewCourse) {
            CourseEditorSheet(table: document.table, periods: document.periods, onSave: append)
        }
        .sheet(isPresented: $showingDetailPreview) {
            if let item = document.courses.first {
                CourseDetailView(item: item, table: document.table, periods: document.periods)
            }
        }
        .onChange(of: document) { _, updated in
            guard !storageLocked, !ProcessInfo.processInfo.arguments.contains("--demo-data") else { return }
            do { try ScheduleStore.save(updated) }
            catch { storageMessage = "保存课程失败：\(error.localizedDescription)" }
        }
        .alert("课程数据需要处理", isPresented: Binding(
            get: { storageMessage != nil },
            set: { if !$0 { storageMessage = nil } }
        )) {
            if storageLocked {
                Button("备份原文件并新建", role: .destructive, action: recoverStorage)
            }
            Button("暂不处理", role: .cancel) {}
        } message: {
            Text(storageMessage ?? "未知存储错误")
        }
    }

    private func beginAddingCourse() {
        guard !storageLocked else {
            storageMessage = "检测到无法读取的原课程数据。请先备份原文件再新建，避免静默覆盖。"
            return
        }
        showingNewCourse = true
    }

    private func append(course: Course, rule: MeetingRule) {
        guard !storageLocked else {
            storageMessage = "当前存储已锁定，未写入新课程。"
            return
        }
        document.courses.append(ScheduledCourse(course: course, rule: rule))
    }

    private func recoverStorage() {
        do {
            _ = try ScheduleStore.backUpUnreadableFile()
            storageLocked = false
            document = .empty()
            try ScheduleStore.save(document)
            storageMessage = nil
        } catch {
            storageMessage = "无法备份原数据：\(error.localizedDescription)"
        }
    }
}

private struct ScheduleView: View {
    let document: ScheduleDocument
    let addAction: () -> Void
    @State private var selectedCourse: ScheduledCourse?
    private let days = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.table.name).font(.title2.bold())
                        Text(weekSummary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("新建课程", action: addAction).buttonStyle(.borderedProminent)
                }
                HStack(spacing: 3) {
                    Text("").frame(width: 36)
                    ForEach(days, id: \.self) { day in Text("周\(day)").font(.caption.bold()).frame(maxWidth: .infinity) }
                }.foregroundStyle(.secondary)
                ForEach(document.periods) { period in
                    HStack(spacing: 3) {
                        VStack(spacing: 1) { Text("\(period.index)").font(.caption.bold()); Text(time(period.startMinuteOfDay)).font(.system(size: 8)).foregroundStyle(.secondary) }.frame(width: 36)
                        ForEach(1...7, id: \.self) { weekday in
                            let match = document.courses.first { $0.rule.weekday == weekday && $0.rule.timingMode == .period && $0.rule.startPeriod == period.index }
                            CourseCell(course: match?.course) { selectedCourse = match }
                        }
                    }
                }
                let customCourses = document.courses.filter { $0.rule.timingMode == .custom }
                if !customCourses.isEmpty {
                    Text("不规则时间课程").font(.headline).padding(.top, 4)
                    ForEach(customCourses) { item in
                        Button { selectedCourse = item } label: { HStack(spacing: 12) {
                            Image(systemName: "clock.badge.checkmark").foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.course.name).font(.subheadline.bold())
                                Text("周\(days[item.rule.weekday - 1]) · \(time(item.rule.customStartMinute))–\(time(item.rule.customEndMinute))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.course.location ?? "").font(.caption).foregroundStyle(.secondary)
                        }.padding(12).background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
                            .buttonStyle(.plain)
                    }
                }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: $selectedCourse) { item in
            CourseDetailView(item: item, table: document.table, periods: document.periods)
        }
    }

    private var weekSummary: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: document.table.semesterStartDate)
        let daysSinceStart = calendar.dateComponents([.day], from: start, to: .now).day ?? 0
        let rawWeek = daysSinceStart / 7 + 1
        let currentWeek = min(max(rawWeek, 1), document.table.totalWeeks)
        return "第 \(currentWeek) 周 · 共 \(document.table.totalWeeks) 周"
    }

    private func time(_ minutes: Int?) -> String {
        guard let minutes else { return "--:--" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

private struct CourseCell: View {
    let course: Course?
    let action: () -> Void
    var body: some View {
        Button(action: action) { RoundedRectangle(cornerRadius: 6)
            .fill(course == nil ? Color.secondary.opacity(0.06) : Color.blue.opacity(0.18))
            .overlay(alignment: .topLeading) {
                if let course { Text(course.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.blue).padding(5).lineLimit(3) }
            }.frame(maxWidth: .infinity, minHeight: 56) }
            .buttonStyle(.plain)
            .disabled(course == nil)
    }
}

private struct CourseDraftPrefill {
    var name = ""
    var weekday = 1
    var customStartMinute: Int?
    var customEndMinute: Int?
    var sourceText: String?

    static func from(_ draft: OCRImportDraft) -> CourseDraftPrefill {
        let lines = draft.rawRecognizedText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let weekdayTokens = [("周一", 1), ("星期一", 1), ("周二", 2), ("星期二", 2), ("周三", 3), ("星期三", 3), ("周四", 4), ("星期四", 4), ("周五", 5), ("星期五", 5), ("周六", 6), ("星期六", 6), ("周日", 7), ("周天", 7), ("星期日", 7)]
        let weekday = weekdayTokens.first(where: { draft.rawRecognizedText.contains($0.0) })?.1 ?? 1
        let name = lines.first(where: { line in
            line.count <= 40 && !weekdayTokens.contains(where: { line.contains($0.0) }) && !line.contains(":") && !line.contains("：")
        }) ?? lines.first ?? ""
        return CourseDraftPrefill(name: name, weekday: weekday, sourceText: draft.rawRecognizedText)
    }
}

private struct CourseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var weekday = 1
    @State private var mode: TimingMode = .period
    @State private var startPeriod = 1
    @State private var endPeriod = 2
    @State private var startWeek = 1
    @State private var endWeek = 18
    @State private var reminderMinutes = 30
    @State private var customStart = Calendar.current.date(from: DateComponents(hour: 16, minute: 40)) ?? Date()
    @State private var customEnd = Calendar.current.date(from: DateComponents(hour: 18, minute: 10)) ?? Date()
    @State private var validationMessage: String?
    let table: CourseTable
    let periods: [Period]
    let sourceText: String?
    let onSave: (Course, MeetingRule) -> Void
    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    init(table: CourseTable, periods: [Period], prefill: CourseDraftPrefill? = nil, onSave: @escaping (Course, MeetingRule) -> Void) {
        self.table = table
        self.periods = periods
        self.sourceText = prefill?.sourceText
        self.onSave = onSave
        _name = State(initialValue: prefill?.name ?? "")
        _weekday = State(initialValue: prefill?.weekday ?? 1)
        _endWeek = State(initialValue: table.totalWeeks)
        _reminderMinutes = State(initialValue: table.defaultReminderMinutes ?? -1)
        if let start = prefill?.customStartMinute, let end = prefill?.customEndMinute {
            _mode = State(initialValue: .custom)
            _customStart = State(initialValue: Self.date(minutes: start))
            _customEnd = State(initialValue: Self.date(minutes: end))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称（必填）", text: $name)
                    TextField("教师", text: $teacher)
                    TextField("教室", text: $location)
                    TextField("备注", text: $notes, axis: .vertical)
                }
                if let sourceText {
                    Section("OCR 原文") {
                        Text(sourceText).font(.footnote).foregroundStyle(.secondary).lineLimit(8)
                    }
                }
                Section("上课日") {
                    Picker("星期", selection: $weekday) { ForEach(1...7, id: \.self) { Text(dayNames[$0 - 1]).tag($0) } }
                }
                Section("上课时间") {
                    Picker("时间方式", selection: $mode) {
                        Text("按节次").tag(TimingMode.period)
                        Text("自定义时间").tag(TimingMode.custom)
                    }.pickerStyle(.segmented)
                    if mode == .period {
                        Picker("开始节次", selection: $startPeriod) { ForEach(periods.map(\.index), id: \.self) { Text("第 \($0) 节").tag($0) } }
                        Picker("结束节次", selection: $endPeriod) { ForEach(periods.map(\.index), id: \.self) { Text("第 \($0) 节").tag($0) } }
                    } else {
                        DatePicker("开始", selection: $customStart, displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: $customEnd, displayedComponents: .hourAndMinute)
                    }
                }
                Section("重复") {
                    Picker("开始周", selection: $startWeek) { ForEach(1...table.totalWeeks, id: \.self) { Text("第 \($0) 周").tag($0) } }
                    Picker("结束周", selection: $endWeek) { ForEach(1...table.totalWeeks, id: \.self) { Text("第 \($0) 周").tag($0) } }
                    Picker("提醒", selection: $reminderMinutes) {
                        Text("不提醒").tag(-1)
                        Text("上课时").tag(0)
                        Text("提前 10 分钟").tag(10)
                        Text("提前 30 分钟").tag(30)
                        Text("提前 1 小时").tag(60)
                    }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("新建课程")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        validationMessage = nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { validationMessage = "请填写课程名称。"; return }
        guard startWeek <= endWeek else { validationMessage = "开始周不能晚于结束周。"; return }
        let course = Course(
            courseTableID: table.id,
            name: cleanName,
            teacher: teacher.nilIfBlank,
            location: location.nilIfBlank,
            notes: notes.nilIfBlank
        )
        let rule: MeetingRule
        if mode == .period {
            rule = MeetingRule(courseID: course.id, weekday: weekday, weekSet: Set(startWeek...endWeek), startPeriod: startPeriod, endPeriod: endPeriod, reminderMinutes: reminderMinutes < 0 ? nil : reminderMinutes)
        } else {
            let start = minutes(customStart), end = minutes(customEnd)
            rule = MeetingRule(courseID: course.id, weekday: weekday, weekSet: Set(startWeek...endWeek), customStartMinute: start, customEndMinute: end, reminderMinutes: reminderMinutes < 0 ? nil : reminderMinutes)
        }
        do {
            try MeetingRuleValidator.validate(rule, in: table, periods: periods)
        } catch {
            validationMessage = error.localizedDescription
            return
        }
        onSave(course, rule)
        dismiss()
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now
    }
}

private struct ImportView: View {
    let table: CourseTable
    let periods: [Period]
    let onSave: (Course, MeetingRule) -> Void
    @State private var selectedItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var draft: OCRImportDraft?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showFileImporter = false
    @State private var showingReview = false
    var body: some View {
        List {
            PhotosPicker(selection: $selectedItem, matching: .images) { Label("从相册选择图片", systemImage: "photo") }
                .onChange(of: selectedItem) { _, item in scan(item) }
            Button { showFileImporter = true } label: { Label("选择本地图片", systemImage: "doc.badge.plus") }
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                    switch result { case .success(let urls): importFile(urls[0]); case .failure(let error): errorMessage = "选择文件失败：\(error.localizedDescription)" }
                }
            if isScanning { ProgressView("正在识别课程与时间…") }
            if let draft {
                Section("识别草稿（请确认）") {
                    Text(draft.rawRecognizedText.isEmpty ? "未识别到文字" : draft.rawRecognizedText).font(.footnote)
                    Button("编辑并保存为课程") { showingReview = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.rawRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("识别结果不会自动写入课程表或日历，必须先检查并确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let confirmationMessage { Text(confirmationMessage).foregroundStyle(.green).font(.footnote) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            Text("OCR 结果会先进入可编辑草稿，确认后才创建课程和日历提醒。").font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingReview) {
            if let draft {
                CourseEditorSheet(table: table, periods: periods, prefill: .from(draft)) { course, rule in
                    onSave(course, rule)
                    confirmationMessage = "“\(course.name)”已保存到课程表；尚未自动写入 Apple 日历。"
                    self.draft = nil
                }
            }
        }
    }
    private func scan(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isScanning = true; errorMessage = nil
        Task {
            do { let data = try await item.loadTransferable(type: Data.self); guard let data, let image = UIImage(data: data) else { throw OCRServiceError.invalidImage }; draft = try await OCRService().recognize(image: image) }
            catch { errorMessage = "识别失败：\(error.localizedDescription)" }
            isScanning = false
        }
    }
    private func importFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { errorMessage = "无法访问所选文件"; return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                errorMessage = "无法读取图片，请选择 JPG、PNG 或 HEIC 图片。"
                return
            }
            scanImage(image)
        } catch { errorMessage = "读取文件失败：\(error.localizedDescription)" }
    }
    private func scanImage(_ image: UIImage) {
        isScanning = true; errorMessage = nil
        Task {
            do {
                draft = try await OCRService().recognize(image: image)
            } catch {
                errorMessage = "识别失败：\(error.localizedDescription)"
            }
            isScanning = false
        }
    }
}

private struct CourseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var calendarService = CalendarService()
    @State private var isExporting = false
    @State private var resultMessage: String?
    let item: ScheduledCourse
    let table: CourseTable
    let periods: [Period]

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    LabeledContent("课程", value: item.course.name)
                    if let teacher = item.course.teacher { LabeledContent("教师", value: teacher) }
                    if let location = item.course.location { LabeledContent("教室", value: location) }
                    if let notes = item.course.notes { LabeledContent("备注", value: notes) }
                }
                Section("上课安排") {
                    LabeledContent("星期", value: weekdayName)
                    LabeledContent("时间", value: timeSummary)
                    LabeledContent("周次", value: weekSummary)
                    LabeledContent("提醒", value: reminderSummary)
                }
                Section("Apple 日历") {
                    Button {
                        exportToCalendar()
                    } label: {
                        if isExporting {
                            HStack { ProgressView(); Text("正在导出…") }
                        } else {
                            Label("导出这门课程", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(isExporting)
                    Text("会为所选周次逐次创建日程。再次导出可能产生重复日程。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let resultMessage {
                        Text(resultMessage)
                            .font(.footnote)
                            .foregroundStyle(resultMessage.hasPrefix("已") ? .green : .red)
                    }
                }
            }
            .navigationTitle("课程详情")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var weekdayName: String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard names.indices.contains(item.rule.weekday - 1) else { return "未知" }
        return names[item.rule.weekday - 1]
    }

    private var timeSummary: String {
        switch item.rule.timingMode {
        case .period:
            return "第 \(item.rule.startPeriod ?? 0)–\(item.rule.endPeriod ?? 0) 节"
        case .custom:
            return "\(time(item.rule.customStartMinute))–\(time(item.rule.customEndMinute))"
        }
    }

    private var weekSummary: String {
        let weeks = item.rule.weekSet.sorted()
        guard let first = weeks.first, let last = weeks.last else { return "未设置" }
        return first == last ? "第 \(first) 周" : "第 \(first)–\(last) 周（共 \(weeks.count) 周）"
    }

    private var reminderSummary: String {
        guard let minutes = item.rule.reminderMinutes ?? table.defaultReminderMinutes else { return "不提醒" }
        return minutes == 0 ? "上课时" : "提前 \(minutes) 分钟"
    }

    private func time(_ minutes: Int?) -> String {
        guard let minutes else { return "--:--" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func exportToCalendar() {
        isExporting = true
        resultMessage = nil
        Task {
            do {
                let count = try await calendarService.exportCourse(
                    course: item.course,
                    rule: item.rule,
                    table: table,
                    periods: periods
                )
                resultMessage = "已创建 \(count) 个 Apple 日历日程。"
            } catch {
                resultMessage = "导出失败：\(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}

private struct SettingsView: View {
    let document: ScheduleDocument
    var body: some View {
        List {
            Section("当前课程表") {
                LabeledContent("名称", value: document.table.name)
                LabeledContent("课程数", value: "\(document.courses.count)")
                LabeledContent("总周数", value: "\(document.table.totalWeeks)")
            }
            Section("课程时间") {
                Label("常规课程：按节次", systemImage: "list.number")
                Label("不规则课程：单独填写开始和结束时间", systemImage: "clock")
            }
            Section("日历") { Label("导入 Apple 日历与课程提醒", systemImage: "bell") }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
