import SwiftUI
import CourseTableCore

/// Weekly timetable. A layered layout: a glass header (table name + week),
/// a horizontal week selector with a water-drop indicator, then the grid.
///
/// Performance: the grid and the "which weeks have class" set are computed in
/// ONE pass over the courses per body evaluation (see `WeekSnapshot`), instead
/// of re-scanning every course for every cell and every week chip.
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
        let snapshot = WeekSnapshot(
            courses: model.courses,
            periods: model.periods,
            weekdayCount: model.weekdayCount,
            currentWeek: model.currentWeek,
            showOutside: model.table.showCoursesOutsideSelectedWeek
        )

        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                weekSelector(activeWeeks: snapshot.activeWeeks)
                grid(snapshot: snapshot)
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
                            .background(Circle().fill(GlassPalette.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    GlassActionButton(title: "新建课程", systemImage: "plus") {
                        editingCourse = nil
                        showingEditor = true
                    }
                    GlassActionButton(title: "回到本周", systemImage: "arrow.uturn.backward", tint: weekdayTodayTint) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { model.resetWeekToToday() }
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

    private func weekSelector(activeWeeks: Set<Int>) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...model.table.totalWeeks, id: \.self) { week in
                        weekChip(week, hasCourses: activeWeeks.contains(week))
                            .id(week)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(model.currentWeek, anchor: .center) }
            .onChange(of: model.currentWeek) { _, newValue in
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
    }

    private func weekChip(_ week: Int, hasCourses: Bool) -> some View {
        let isSelected = week == model.currentWeek
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                model.setCurrentWeek(week)
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(week)").font(.system(size: 16, weight: .bold, design: .rounded))
                Circle()
                    .fill(hasCourses ? (isSelected ? Color.white : GlassPalette.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
            .frame(width: 46, height: 52)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(GlassPalette.accent.gradient)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                        .shadow(color: GlassPalette.accent.opacity(0.3), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "weekDrop", in: weekNamespace)
                } else {
                    // Solid translucent fill instead of a live material blur:
                    // 17 materials in a scrolling row is a large GPU cost.
                    Capsule(style: .continuous).fill(Color.white.opacity(0.28))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Grid

    private func grid(snapshot: WeekSnapshot) -> some View {
        GlassCard(cornerRadius: 24, padding: 12) {
            VStack(spacing: 6) {
                dayHeaderRow
                ForEach(Array(model.periods.enumerated()), id: \.element.id) { index, period in
                    periodRow(period, rowIndex: index, snapshot: snapshot)
                }
            }
        }
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 42, height: 1)
            ForEach(0..<model.weekdayCount, id: \.self) { index in
                Text("周\(dayNames[index])")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func periodRow(_ period: Period, rowIndex: Int, snapshot: WeekSnapshot) -> some View {
        HStack(spacing: 6) {
            VStack(spacing: 1) {
                Text("\(period.index)").font(.system(size: 13, weight: .bold, design: .rounded))
                Text(Period.text(from: period.startMinuteOfDay))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42)

            ForEach(0..<model.weekdayCount, id: \.self) { column in
                cell(snapshot.cell(row: rowIndex, column: column))
            }
        }
    }

    @ViewBuilder
    private func cell(_ match: WeekSnapshot.Cell?) -> some View {
        if let match {
            Button {
                selectedCourseID = match.courseID
            } label: {
                cellContent(match)
            }
            .buttonStyle(.plain)
        } else {
            cellContent(nil)
        }
    }

    @ViewBuilder
    private func cellContent(_ match: WeekSnapshot.Cell?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if let match {
            shape
                .fill(match.color.gradient)
                .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.name).font(.system(size: 10, weight: .semibold)).lineLimit(3)
                        if let location = match.location {
                            Text(location).font(.system(size: 8)).opacity(0.85).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(5)
                }
                .frame(maxWidth: .infinity, minHeight: 62)
                .opacity(match.isActiveWeek ? 1 : 0.35)
        } else {
            shape
                .fill(Color.primary.opacity(0.04))
                .frame(maxWidth: .infinity, minHeight: 62)
        }
    }

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
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.75))
                    )
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
}

// MARK: - Weekly snapshot (precomputed once per body)

/// Flattened, ready-to-render view of the active week. Built in a single pass
/// so the grid never rescans the course list per cell.
struct WeekSnapshot {
    struct Cell {
        let courseID: UUID
        let name: String
        let location: String?
        let color: Color
        let isActiveWeek: Bool
    }

    /// rows[periodRow][column]; nil means an empty cell.
    private let rows: [[Cell?]]
    let activeWeeks: Set<Int>

    init(courses: [StoredCourse], periods: [Period], weekdayCount: Int, currentWeek: Int, showOutside: Bool) {
        var rows = Array(repeating: Array<Cell?>(repeating: nil, count: weekdayCount), count: periods.count)
        var activeWeeks = Set<Int>()
        var periodRowIndex: [Int: Int] = [:]
        for (row, period) in periods.enumerated() { periodRowIndex[period.index] = row }

        for stored in courses {
            let color = GlassPalette.color(fromHex: stored.course.colorHex)
            let location = (stored.course.location?.isEmpty == false) ? stored.course.location : nil
            for rule in stored.rules where rule.timingMode == .period {
                guard let start = rule.startPeriod, let end = rule.endPeriod else { continue }
                let column = rule.weekday - 1
                guard column >= 0, column < weekdayCount else { continue }
                for week in rule.weekSet { activeWeeks.insert(week) }

                let isActive = rule.weekSet.contains(currentWeek)
                guard isActive || showOutside else { continue }
                guard start <= end else { continue }
                for index in start...end {
                    guard let row = periodRowIndex[index] else { continue }
                    let existing = rows[row][column]
                    // Prefer an active-week course over a dimmed one.
                    if existing == nil || (isActive && existing?.isActiveWeek == false) {
                        rows[row][column] = Cell(
                            courseID: stored.course.id,
                            name: stored.course.name,
                            location: location,
                            color: color,
                            isActiveWeek: isActive
                        )
                    }
                }
            }
        }
        self.rows = rows
        self.activeWeeks = activeWeeks
    }

    func cell(row: Int, column: Int) -> Cell? {
        guard rows.indices.contains(row) else { return nil }
        let columns = rows[row]
        guard columns.indices.contains(column) else { return nil }
        return columns[column]
    }
}

// MARK: - Selection wrapper for `.sheet(item:)`

struct DetailSelection: Identifiable {
    let id: UUID
}
