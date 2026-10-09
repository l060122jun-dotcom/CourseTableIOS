import SwiftUI
import CourseTableCore

/// All stored courses, including those not running in the selected week.
struct CourseOverviewScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var selection: DetailSelection?

    private struct CourseGroup: Identifiable {
        let name: String
        let records: [StoredCourse]
        var id: String { name }
        var weeks: Set<Int> {
            records.flatMap(\.rules).reduce(into: Set<Int>()) { $0.formUnion($1.weekSet) }
        }
    }

    private var allGroups: [CourseGroup] {
        Dictionary(grouping: model.courses) { $0.course.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { CourseGroup(name: $0.key, records: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var courses: [CourseGroup] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allGroups.filter { group in
            key.isEmpty || group.records.contains { record in
                [record.course.name, record.course.teacher ?? "", record.course.location ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(key) }
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("课程总览").font(.title2.bold())
                        Text("\(model.table.name) · \(allGroups.count) 门课程")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("搜索课程、教师或教室", text: $query)
                            .textFieldStyle(.roundedBorder)
                        Text("显示全学期课程，不受当前周次限制；点按可查看和编辑。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if courses.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "暂无课程" : "未找到课程", systemImage: "books.vertical")
                }
                ForEach(courses) { group in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.name).font(.headline)
                            Text("开课：\(Self.weekText(group.weeks)) · 共 \(group.weeks.count) 周")
                                .font(.subheadline.weight(.medium))
                            ForEach(group.records) { stored in
                    Button { selection = DetailSelection(id: stored.course.id) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(GlassPalette.color(fromHex: stored.course.colorHex))
                                        .frame(width: 5, height: 25)
                                    Text("上课安排").font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                if let teacher = stored.course.teacher, !teacher.isEmpty {
                                    Label(teacher, systemImage: "person").font(.subheadline).foregroundStyle(.secondary)
                                }
                                if let room = stored.course.location, !room.isEmpty {
                                    Label(room, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                                }
                                let allWeeks = stored.rules.reduce(into: Set<Int>()) { $0.formUnion($1.weekSet) }
                                Text("开课：\(Self.weekText(allWeeks)) · 共 \(allWeeks.count) 周")
                                    .font(.subheadline.weight(.medium))
                                ForEach(stored.rules.sorted { lhs, rhs in
                                    if lhs.weekday != rhs.weekday { return lhs.weekday < rhs.weekday }
                                    return startMinute(lhs) < startMinute(rhs)
                                }) { rule in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(weekday(rule.weekday)) · \(timeText(rule))")
                                            .font(.subheadline.weight(.semibold))
                                        Text(Self.weekText(rule.weekSet)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                }
                                if let notes = stored.course.notes, !notes.isEmpty {
                                    Text(notes).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $selection) { selected in
            if let item = model.courses.first(where: { $0.course.id == selected.id }) {
                CourseDetailSheet(item: item).environmentObject(model)
            }
        }
    }

    private func weekday(_ value: Int) -> String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return (1...7).contains(value) ? names[value - 1] : "星期未设置"
    }

    private func startMinute(_ rule: MeetingRule) -> Int {
        (try? MeetingRuleValidator.resolve(rule, periods: model.periods).startMinuteOfDay) ?? 0
    }

    private func timeText(_ rule: MeetingRule) -> String {
        let clock: String
        if let time = try? MeetingRuleValidator.resolve(rule, periods: model.periods) {
            clock = "\(Period.text(from: time.startMinuteOfDay))–\(Period.text(from: time.endMinuteOfDay))"
        } else { clock = "时间配置需检查" }
        if rule.timingMode == .period, let start = rule.startPeriod, let end = rule.endPeriod {
            return "第 \(start)–\(end) 节 · \(clock)"
        }
        return "自定义时间 · \(clock)"
    }

    static func weekText(_ weeks: Set<Int>) -> String {
        let values = weeks.sorted()
        guard let first = values.first else { return "未设置周次" }
        var ranges: [String] = []
        var start = first
        var end = first
        for week in values.dropFirst() {
            if week == end + 1 { end = week }
            else {
                ranges.append(start == end ? "\(start)" : "\(start)–\(end)")
                start = week; end = week
            }
        }
        ranges.append(start == end ? "\(start)" : "\(start)–\(end)")
        return "第 \(ranges.joined(separator: "、")) 周"
    }
}
