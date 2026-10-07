import SwiftUI
import WidgetKit

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let schedule: WidgetSchedule?
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, schedule: WidgetSchedule(tableName: "今日课表", lessons: [WidgetLesson(id: "sample", name: "通信原理", location: "汇文楼 · 566", start: .now.addingTimeInterval(1800), end: .now.addingTimeInterval(7200))], updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ScheduleEntry(date: .now, schedule: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        let schedule = WidgetSchedule.load()
        let cutoff = now.addingTimeInterval(24 * 3600)
        var dates = [now]
        dates += schedule?.lessons.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < cutoff } ?? []
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) { dates.append(midnight) }
        let entries = Set(dates).sorted().map { ScheduleEntry(date: $0, schedule: schedule) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct ScheduleWidgetView: View {
    let entry: ScheduleEntry
    @Environment(\.widgetFamily) private var family
    private var today: [WidgetLesson] {
        entry.schedule?.lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: entry.date) && $0.end > entry.date } ?? []
    }
    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text(today.first?.name ?? "今日暂无课程").font(.headline)
                if let lesson = today.first {
                    Text(lesson.start, style: .time)
                    Text(lesson.location ?? "流云课表").font(.caption)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("今日课表", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    Spacer()
                    Text(entry.date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                }
                if let schedule = entry.schedule {
                    Text(schedule.tableName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if today.isEmpty {
                        Spacer(minLength: 0)
                        Label("今日课程已结束", systemImage: "checkmark.circle").font(.headline)
                        Text("享受你的课余时间").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(today.prefix(family == .systemSmall ? 1 : family == .systemLarge ? 5 : 2))) { lesson in
                            HStack(alignment: .top, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(.blue).frame(width: 3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(lesson.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(lesson.location ?? "未设置教室").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    HStack(spacing: 3) {
                                        Text(lesson.start, style: .time)
                                        Text("–")
                                        Text(lesson.end, style: .time)
                                    }.font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if lesson.start <= entry.date {
                                    Text("上课中").font(.caption2).foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                    Text("打开流云课表").font(.headline)
                    Text("导入课表后即可显示课程").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.background, for: .widget)
        }
    }
}

@main
struct CourseTableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlowClassToday", provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("流云课表 · 今日课程")
        .description("查看今日剩余课程、上课时间和教室。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
