import SwiftUI
import CourseTableCore

@main
struct CourseTableApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
private struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                SchedulePlaceholderView()
                    .navigationTitle("课程表")
            }
            .tabItem { Label("课表", systemImage: "calendar") }

            NavigationStack {
                ImportPlaceholderView()
                    .navigationTitle("图片导入")
            }
            .tabItem { Label("导入", systemImage: "viewfinder") }

            NavigationStack {
                SettingsPlaceholderView()
                    .navigationTitle("设置")
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

private struct SchedulePlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("大三上").font(.title2.bold())
                        Text("第 8 周 · 2026年10月19日—25日")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("今天") { }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                HStack(spacing: 0) {
                    Text("").frame(width: 34)
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                        Text(day).font(.caption.bold()).frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.secondary)

                let slots = [("1", "08:00"), ("2", "10:00"), ("3", "13:30"), ("4", "15:30"), ("5", "18:30")]
                ForEach(Array(slots.enumerated()), id: \.offset) { row, slot in
                    HStack(spacing: 4) {
                        VStack(spacing: 1) {
                            Text(slot.0).font(.caption.bold())
                            Text(slot.1).font(.system(size: 8)).foregroundStyle(.secondary)
                        }.frame(width: 34)
                        ForEach(0..<7, id: \.self) { column in
                            ScheduleCell(title: sampleTitle(row: row, column: column), color: sampleColor(row: row, column: column))
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func sampleTitle(row: Int, column: Int) -> String? {
        switch (row, column) { case (0, 0): return "高等数学"; case (1, 2): return "英语"; case (2, 1): return "数据结构"; case (3, 4): return "体育"; case (4, 3): return "实验（不规则）"; default: return nil }
    }
    private func sampleColor(row: Int, column: Int) -> Color {
        switch (row, column) { case (0, 0): return .blue; case (1, 2): return .orange; case (2, 1): return .green; case (3, 4): return .purple; case (4, 3): return .pink; default: return .clear }
    }
}

private struct ScheduleCell: View {
    let title: String?
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(title == nil ? 0.05 : 0.18))
            .overlay(alignment: .topLeading) {
                if let title { Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(color).padding(5) }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
    }
}

private struct ImportPlaceholderView: View {
    var body: some View {
        List {
            Label("相机扫描课程表", systemImage: "camera")
            Label("从相册选择", systemImage: "photo")
            Text("识别结果会先进入可编辑草稿，确认后才创建课程表。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        List {
            Section("课程时间") {
                Text("常规课程：按节次")
                Text("不规则课程：单独填写开始和结束时间")
            }
            Section("日历") {
                Text("导入 Apple 日历与课程提醒")
            }
        }
    }
}
