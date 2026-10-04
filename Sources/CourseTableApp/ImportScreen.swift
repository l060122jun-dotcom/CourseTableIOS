import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import CourseTableCore

/// Import hub: AI 识别（图片 / Excel）、课表文件（.lcs / JSON）导入导出。
/// Nothing is written to the timetable until the user confirms on the review page.
struct ImportScreen: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanningText = "正在识别课程与时间…"
    @State private var draft: OCRDraft?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showingReview = false
    @State private var showingFileImporter = false
    @State private var shareURL: URL?
    private var shareSelection: Binding<ShareItem?> {
        Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                aiImageCard
                excelCard
                if isScanning { scanningCard }
                if let draft { draftCard(draft) }
                transferCard
                if let confirmationMessage { messageCard(confirmationMessage, color: .green) }
                if let errorMessage { messageCard(errorMessage, color: .orange) }
            }
            .padding(16)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showingReview) {
            if let draft { ScheduleReviewSheet(draft: draft).environmentObject(model) }
        }
        .sheet(item: shareSelection) { ShareSheet(items: [$0.url]) }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: false
        ) { handleFileImport($0) }
        .onChange(of: showingFileImporter) { _, presented in
            if !presented { excelPickRequested = false }
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            scanImage(item)
        }
    }

    private var importTypes: [UTType] {
        // .lcs is JSON under the hood; accept json, xlsx and generic data so
        // Accept every spreadsheet-ish type the system knows plus generic data,
        // so xlsx / xls / csv / tsv / lcs / json are all selectable.
        var types: [UTType] = [.json, .spreadsheet, .commaSeparatedText, .tabSeparatedText, .plainText, .data]
        for ext in ["xlsx", "xls", "xlsm", "csv", "tsv", "lcs"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    // MARK: Cards

    private var header: some View {
        GlassCard(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导入课程").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("AI 识别图片 / Excel，或导入课表文件，确认后才会生效")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var aiImageCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(GlassPalette.accent.opacity(0.12)).frame(width: 74, height: 74)
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(GlassPalette.accent)
                }
                Text("AI 识别课表截图").font(.system(size: 16, weight: .semibold))
                Text("由云端 AI 解析课程、星期、节次与周次，返回结构化结果。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("从相册选择图片")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(GlassPalette.accent.gradient))
                }
                .disabled(isScanning)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var excelCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(red: 0.22, green: 0.62, blue: 0.36).opacity(0.14)).frame(width: 74, height: 74)
                    Image(systemName: "tablecells")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 0.36))
                }
                Text("AI 识别 Excel 课表").font(.system(size: 16, weight: .semibold))
                Text("支持 .xlsx，本机解析表格后再交 AI 结构化。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { pickExcel() } label: {
                    Text("选择 Excel 文件")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(red: 0.22, green: 0.62, blue: 0.36).gradient))
                }
                .disabled(isScanning)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var scanningCard: some View {
        GlassCard(cornerRadius: 20) {
            HStack(spacing: 12) {
                ProgressView().tint(GlassPalette.accent)
                Text(scanningText).font(.system(size: 14, weight: .medium))
                Spacer()
            }
        }
    }

    private func draftCard(_ draft: OCRDraft) -> some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("识别草稿", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlassPalette.accent)
                    Spacer()
                    Text("\(draft.courses.count) 条").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(draft.rawText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                Button { showingReview = true } label: {
                    Text("检查并导入")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(GlassPalette.accent.gradient))
                }
                .disabled(draft.courses.isEmpty)
                .opacity(draft.courses.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var transferCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("课表文件").font(.system(size: 15, weight: .bold))
                Button { exportScheduleFile() } label: {
                    Label("导出课表文件（.lcs）", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
                Button { excelPickRequested = false; showingFileImporter = true } label: {
                    Label("导入课表文件（.lcs / JSON）", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text("导出的 .lcs 文件可直接在另一台手机的流云课表中导入。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func messageCard(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .liuyunGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Actions

    private func scanImage(_ item: PhotosPickerItem) {
        beginScanning("正在识别图片…")
        selectedItem = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw AIScheduleError.badResponse
                }
                draft = try await AIScheduleService().recognize(image: image)
            } catch {
                errorMessage = "识别失败：\(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    private func pickExcel() {
        excelPickRequested = true
        showingFileImporter = true
    }

    @State private var excelPickRequested = false

    private func beginScanning(_ text: String) {
        isScanning = true
        scanningText = text
        errorMessage = nil
        confirmationMessage = nil
        draft = nil
    }

    private func exportScheduleFile() {
        errorMessage = nil
        do {
            let data = try TransferBridge.encode(model.document)
            shareURL = try FileExporter.writeTemporary(name: model.table.name, ext: FileExporter.scheduleExtension, data: data)
            confirmationMessage = "已生成课表文件，可保存或分享到其他设备。"
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let wasExcelPick = excelPickRequested
        excelPickRequested = false
        errorMessage = nil
        confirmationMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let ext = url.pathExtension.lowercased()
            let scheduleTypes: Set<String> = ["lcs", "json"]
            if wasExcelPick || !scheduleTypes.contains(ext) {
                importSpreadsheet(url)
            } else {
                importScheduleFile(url)
            }
        case .failure(let error):
            if (error as NSError).code == NSUserCancelledError { return }
            errorMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func importSpreadsheet(_ url: URL) {
        beginScanning("正在解析表格并识别课程…")
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try FileExporter.readData(at: url)
                }.value
                let ext = url.pathExtension
                draft = try await AIScheduleService().recognize(spreadsheet: data, fileExtension: ext)
            } catch {
                errorMessage = "表格识别失败：\(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    private func importScheduleFile(_ url: URL) {
        do {
            let data = try FileExporter.readData(at: url)
            let document = try TransferBridge.decode(data)
            model.replaceDocument(document)
            confirmationMessage = "已导入 \(document.tables.count) 张课程表，共 \(document.tables.reduce(0) { $0 + $1.courses.count }) 门课程。"
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Review sheet

/// Full-fidelity editor for an OCR/AI draft. Every field that the `.lcs`
/// format carries is editable here; nothing is saved until 导入.
struct ScheduleReviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let draft: OCRDraft
    @State private var rows: [EditableRow]
    @State private var rawExpanded = false
    @State private var applySemesterStart = true
    @State private var semesterStart = ScheduleDocument.mondayOfCurrentWeek()
    @State private var totalWeeks = 18

    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    struct EditableRow: Identifiable {
        let id = UUID()
        var name: String
        var teacher: String
        var location: String
        var weekday: Int
        var mode: TimingMode
        var startPeriod: Int
        var endPeriod: Int
        var customStart: Date
        var customEnd: Date
        var weeks: Set<Int>
        var included: Bool
    }

    init(draft: OCRDraft) {
        self.draft = draft
        _rows = State(initialValue: draft.courses.map { course in
            let isCustom = course.timingMode == TimingMode.custom.rawValue || (course.customStart != nil && course.startPeriod == nil)
            return EditableRow(
                name: course.name,
                teacher: course.teacher ?? "",
                location: course.location ?? "",
                weekday: min(max(course.weekday, 1), 7),
                mode: isCustom ? .custom : .period,
                startPeriod: max(1, course.startPeriod ?? 1),
                endPeriod: max(1, course.endPeriod ?? course.startPeriod ?? 1),
                customStart: EditableRow.date(from: course.customStart) ?? EditableRow.date(minutes: 16 * 60 + 40),
                customEnd: EditableRow.date(from: course.customEnd) ?? EditableRow.date(minutes: 18 * 60 + 10),
                weeks: Set(course.weeks ?? Array(1...(draft.suggestedTotalWeeks ?? 18))),
                included: true
            )
        })
        if let suggestedStart = draft.suggestedSemesterStart,
           let date = ScheduleTransfer.parseDate(suggestedStart) {
            _semesterStart = State(initialValue: date)
        }
        _totalWeeks = State(initialValue: min(52, max(1, draft.suggestedTotalWeeks ?? 18)))
    }

    var body: some View {
        NavigationStack {
            Form {
                semesterSection
                Section {
                    ForEach($rows) { $row in
                        rowEditor($row)
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                } header: {
                    Text("课程时段（\(rows.filter(\.included).count)/\(rows.count) 已选）")
                } footer: {
                    Text("同一门课有多个时段时可保留多条，共用课程名即可。")
                }

                if !draft.warnings.isEmpty {
                    Section("提醒") {
                        ForEach(draft.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                    }
                }
                Section("识别原文") {
                    DisclosureGroup("展开原文", isExpanded: $rawExpanded) {
                        Text(draft.rawText).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("确认导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { commit() }
                        .disabled(rows.filter(\.included).isEmpty)
                }
            }
        }
    }

    private var semesterSection: some View {
        Section("学期信息") {
            Toggle("更新第一周日期", isOn: $applySemesterStart)
            if applySemesterStart {
                DatePicker("第一周", selection: $semesterStart, displayedComponents: .date)
                Stepper("总周数：\(totalWeeks)", value: $totalWeeks, in: 1...52)
            }
        }
    }

    private func rowEditor(_ row: Binding<EditableRow>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("课程名称", text: row.name).font(.system(size: 15, weight: .semibold))
                Toggle("", isOn: row.included).labelsHidden()
            }
            HStack {
                TextField("教师", text: row.teacher).font(.system(size: 12))
                TextField("教室", text: row.location).font(.system(size: 12))
            }
            Picker("星期", selection: row.weekday) {
                ForEach(1...7, id: \.self) { Text(dayNames[$0 - 1]).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("时间", selection: row.mode) {
                ForEach(TimingMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if row.wrappedValue.mode == .period {
                HStack {
                    Stepper("开始 \(row.wrappedValue.startPeriod) 节", value: row.startPeriod, in: 1...14)
                    Stepper("结束 \(row.wrappedValue.endPeriod) 节", value: row.endPeriod, in: 1...14)
                }
            } else {
                DatePicker("开始", selection: row.customStart, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: row.customEnd, displayedComponents: .hourAndMinute)
            }

            Text("已选 \(row.wrappedValue.weeks.count) 周").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func commit() {
        let effectiveWeeks = applySemesterStart ? totalWeeks : model.table.totalWeeks
        if applySemesterStart {
            model.updateTable { table in
                table.semesterStartDate = semesterStart
                table.totalWeeks = min(52, max(1, totalWeeks))
            }
        }

        // Group rows that describe the same course (same name + teacher + room)
        // into ONE `Course` with several `MeetingRule`s, matching the domain
        // model — AI emits one row per class period.
        struct Group { var course: Course; var rules: [MeetingRule] }
        var order: [String] = []
        var groups: [String: Group] = [:]
        let palette = ["#0F77FF", "#3BA55D", "#E84A8A", "#F5A623", "#8E5BF0", "#00B8C4", "#EF4B4B", "#5C7CFA"]

        for row in rows where row.included {
            let cleanName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }
            let teacher = row.teacher.nilIfBlank
            let location = row.location.nilIfBlank
            let key = [cleanName, teacher ?? "", location ?? ""].joined(separator: "|")

            let course: Course
            if let existing = groups[key] {
                course = existing.course
            } else {
                course = Course(
                    courseTableID: model.table.id,
                    name: cleanName,
                    teacher: teacher,
                    location: location,
                    colorHex: palette[order.count % palette.count]
                )
                order.append(key)
                groups[key] = Group(course: course, rules: [])
            }

            let weeks = Set(row.weeks.filter { $0 >= 1 && $0 <= effectiveWeeks })
            let finalWeeks = weeks.isEmpty ? Set(1...max(1, effectiveWeeks)) : weeks
            let rule: MeetingRule
            if row.mode == .period {
                let start = max(1, row.startPeriod)
                rule = MeetingRule(courseID: course.id, weekday: row.weekday, weekSet: finalWeeks, startPeriod: start, endPeriod: max(start, row.endPeriod))
            } else {
                rule = MeetingRule(courseID: course.id, weekday: row.weekday, weekSet: finalWeeks, customStartMinute: EditableRow.minutes(of: row.customStart), customEndMinute: EditableRow.minutes(of: row.customEnd))
            }
            groups[key]?.rules.append(rule)
        }

        let incoming = order.compactMap { groups[$0].map { StoredCourse(course: $0.course, rules: $0.rules) } }
        model.importCourses(incoming)
        dismiss()
    }
}

extension ScheduleReviewSheet.EditableRow {
    static func date(minutes: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now
    }
    static func date(from text: String?) -> Date? {
        guard let minutes = text.flatMap(Period.minutes(from:)) else { return nil }
        return date(minutes: minutes)
    }
    static func minutes(of date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
