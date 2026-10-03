import SwiftUI
import CourseTableCore

/// Weekly timetable. A layered layout: a glass header (table name + week),
/// a horizontal week selector with a water-drop indicator, then the grid.
struct ScheduleScreen: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var weekNamespace

    @State private var selectedCourseID: UUID?
    @State private var showingEditor = false
    @State private var editingCourse: StoredCourse?
    @State private var showingTableManager = false
    private var detailSelection: Binding<DetailSelection?> {
        Binding(
            get: { selectedCourseID.map(DetailSelection.init) },
            set: { selectedCourseID = $0?.id }
        )
    }

    private let dayNames = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                weekSelector
                grid
                customSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingEditor) {
            CourseEditorSheet(existing: editingCourse)
                .environmentObject(model)
        }
        .sheet(item: detailSelection) { selection in
            if let stored = model.courses.first(where: { $0.course.id == selection.id }) {
                CourseDetailSheet(item: stored)
                    .environmentObject(model)
            }
        }
        .sheet(isPresented: $showingTableManager) {
            TableManagerSheet()
                .environmentObject(model)
        }
    }

    // MARK: Header

    private var header: some View {
        GlassCard(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.table.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(weekSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showingTableManager = true } label: {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GlassPalette.accent)
                            .padding(10)
                            .liuyunGlass(.tinted(GlassPalette.accent.opacity(0.5)), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    GlassActionButton(title: "新建课程", systemImage: "plus") {
                        editingCourse = nil
                        showingEditor = true
                    }
                    GlassActionButton(title: "回到本周", systemImage: "arrow.uturn.backward", tint: weekdayTodayTint) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.resetWeekToToday() }
                    }
                }
            }
        }
    }

    private var weekdayTodayTint: Color { Color(red: 0.30, green: 0.68, blue: 0.45) }

    private var weekSubtitle: String {
        let current = model.currentWeek
        let native = SemesterCalendar.naturalWeek(semesterStart: model.table.semesterStartDate, totalWeeks: model.table.totalWeeks)
        let suffix = current == native ? " · 本周" : ""
        return "第 \(current) 周 · 共 \(model.table.totalWeeks) 周\(suffix)"
    }

    // MARK: Week selector

    private var weekSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...model.table.totalWeeks, id: \.self) { week in
                        weekChip(week)
                            .id(week)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(model.currentWeek, anchor: .center) }
            .onChange(of: model.currentWeek) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func weekChip(_ week: Int) -> some View {
        let isSelected = week == model.currentWeek
        let isActiveCourseWeek = !coursesIn(week: week).isEmpty
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                model.setCurrentWeek(week)
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(week)").font(.system(size: 16, weight: .bold, design: .rounded))
                Circle()
                    .fill(isActiveCourseWeek ? (isSelected ? Color.white : GlassPalette.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
            .frame(width: 46, height: 52)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [GlassPalette.accent, GlassPalette.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                        .shadow(color: GlassPalette.accent.opacity(0.35), radius: 10, y: 4)
                        .matchedGeometryEffect(id: "weekDrop", in: weekNamespace)
                } else {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Grid

    private var grid: some View {
        GlassCard(cornerRadius: 24, padding: 12) {
            VStack(spacing: 6) {
                dayHeaderRow
                ForEach(model.periods) { period in
                    periodRow(period)
                }
            }
        }
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 6) {
            Text("").frame(width: 42)
            ForEach(0..<model.weekdayCount, id: \.self) { index in
                Text("周\(dayNames[index])")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func periodRow(_ period: Period) -> some View {
        HStack(spacing: 6) {
            VStack(spacing: 1) {
                Text("\(period.index)").font(.system(size: 13, weight: .bold, design: .rounded))
                Text(Period.text(from: period.startMinuteOfDay))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42)

            ForEach(1...model.weekdayCount, id: \.self) { weekday in
                cell(weekday: weekday, period: period)
            }
        }
    }

    private func cell(weekday: Int, period: Period) -> some View {
        let match = courseCell(weekday: weekday, period: period)
        return Group {
            if let match {
                Button {
                    selectedCourseID = match.stored.course.id
                } label: {
                    cellContent(match)
                }
                .buttonStyle(.plain)
            } else {
                cellContent(nil)
            }
        }
    }

    @ViewBuilder
    private func cellContent(_ match: CellMatch?) -> some View {
        let isCurrentWeekCourse = match?.isActiveWeek ?? true
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(match == nil ? AnyShapeStyle(Color.primary.opacity(0.04)) : AnyShapeStyle(tint(for: match!).gradient))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(match == nil ? 0 : 0.35), lineWidth: 0.75)
            )
            .overlay(alignment: .topLeading) {
                if let match {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.stored.course.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(3)
                        if let location = match.stored.course.location, !location.isEmpty {
                            Text(location).font(.system(size: 8)).opacity(0.8).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .opacity(isCurrentWeekCourse ? 1 : 0.35)
    }

    private func tint(for match: CellMatch) -> Color { GlassPalette.color(fromHex: match.stored.course.colorHex) }

    // MARK: Custom-time courses

    @ViewBuilder
    private var customSection: some View {
        let custom = model.courses.filter { $0.rules.contains { $0.timingMode == .custom } }
        if !custom.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("不规则时间课程")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.leading, 4)
                ForEach(custom) { item in
                    Button { selectedCourseID = item.course.id } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(GlassPalette.color(fromHex: item.course.colorHex).gradient)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.course.name).font(.system(size: 15, weight: .semibold))
                                Text(customSubtitle(item)).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                    .liuyunGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private func customSubtitle(_ item: StoredCourse) -> String {
        guard let rule = item.rules.first(where: { $0.timingMode == .custom }) else { return "" }
        let start = Period.text(from: rule.customStartMinute ?? 0)
        let end = Period.text(from: rule.customEndMinute ?? 0)
        return "周\(dayNames[rule.weekday - 1]) · \(start)–\(end)"
    }

    // MARK: Lookup

    private struct CellMatch {
        let stored: StoredCourse
        let rule: MeetingRule
        let isActiveWeek: Bool
    }

    private func courseCell(weekday: Int, period: Period) -> CellMatch? {
        let week = model.currentWeek
        for stored in model.courses {
            for rule in stored.rules where rule.timingMode == .period {
                guard rule.weekday == weekday,
                      let start = rule.startPeriod, let end = rule.endPeriod,
                      period.index >= start, period.index <= end else { continue }
                // Prefer a course that is active this week; otherwise show dimmed.
                if rule.weekSet.contains(week) {
                    return CellMatch(stored: stored, rule: rule, isActiveWeek: true)
                }
            }
        }
        guard model.table.showCoursesOutsideSelectedWeek else { return nil }
        for stored in model.courses {
            for rule in stored.rules where rule.timingMode == .period {
                guard rule.weekday == weekday,
                      let start = rule.startPeriod, let end = rule.endPeriod,
                      period.index >= start, period.index <= end else { continue }
                return CellMatch(stored: stored, rule: rule, isActiveWeek: false)
            }
        }
        return nil
    }

    private func coursesIn(week: Int) -> [StoredCourse] {
        model.courses.filter { stored in
            stored.rules.contains { $0.weekSet.contains(week) }
        }
    }
}

// MARK: - Selection wrapper for `.sheet(item:)`

struct DetailSelection: Identifiable {
    let id: UUID
}
