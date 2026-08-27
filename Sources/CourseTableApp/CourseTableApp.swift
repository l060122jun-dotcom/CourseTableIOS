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

private struct DemoCourse: Identifiable, Codable, Equatable {
    let id: UUID
    var course: Course
    var rule: MeetingRule
}

private struct RootView: View {
    @State private var courses: [DemoCourse] = PersistenceStore.load() ?? DemoCourse.samples
    @State private var showingNewCourse = false

    var body: some View {
        TabView {
            NavigationStack { ScheduleView(courses: courses, addAction: { showingNewCourse = true }).navigationTitle("课程表") }
                .tabItem { Label("课表", systemImage: "calendar") }
            NavigationStack { ImportView().navigationTitle("图片导入") }
                .tabItem { Label("导入", systemImage: "viewfinder") }
            NavigationStack { SettingsView().navigationTitle("设置") }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showingNewCourse) {
            NewCourseSheet { course, rule in
                courses.append(DemoCourse(id: course.id, course: course, rule: rule))
            }
        }
        .onChange(of: courses) { _, updated in PersistenceStore.save(updated) }
    }
}

private enum PersistenceStore {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CourseTable", isDirectory: true)
            .appendingPathComponent("courses.json")
    }
    static func load() -> [DemoCourse]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([DemoCourse].self, from: data)
    }
    static func save(_ courses: [DemoCourse]) {
        do { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(courses).write(to: url, options: .atomic) }
        catch { print("Unable to save courses: \(error)") }
    }
}

private struct ScheduleView: View {
    let courses: [DemoCourse]
    let addAction: () -> Void
    private let periods = [(1, "08:00"), (2, "10:00"), (3, "13:30"), (4, "15:30"), (5, "18:30")]
    private let days = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("大三上").font(.title2.bold())
                        Text("第 8 周 · 2026年10月19日—25日").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("新建课程", action: addAction).buttonStyle(.borderedProminent)
                }
                HStack(spacing: 3) {
                    Text("").frame(width: 36)
                    ForEach(days, id: \.self) { day in Text("周\(day)").font(.caption.bold()).frame(maxWidth: .infinity) }
                }.foregroundStyle(.secondary)
                ForEach(periods, id: \.0) { period in
                    HStack(spacing: 3) {
                        VStack(spacing: 1) { Text("\(period.0)").font(.caption.bold()); Text(period.1).font(.system(size: 8)).foregroundStyle(.secondary) }.frame(width: 36)
                        ForEach(1...7, id: \.self) { weekday in
                            let match = courses.first { $0.rule.weekday == weekday && $0.rule.timingMode == .period && $0.rule.startPeriod == period.0 }
                            CourseCell(course: match?.course)
                        }
                    }
                }
                let customCourses = courses.filter { $0.rule.timingMode == .custom }
                if !customCourses.isEmpty {
                    Text("不规则时间课程").font(.headline).padding(.top, 4)
                    ForEach(customCourses) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "clock.badge.checkmark").foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.course.name).font(.subheadline.bold())
                                Text("周\(days[item.rule.weekday - 1]) · \(time(item.rule.customStartMinute))–\(time(item.rule.customEndMinute))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.course.location ?? "").font(.caption).foregroundStyle(.secondary)
                        }.padding(12).background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
    }

    private func time(_ minutes: Int?) -> String {
        guard let minutes else { return "--:--" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

private struct CourseCell: View {
    let course: Course?
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(course == nil ? Color.secondary.opacity(0.06) : Color.blue.opacity(0.18))
            .overlay(alignment: .topLeading) {
                if let course { Text(course.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.blue).padding(5).lineLimit(3) }
            }.frame(maxWidth: .infinity, minHeight: 64)
    }
}

private struct NewCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var weekday = 1
    @State private var mode: TimingMode = .period
    @State private var startPeriod = 1
    @State private var endPeriod = 2
    @State private var customStart = Calendar.current.date(from: DateComponents(hour: 16, minute: 40)) ?? Date()
    @State private var customEnd = Calendar.current.date(from: DateComponents(hour: 18, minute: 10)) ?? Date()
    let onSave: (Course, MeetingRule) -> Void
    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称（必填）", text: $name)
                    TextField("教师", text: $teacher)
                    TextField("教室", text: $location)
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
                        Picker("开始节次", selection: $startPeriod) { ForEach(1...12, id: \.self) { Text("第 \($0) 节").tag($0) } }
                        Picker("结束节次", selection: $endPeriod) { ForEach(1...12, id: \.self) { Text("第 \($0) 节").tag($0) } }
                    } else {
                        DatePicker("开始", selection: $customStart, displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: $customEnd, displayedComponents: .hourAndMinute)
                    }
                }
                Section("重复") {
                    Text("第 1–18 周").foregroundStyle(.secondary)
                    Text("保存后可继续接入 OCR 草稿和 Apple 日历提醒").font(.footnote).foregroundStyle(.secondary)
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
        let tableID = UUID()
        let course = Course(courseTableID: tableID, name: name, teacher: teacher.isEmpty ? nil : teacher, location: location.isEmpty ? nil : location)
        let rule: MeetingRule
        if mode == .period {
            rule = MeetingRule(courseID: course.id, weekday: weekday, weekSet: Set(1...18), startPeriod: min(startPeriod, endPeriod), endPeriod: max(startPeriod, endPeriod))
        } else {
            let start = minutes(customStart), end = minutes(customEnd)
            rule = MeetingRule(courseID: course.id, weekday: weekday, weekSet: Set(1...18), customStartMinute: min(start, end - 1), customEndMinute: max(end, start + 1))
        }
        onSave(course, rule)
        dismiss()
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

private struct ImportView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var draft: OCRImportDraft?
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    var body: some View {
        List {
            PhotosPicker(selection: $selectedItem, matching: .images) { Label("从相册选择图片", systemImage: "photo") }
                .onChange(of: selectedItem) { _, item in scan(item) }
            Button { showFileImporter = true } label: { Label("选择本地图片或表格文件", systemImage: "doc.badge.plus") }
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .commaSeparatedText, .tabSeparatedText, .plainText, .data], allowsMultipleSelection: false) { result in
                    switch result { case .success(let urls): importFile(urls[0]); case .failure(let error): errorMessage = "选择文件失败：\(error.localizedDescription)" }
                }
            Label("拍照导入课程表", systemImage: "camera").foregroundStyle(.secondary)
            if isScanning { ProgressView("正在识别课程与时间…") }
            if let draft {
                Section("识别草稿（请确认）") {
                    Text(draft.rawRecognizedText.isEmpty ? "未识别到文字" : draft.rawRecognizedText).font(.footnote)
                    Text("识别结果不会自动写入日历，确认后再创建课程。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            Text("OCR 结果会先进入可编辑草稿，确认后才创建课程和日历提醒。").font(.footnote).foregroundStyle(.secondary)
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
            if let image = UIImage(data: data) { scanImage(image); return }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            guard !text.isEmpty else { errorMessage = "表格文件暂未识别到可读文本，请导出为 CSV/TSV 后重试。"; return }
            draft = OCRImportDraft(sourceImageHash: "file:\(url.lastPathComponent)", rawRecognizedText: text, warnings: ["表格已读取为导入草稿，请确认课程、星期、周次和时间后保存。"])
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

private struct SettingsView: View {
    var body: some View {
        List {
            Section("课程时间") {
                Label("常规课程：按节次", systemImage: "list.number")
                Label("不规则课程：单独填写开始和结束时间", systemImage: "clock")
            }
            Section("日历") { Label("导入 Apple 日历与课程提醒", systemImage: "bell") }
        }
    }
}

private extension DemoCourse {
    static let samples: [DemoCourse] = {
        let tableID = UUID()
        func item(_ name: String, _ weekday: Int, _ period: Int) -> DemoCourse {
            let c = Course(courseTableID: tableID, name: name)
            return DemoCourse(id: c.id, course: c, rule: MeetingRule(courseID: c.id, weekday: weekday, weekSet: Set(1...18), startPeriod: period, endPeriod: period))
        }
        let custom = Course(courseTableID: tableID, name: "实验（不规则）", location: "实验楼 B203", colorHex: "#E84A8A")
        return [item("高等数学", 1, 1), item("英语", 3, 2), item("数据结构", 2, 3), item("体育", 5, 4), DemoCourse(id: custom.id, course: custom, rule: MeetingRule(courseID: custom.id, weekday: 4, weekSet: Set(1...18), customStartMinute: 16 * 60 + 40, customEndMinute: 18 * 60 + 10))]
    }()
}
