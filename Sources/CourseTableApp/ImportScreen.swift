import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import CourseTableCore

/// Import hub: photo OCR with a mandatory review step, plus JSON backup
/// import/export. Never writes to the timetable or calendar automatically.
struct ImportScreen: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var draft: OCRDraft?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showingReview = false
    @State private var showingJSONImporter = false
    @State private var shareURL: URL?
    private var shareSelection: Binding<ShareItem?> {
        Binding(
            get: { shareURL.map(ShareItem.init) },
            set: { shareURL = $0?.url }
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                photoCard
                if isScanning { scanningCard }
                if let draft { draftCard(draft) }
                backupCard
                if let confirmationMessage { messageCard(confirmationMessage, color: .green) }
                if let errorMessage { messageCard(errorMessage, color: .orange) }
            }
            .padding(16)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showingReview) {
            if let draft { OCRReviewSheet(draft: draft).environmentObject(model) }
        }
        .sheet(item: shareSelection) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $showingJSONImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            scan(item)
        }
    }

    // MARK: Cards

    private var header: some View {
        GlassCard(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导入课程").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("拍照识别或从其他设备迁移，确认后才会生效")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var photoCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(GlassPalette.accent.opacity(0.12)).frame(width: 74, height: 74)
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(GlassPalette.accent)
                }
                Text("识别课表截图").font(.system(size: 16, weight: .semibold))
                Text("支持相册选图，图片只在本机识别，不会上传。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("从相册选择")
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

    private var scanningCard: some View {
        GlassCard(cornerRadius: 20) {
            HStack(spacing: 12) {
                ProgressView().tint(GlassPalette.accent)
                Text("正在识别课程与时间…").font(.system(size: 14, weight: .medium))
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
                Text("已解析 \(draft.courses.count) 条课程，请检查后再导入。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button {
                    showingReview = true
                } label: {
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

    private var backupCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("备份与迁移").font(.system(size: 15, weight: .bold))
                Button { exportJSON() } label: {
                    Label("导出全部课程表（JSON）", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
                Button { showingJSONImporter = true } label: {
                    Label("从 JSON 文件导入", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
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

    private func scan(_ item: PhotosPickerItem) {
        isScanning = true
        errorMessage = nil
        confirmationMessage = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw OCRServiceError.invalidImage
                }
                draft = try await OCRService().recognize(image: image)
            } catch {
                errorMessage = "识别失败：\(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    private func exportJSON() {
        errorMessage = nil
        do {
            let data = try TransferBridge.encode(model.document)
            shareURL = try FileExporter.writeTemporary(name: "流云课表备份", ext: "json", data: data)
            confirmationMessage = "已生成备份文件，请选择保存位置。"
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        confirmationMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try FileExporter.readData(at: url)
                let document = try TransferBridge.decode(data)
                model.replaceDocument(document)
                confirmationMessage = "已导入 \(document.tables.count) 张课程表。"
            } catch {
                errorMessage = "导入失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - OCR review

/// Review + edit the parsed rows before committing. Nothing is saved until
/// the user taps 导入.
struct OCRReviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let draft: OCRDraft
    @State private var rows: [EditableRow]
    @State private var rawExpanded = false

    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    struct EditableRow: Identifiable {
        let id: UUID
        var name: String
        var teacher: String
        var location: String
        var weekday: Int
        var included: Bool
    }

    init(draft: OCRDraft) {
        self.draft = draft
        _rows = State(initialValue: draft.courses.map {
            EditableRow(id: $0.id, name: $0.name, teacher: $0.teacher ?? "", location: $0.location ?? "", weekday: $0.weekday, included: true)
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("课程名称", text: $row.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Toggle("", isOn: $row.included).labelsHidden()
                            }
                            HStack {
                                TextField("教师", text: $row.teacher).font(.system(size: 12))
                                TextField("教室", text: $row.location).font(.system(size: 12))
                            }
                            Picker("星期", selection: $row.weekday) {
                                ForEach(1...7, id: \.self) { Text(dayNames[$0 - 1]).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                } header: {
                    Text("课程（\(rows.filter(\.included).count)/\(rows.count) 已选）")
                } footer: {
                    Text("默认按整学期每周上课，导入后可在课表中编辑周次与节次。")
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

    private func commit() {
        let totalWeeks = model.table.totalWeeks
        var incoming: [StoredCourse] = []
        for row in rows where row.included {
            let cleanName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }
            let course = Course(
                courseTableID: model.table.id,
                name: cleanName,
                teacher: row.teacher.nilIfBlank,
                location: row.location.nilIfBlank,
                colorHex: model.courses.count.isMultiple(of: 2) ? "#0F77FF" : "#3BA55D"
            )
            let rule = MeetingRule(
                courseID: course.id,
                weekday: min(max(row.weekday, 1), 7),
                weekSet: Set(1...max(1, totalWeeks)),
                startPeriod: model.periods.first?.index ?? 1,
                endPeriod: model.periods.first?.index ?? 1
            )
            incoming.append(StoredCourse(course: course, rules: [rule]))
        }
        model.importCourses(incoming)
        dismiss()
    }
}
