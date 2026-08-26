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
        ContentUnavailableView(
            "还没有课程表",
            systemImage: "calendar.badge.plus",
            description: Text("可以手动创建、扫描图片，或从文件导入。")
        )
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
