import SwiftUI
import CourseTableCore

/// App shell: an atmospheric background, a content layer, and a floating
/// liquid-glass tab bar whose "water drop" indicator morphs between items.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var tabNamespace
    @State private var tab: AppTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let screen = arguments.first(where: { $0.hasPrefix("--screen=") })?.split(separator: "=").last.map(String.init)
        _tab = State(initialValue: AppTab(screen: screen))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GlassBackground()

            ZStack {
                ScheduleScreen()
                    .opacity(tab == .schedule ? 1 : 0)
                    .allowsHitTesting(tab == .schedule)
                    .accessibilityHidden(tab != .schedule)
                ImportScreen()
                    .opacity(tab == .importTab ? 1 : 0)
                    .allowsHitTesting(tab == .importTab)
                    .accessibilityHidden(tab != .importTab)
                CourseOverviewScreen()
                    .opacity(tab == .courses ? 1 : 0)
                    .allowsHitTesting(tab == .courses)
                    .accessibilityHidden(tab != .courses)
                SettingsScreen()
                    .opacity(tab == .settings ? 1 : 0)
                    .allowsHitTesting(tab == .settings)
                    .accessibilityHidden(tab != .settings)
            }
            .animation(nil, value: tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GlassTabBar(selection: $tab, namespace: tabNamespace)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
        .alert("课程数据需要处理", isPresented: Binding(
            get: { model.storageMessage != nil },
            set: { if !$0 { model.storageMessage = nil } }
        )) {
            if model.storageLocked {
                Button("备份原文件并新建", role: .destructive) { model.recoverStorage() }
            }
            Button("暂不处理", role: .cancel) {}
        } message: {
            Text(model.storageMessage ?? "未知存储错误")
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case schedule
    case courses
    case importTab = "import"
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "课表"
        case .courses: return "课程"
        case .importTab: return "导入"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .schedule: return "calendar"
        case .courses: return "list.bullet.rectangle"
        case .importTab: return "tray.and.arrow.down"
        case .settings: return "gearshape"
        }
    }

    init(screen: String?) {
        switch screen {
        case "import": self = .importTab
        case "courses": self = .courses
        case "settings": self = .settings
        default: self = .schedule
        }
    }
}

// MARK: - Floating glass tab bar

struct GlassTabBar: View {
    @Binding var selection: AppTab
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        // Always show the icon; express selection with a fill
                        // variant (safe no-op if the symbol has none) and colour.
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolVariant(selection == tab ? .fill : .none)
                        Text(tab.title).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background {
                        if selection == tab {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [GlassPalette.accent, GlassPalette.accent.opacity(0.72)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                                .shadow(color: GlassPalette.accent.opacity(0.35), radius: 12, y: 5)
                                .matchedGeometryEffect(id: "tabDrop", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .liuyunGlass(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
    }
}
