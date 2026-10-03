import SwiftUI
import CourseTableCore

/// Create or edit a course. Supports multiple meeting rules, arbitrary week
/// sets (with single/double-week shortcuts), period or custom timing, a colour
/// and a per-course reminder.
struct CourseEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let existing: StoredCourse?

    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var colorHex = "#0F77FF"
    @State private var rules: [DraftRule] = []
    @State private var validationMessage: String?

    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private let palette = ["#0F77FF", "#3BA55D", "#E84A8A", "#F5A623", "#8E5BF0", "#00B8C4", "#EF4B4B", "#5C7CFA"]

    init(existing: StoredCourse?) {
        self.existing = existing
        if let existing {
            _name = State(initialValue: existing.course.name)
            _teacher = State(initialValue: existing.course.teacher ?? "")
            _location = State(initialValue: existing.course.location ?? "")
            _notes = State(initialValue: existing.course.notes ?? "")
            _colorHex = State(initialValue: existing.course.colorHex)
            _rules = State(initialValue: existing.rules.map(DraftRule.init))
        } else {
            _rules = State(initialValue: [DraftRule()])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                courseInfoSection
                ForEach($rules) { $rule in
                    ruleSection($rule, index: rules.firstIndex(where: { $0.id == rule.id }) ?? 0)
                }
                .onDelete { offsets in
                    rules.remove(atOffsets: offsets)
                    if rules.isEmpty { rules = [DraftRule()] }
                }
                addRuleButton
                if let validationMessage {
                    Section { Text(validationMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground().opacity(0.6))
            .navigationTitle(existing == nil ? "新建课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: Sections

    private var courseInfoSection: some View {
        Section("课程信息") {
            TextField("课程名称（必填）", text: $name)
            TextField("教师", text: $teacher)
            TextField("教室", text: $location)
            TextField("备注", text: $notes, axis: .vertical)
            VStack(alignment: .leading, spacing: 10) {
                Text("课程颜色").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(palette, id: \.self) { hex in
                        Circle()
                            .fill(GlassPalette.color(fromHex: hex).gradient)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 2 : 0))
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                            .scaleEffect(colorHex == hex ? 1.12 : 1)
                            .onTapGesture { withAnimation(.spring(response: 0.3)) { colorHex = hex } }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func ruleSection(_ rule: Binding<DraftRule>, index: Int) -> some View {
        Section("上课时段 \(index + 1)") {
            Picker("星期", selection: rule.weekday) {
                ForEach(1...7, id: \.self) { Text(dayNames[$0 - 1]).tag($0) }
            }
            Picker("时间方式", selection: rule.mode) {
                ForEach(TimingMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if rule.wrappedValue.mode == .period {
                Picker("开始节次", selection: rule.startPeriod) {
                    ForEach(model.periods, id: \.index) { Text("第 \($0.index) 节").tag($0.index) }
                }
                Picker("结束节次", selection: rule.endPeriod) {
                    ForEach(model.periods, id: \.index) { Text("第 \($0.index) 节").tag($0.index) }
                }
            } else {
                DatePicker("开始", selection: rule.customStartDate, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: rule.customEndDate, displayedComponents: .hourAndMinute)
            }

            weekPatternPicker(rule)
            weekGrid(rule)

            Picker("提醒", selection: rule.reminderMinutes) {
                Text("默认").tag(Int?.none)
                Text("不提醒").tag(Int?.some(-1))
                Text("上课时").tag(Int?.some(0))
                Text("提前 5 分钟").tag(Int?.some(5))
                Text("提前 10 分钟").tag(Int?.some(10))
                Text("提前 30 分钟").tag(Int?.some(30))
                Text("提前 1 小时").tag(Int?.some(60))
                Text("提前 2 小时").tag(Int?.some(120))
            }
        }
    }

    private func weekPatternPicker(_ rule: Binding<DraftRule>) -> some View {
        Picker("周次模式", selection: rule.pattern) {
            ForEach(WeekPattern.allCases) { Text($0.label).tag($0) }
        }
        .onChange(of: rule.wrappedValue.pattern) { _, pattern in
            let draft = rule.wrappedValue
            rule.wrappedValue.weekSet = WeekPattern.weeks(
                range: min(draft.startWeek, draft.endWeek)...max(draft.startWeek, draft.endWeek),
                pattern: pattern
            )
        }
    }

    private func weekGrid(_ rule: Binding<DraftRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("起始周").font(.footnote)
                Picker("", selection: rule.startWeek) {
                    ForEach(1...max(1, model.table.totalWeeks), id: \.self) { Text("第 \($0) 周").tag($0) }
                }
                .labelsHidden()
                .onChange(of: rule.wrappedValue.startWeek) { _, _ in rebuildWeeks(rule) }
                Text("结束周").font(.footnote)
                Picker("", selection: rule.endWeek) {
                    ForEach(1...max(1, model.table.totalWeeks), id: \.self) { Text("第 \($0) 周").tag($0) }
                }
                .labelsHidden()
                .onChange(of: rule.wrappedValue.endWeek) { _, _ in rebuildWeeks(rule) }
            }
            Text("已选 \(rule.wrappedValue.weekSet.count) 周：\(weekSummary(rule.wrappedValue.weekSet))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func rebuildWeeks(_ rule: Binding<DraftRule>) {
        let draft = rule.wrappedValue
        rule.wrappedValue.weekSet = WeekPattern.weeks(
            range: min(draft.startWeek, draft.endWeek)...max(draft.startWeek, draft.endWeek),
            pattern: draft.pattern
        )
    }

    private func weekSummary(_ weeks: Set<Int>) -> String {
        let sorted = weeks.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "未选择" }
        if sorted.count == last - first + 1 { return "第 \(first)–\(last) 周" }
        return sorted.map(String.init).joined(separator: ", ")
    }

    private var addRuleButton: some View {
        Section {
            Button {
                rules.append(DraftRule())
            } label: {
                Label("添加上课时段", systemImage: "plus.circle")
            }
        }
    }

    // MARK: Save

    private func save() {
        validationMessage = nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { validationMessage = "请填写课程名称。"; return }
        guard !rules.isEmpty else { validationMessage = "至少需要一个上课时段。"; return }

        let baseID = existing?.course.id ?? UUID()
        let course = Course(
            id: baseID,
            courseTableID: model.table.id,
            name: cleanName,
            teacher: teacher.nilIfBlank,
            location: location.nilIfBlank,
            notes: notes.nilIfBlank,
            colorHex: colorHex
        )

        var meetingRules: [MeetingRule] = []
        for (index, draft) in rules.enumerated() {
            guard !draft.weekSet.isEmpty else {
                validationMessage = "时段 \(index + 1)：至少选择一个上课周次。"
                return
            }
            let rule: MeetingRule
            if draft.mode == .period {
                rule = MeetingRule(
                    id: draft.id,
                    courseID: baseID,
                    weekday: draft.weekday,
                    weekSet: draft.weekSet,
                    startPeriod: draft.startPeriod,
                    endPeriod: draft.endPeriod,
                    reminderMinutes: draft.reminderMinutes
                )
            } else {
                let start = draft.customStartMinutes
                let end = draft.customEndMinutes
                rule = MeetingRule(
                    id: draft.id,
                    courseID: baseID,
                    weekday: draft.weekday,
                    weekSet: draft.weekSet,
                    customStartMinute: start,
                    customEndMinute: end,
                    reminderMinutes: draft.reminderMinutes
                )
            }
            do { try MeetingRuleValidator.validate(rule, in: model.table, periods: model.periods) }
            catch {
                validationMessage = "时段 \(index + 1)：\(error.localizedDescription)"
                return
            }
            meetingRules.append(rule)
        }

        model.upsertCourse(course, rules: meetingRules)
        dismiss()
    }
}

// MARK: - Draft rule

/// Mutable, view-friendly mirror of `MeetingRule`.
struct DraftRule: Identifiable {
    var id = UUID()
    var weekday = 1
    var mode: TimingMode = .period
    var startPeriod = 1
    var endPeriod = 1
    var customStartMinutes = 16 * 60 + 40
    var customEndMinutes = 18 * 60 + 10
    var startWeek = 1
    var endWeek = 18
    var pattern: WeekPattern = .every
    var weekSet: Set<Int> = Set(1...18)
    var reminderMinutes: Int? = nil

    init() {
        rebuild()
    }

    init(_ rule: MeetingRule) {
        id = rule.id
        weekday = rule.weekday
        mode = rule.timingMode
        startPeriod = rule.startPeriod ?? 1
        endPeriod = rule.endPeriod ?? startPeriod
        customStartMinutes = rule.customStartMinute ?? (16 * 60 + 40)
        customEndMinutes = rule.customEndMinute ?? (18 * 60 + 10)
        reminderMinutes = rule.reminderMinutes
        let sorted = rule.weekSet.sorted()
        startWeek = sorted.first ?? 1
        endWeek = sorted.last ?? 18
        weekSet = rule.weekSet
        pattern = WeekPattern.detect(from: rule.weekSet)
    }

    mutating func rebuild() {
        weekSet = WeekPattern.weeks(range: startWeek...max(startWeek, endWeek), pattern: pattern)
    }

    var customStartDate: Date {
        get { Calendar.current.date(from: DateComponents(hour: customStartMinutes / 60, minute: customStartMinutes % 60)) ?? .now }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            customStartMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
    }

    var customEndDate: Date {
        get { Calendar.current.date(from: DateComponents(hour: customEndMinutes / 60, minute: customEndMinutes % 60)) ?? .now }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            customEndMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
