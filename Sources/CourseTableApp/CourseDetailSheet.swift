import SwiftUI
import UIKit
import CourseTableCore

/// Read-only detail with actions: edit, delete, export this course to the
/// Apple calendar, and share an ICS. Multi-rule aware.
struct CourseDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: StoredCourse

    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var isExporting = false
    @State private var resultMessage: String?
    @State private var shareURL: URL?
    private var shareSelection: Binding<ShareItem?> {
        Binding(
            get: { shareURL.map(ShareItem.init) },
            set: { shareURL = $0?.url }
        )
    }

    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    banner
                    infoCard
                    ForEach(Array(item.rules.enumerated()), id: \.element.id) { index, rule in
                        ruleCard(rule, index: index + 1)
                    }
                    actionCard
                    if let resultMessage {
                        Text(resultMessage)
                            .font(.footnote)
                            .foregroundStyle(resultMessage.hasPrefix("已") ? .green : .orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(GlassBackground().opacity(0.6))
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingEditor = true } label: { Label("编辑", systemImage: "pencil") }
                        Button(role: .destructive) { showingDeleteConfirm = true } label: { Label("删除课程", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                CourseEditorSheet(existing: item).environmentObject(model)
            }
            .sheet(item: shareSelection) { share in
                ShareSheet(items: [share.url])
            }
            .confirmationDialog("确认删除这门课程？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    model.deleteCourse(item.course.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: Cards

    private var banner: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(GlassPalette.color(fromHex: item.course.colorHex).gradient)
                .frame(width: 54, height: 54)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            Text(item.course.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            if let teacher = item.course.teacher, !teacher.isEmpty {
                Text(teacher).font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .liuyunGlass(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var infoCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(spacing: 12) {
                if let location = item.course.location, !location.isEmpty { row("教室", location, "mappin.and.ellipse") }
                if let notes = item.course.notes, !notes.isEmpty { row("备注", notes, "note.text") }
                row("时段数", "\(item.rules.count) 个", "clock")
            }
        }
    }

    private func ruleCard(_ rule: MeetingRule, index: Int) -> some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("时段 \(index)").font(.system(size: 13, weight: .bold)).foregroundStyle(GlassPalette.accent)
                row("星期", dayNames[max(0, min(6, rule.weekday - 1))], "calendar")
                row("时间", timeSummary(rule), "clock")
                row("周次", weekSummary(rule.weekSet), "list.number")
                row("提醒", reminderSummary(rule), "bell")
            }
        }
    }

    private var actionCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(spacing: 12) {
                Button { exportToCalendar() } label: {
                    HStack {
                        if isExporting { ProgressView().tint(GlassPalette.accent) }
                        Label("写入 Apple 日历", systemImage: "calendar.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(GlassPalette.accent)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)

                Divider().opacity(0.3)

                Button { shareICS() } label: {
                    HStack {
                        Label("分享 .ics 日历文件", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.primary.opacity(0.8))
                }
                .buttonStyle(.plain)

                Text("写入日历时会按所选周次逐次创建，重复导入只更新不重复。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.trailing)
        }
    }

    // MARK: Summaries

    private func timeSummary(_ rule: MeetingRule) -> String {
        switch rule.timingMode {
        case .period: return "第 \(rule.startPeriod ?? 0)–\(rule.endPeriod ?? 0) 节"
        case .custom:
            return "\(Period.text(from: rule.customStartMinute ?? 0))–\(Period.text(from: rule.customEndMinute ?? 0))"
        }
    }

    private func weekSummary(_ weeks: Set<Int>) -> String {
        let sorted = weeks.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "未设置" }
        if sorted.count == last - first + 1 { return "第 \(first)–\(last) 周" }
        return "共 \(sorted.count) 周：\(sorted.map(String.init).joined(separator: ", "))"
    }

    private func reminderSummary(_ rule: MeetingRule) -> String {
        let minutes = rule.reminderMinutes ?? model.table.defaultReminderMinutes
        guard let minutes else { return "不提醒" }
        if minutes < 0 { return "不提醒" }
        return minutes == 0 ? "上课时" : "提前 \(minutes) 分钟"
    }

    // MARK: Actions

    private func exportToCalendar() {
        isExporting = true
        resultMessage = nil
        Task {
            do {
                let summary = try await CalendarService.shared.export(
                    course: item.course,
                    rules: item.rules,
                    table: model.table,
                    periods: model.periods,
                    existingRecords: model.document.calendarExports
                )
                model.replaceCalendarExports(summary.allRecords)
                resultMessage = "已写入 \(summary.created) 个日程，更新 \(summary.updated) 个。"
            } catch {
                resultMessage = "导出失败：\(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private func shareICS() {
        resultMessage = nil
        do {
            let content = try ICSGenerator.generate(
                courses: [item.course],
                rulesByCourse: [item.course.id: item.rules],
                table: model.table,
                periods: model.periods
            )
            let url = try FileExporter.writeTemporary(name: item.course.name, ext: "ics", content: content)
            shareURL = url
        } catch {
            resultMessage = "生成失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Table manager

/// Lists every course table, switches the active one, adds and deletes tables.
struct TableManagerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newStart = Date()
    @State private var newWeeks = 18

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.document.tables) { stored in
                        tableRow(stored)
                    }
                }
                .padding(16)
            }
            .background(GlassBackground().opacity(0.6))
            .navigationTitle("课程表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { addSheet }
        }
    }

    private func tableRow(_ stored: StoredTable) -> some View {
        let isActive = stored.id == model.document.activeTableID
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.setActiveTable(stored.id) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isActive ? AnyShapeStyle(GlassPalette.accent.gradient) : AnyShapeStyle(.ultraThinMaterial))
                        .frame(width: 40, height: 40)
                    if isActive {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(stored.table.name).font(.system(size: 16, weight: .semibold))
                    Text("\(stored.courses.count) 门课 · \(stored.table.totalWeeks) 周")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Text("当前").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(GlassPalette.accent))
                }
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .liuyunGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            if model.document.tables.count > 1 {
                Button(role: .destructive) { model.deleteTable(stored.id) } label: { Label("删除课程表", systemImage: "trash") }
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("课程表名称", text: $newName)
                DatePicker("第一周日期", selection: $newStart, displayedComponents: .date)
                Stepper("总周数：\(newWeeks)", value: $newWeeks, in: 1...52)
            }
            .navigationTitle("新建课程表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingAdd = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        model.addTable(named: newName, semesterStart: newStart, totalWeeks: newWeeks)
                        newName = ""; showingAdd = false
                    }
                }
            }
        }
    }
}

// MARK: - Share helpers

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
