import SwiftUI
import CourseTableCore

/// Settings: course-table metadata, period times, reminder policy, whole-table
/// Apple calendar export, and ICS sharing.
struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel

    @State private var name = ""
    @State private var totalWeeks = 18
    @State private var semesterStart = Date()
    @State private var hasWeekend = false
    @State private var showOutside = false
    @State private var reminderMinutes = 30
    @State private var reminderStyle: ReminderStyle = .notification

    @State private var periods: [Period] = []
    @State private var isExporting = false
    @State private var message: String?
    @State private var shareURL: URL?
    @State private var loaded = false
    @State private var timeSelection: PeriodTimeSelection?
    private struct PeriodTimeSelection: Identifiable {
        let id = UUID()
        let periodID: UUID
        let index: Int
        let isStart: Bool
        let minute: Int
    }
    private var shareSelection: Binding<ShareItem?> {
        Binding(
            get: { shareURL.map(ShareItem.init) },
            set: { shareURL = $0?.url }
        )
    }

    private let reminderChoices = [0, 5, 10, 15, 30, 60, 120]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                appearanceCard
                tableCard
                periodCard
                reminderCard
                calendarCard
                if let message {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(message.hasPrefix("已") ? .green : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .liuyunGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(16)
            .padding(.bottom, 120)
        }
        .onAppear(perform: loadFromModel)
        .onChange(of: model.document.activeTableID) { _, _ in loadFromModel() }
        .sheet(item: shareSelection) { ShareSheet(items: [$0.url]) }
        .sheet(item: $timeSelection) { selection in
            PeriodTimePickerSheet(index: selection.index, isStart: selection.isStart, minute: selection.minute) { minute in
                guard let index = periods.firstIndex(where: { $0.id == selection.periodID }) else { return }
                if selection.isStart { periods[index].startMinuteOfDay = minute }
                else { periods[index].endMinuteOfDay = minute }
            }
            .presentationDetents([.height(350)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(30)
        }
    }

    // MARK: Load

    private func loadFromModel() {
        name = model.table.name
        totalWeeks = model.table.totalWeeks
        semesterStart = model.table.semesterStartDate
        hasWeekend = model.table.hasWeekendCourses
        showOutside = model.table.showCoursesOutsideSelectedWeek
        reminderMinutes = model.table.defaultReminderMinutes ?? 30
        reminderStyle = model.table.reminderStyle
        periods = model.periods
        loaded = true
    }

    // MARK: Cards

    private var header: some View {
        GlassCard(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("设置").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("课程表信息、节次时间与日历导出")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("外观").font(.system(size: 15, weight: .bold))
                Picker("外观模式", selection: Binding(
                    get: { model.appearance },
                    set: { mode in
                        withAnimation(.easeInOut(duration: 0.25)) { model.setAppearance(mode) }
                    }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Divider().opacity(0.3)

                HStack {
                    Text("液态玻璃不透明度").font(.system(size: 14)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(model.glassOpacity * 100))%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(GlassPalette.accent)
                }
                HStack(spacing: 10) {
                    Image(systemName: "square.dashed").font(.system(size: 13)).foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { model.glassOpacity },
                            set: { model.setGlassOpacity($0) }
                        ),
                        in: 0.3...1.0
                    )
                    .tint(GlassPalette.accent)
                    Image(systemName: "square.fill").font(.system(size: 13)).foregroundStyle(GlassPalette.accent)
                }
                Text("向左更通透、向右更厚重，实时生效。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var tableCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("课程表信息").font(.system(size: 15, weight: .bold))
                labeledField("名称") {
                    TextField("课程表名称", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                labeledField("第一周") {
                    DatePicker("", selection: $semesterStart, displayedComponents: .date).labelsHidden()
                }
                labeledField("总周数") {
                    Stepper("\(totalWeeks)", value: $totalWeeks, in: 1...52)
                        .fixedSize()
                }
                Toggle("周末有课", isOn: $hasWeekend)
                Toggle("显示非本周课程", isOn: $showOutside)
                Button { saveTable() } label: {
                    Text("保存课程表设置")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(GlassPalette.accent.gradient))
                }
                .disabled(!loaded)
            }
        }
    }

    private var periodCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("节次时间").font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button("恢复默认") {
                        periods = ScheduleDocument.defaultPeriods
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                ForEach($periods) { $period in
                    HStack(spacing: 8) {
                        Text("第 \(period.index) 节").font(.system(size: 13, weight: .medium)).frame(width: 58, alignment: .leading)
                        periodTimeButton(period, isStart: true)
                        Text("–").foregroundStyle(.secondary)
                        periodTimeButton(period, isStart: false)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        addPeriod()
                    } label: {
                        Label("加一节", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GlassPalette.accent)
                    Spacer()
                    if periods.count > 1 {
                        Button {
                            periods.removeLast()
                        } label: {
                            Label("删一节", systemImage: "minus").font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                }
                Button { savePeriods() } label: {
                    Text("保存节次时间")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(GlassPalette.accent.gradient))
                }
            }
        }
    }

    private func periodTimeButton(_ period: Period, isStart: Bool) -> some View {
        Button {
            timeSelection = PeriodTimeSelection(periodID: period.id, index: period.index, isStart: isStart, minute: isStart ? period.startMinuteOfDay : period.endMinuteOfDay)
        } label: {
            Text(isStart ? period.startText : period.endText)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("第\(period.index)节\(isStart ? "开始" : "结束")时间")
    }

    private var reminderCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("默认提醒").font(.system(size: 15, weight: .bold))
                labeledField("提前") {
                    Picker("", selection: $reminderMinutes) {
                        ForEach(reminderChoices, id: \.self) { Text($0 == 0 ? "上课时" : "\($0) 分钟").tag($0) }
                    }
                    .labelsHidden()
                }
                labeledField("方式") {
                    Picker("", selection: $reminderStyle) {
                        ForEach(ReminderStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var calendarCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("日历").font(.system(size: 15, weight: .bold))
                Button { exportAll() } label: {
                    HStack {
                        if isExporting { ProgressView().tint(GlassPalette.accent) }
                        Label("把整学期写入 Apple 日历", systemImage: "calendar.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(GlassPalette.accent)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)

                Divider().opacity(0.3)

                Button { shareICS() } label: {
                    Label("分享整学期 .ics", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Sub-views

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }

    private func timeField(_ value: String, onChange: @escaping (String) -> Void) -> some View {
        TextField("", text: Binding(get: { value }, set: onChange))
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(width: 68)
            .padding(.vertical, 6)
            .liuyunGlass(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Actions

    private func addPeriod() {
        let index = (periods.map(\.index).max() ?? 0) + 1
        let last = periods.last
        let start = last?.endMinuteOfDay ?? 8 * 60
        periods.append(Period(index: index, startMinuteOfDay: start + 5, endMinuteOfDay: start + 50))
    }

    private func saveTable() {
        model.updateTable { table in
            table.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我的课程表" : name
            table.totalWeeks = min(52, max(1, totalWeeks))
            table.hasWeekendCourses = hasWeekend
            table.showCoursesOutsideSelectedWeek = showOutside
            table.defaultReminderMinutes = reminderMinutes
            table.reminderStyle = reminderStyle
            table.semesterStartDate = semesterStart
        }
        message = "已保存课程表设置。"
    }

    private func savePeriods() {
        guard periods.allSatisfy({ $0.endMinuteOfDay > $0.startMinuteOfDay }) else {
            message = "节次结束时间必须晚于开始时间，请检查后再保存。"
            return
        }
        let normalized = periods.enumerated().map { offset, period in
            Period(id: period.id, index: offset + 1, startMinuteOfDay: period.startMinuteOfDay, endMinuteOfDay: period.endMinuteOfDay)
        }
        model.setPeriods(normalized)
        periods = normalized
        message = "已保存节次时间。"
    }

    private func exportAll() {
        isExporting = true
        message = nil
        Task {
            do {
                let summary = try await CalendarService.shared.exportAll(
                    table: model.table,
                    periods: model.periods,
                    courses: model.courses,
                    existingRecords: model.document.calendarExports
                )
                model.replaceCalendarExports(summary.allRecords)
                message = "已写入 \(summary.created) 个日程，更新 \(summary.updated) 个，跳过 \(summary.skipped) 个。"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private func shareICS() {
        message = nil
        do {
            let rulesByCourse = Dictionary(uniqueKeysWithValues: model.courses.map { ($0.course.id, $0.rules) })
            let content = try ICSGenerator.generate(
                courses: model.courses.map(\.course),
                rulesByCourse: rulesByCourse,
                table: model.table,
                periods: model.periods
            )
            shareURL = try FileExporter.writeTemporary(name: model.table.name, ext: "ics", content: content)
        } catch {
            message = "生成失败：\(error.localizedDescription)"
        }
    }
}

private struct PeriodTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let index: Int
    let isStart: Bool
    let onSave: (Int) -> Void
    @State private var time: Date

    init(index: Int, isStart: Bool, minute: Int, onSave: @escaping (Int) -> Void) {
        self.index = index
        self.isStart = isStart
        self.onSave = onSave
        let base = Calendar.current.startOfDay(for: .now)
        _time = State(initialValue: Calendar.current.date(byAdding: .minute, value: minute, to: base) ?? base)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("取消") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Text("第\(index)节 · \(isStart ? "开始" : "结束")时间").font(.headline)
                Spacer()
                Button("确定") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    onSave((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                    dismiss()
                }.buttonStyle(.glassProminent)
            }
            DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}
