import SwiftUI
import UIKit

@main
@MainActor
struct OpenWrtMonitorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("themeMode") private var themeMode = "system"

    // 连接弹窗：只在“发起连接”时出现，成功后自动收起，失败给重试。
    @State private var popupPhase: ConnectionPhase?
    @State private var connectStartedAt: Date?

    var body: some View {
        ZStack {
            AppBackground()
            Group {
                if model.connected {
                    MainTabs()
                } else {
                    LoginView()
                }
            }
            // 连接弹窗盖着的时候，底下的页面一律不吃点击。
            // 否则能在「正在连接」的弹窗背后把路由器的「…」菜单点开，两个浮层叠在一起。
            .allowsHitTesting(popupPhase == nil
                              && !model.reconnecting
                              && model.activityTitle == nil)
            if let phase = popupPhase {
                ConnectionPopupView(
                    phase: phase,
                    routerTitle: popupTarget?.title ?? "路由器",
                    routerSubtitle: popupTarget?.subtitle ?? "",
                    startedAt: connectStartedAt,
                    onDismiss: { dismissPopup() },
                    onRetry: { retryConnect() },
                    onCancel: { cancelConnect() }
                )
                .zIndex(2)
            }
            if model.reconnecting || model.activityTitle != nil {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.blue)
                        Text(model.reconnecting
                             ? "正在恢复连接"
                             : (model.activityTitle ?? "正在处理"))
                            .font(.headline)
                        Text(model.reconnecting
                             ? "正在重新建立 SSH 会话…"
                             : (model.activitySubtitle ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 230)
                    .padding(.vertical, 22)
                    .glassCard(padding: 0, cornerRadius: 22)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(colorScheme)
        .tint(.blue)
        .animation(.easeInOut(duration: 0.2), value: popupPhase)
        .onChange(of: model.connecting) { _, isConnecting in
            if isConnecting {
                connectStartedAt = Date()
                popupPhase = .connecting
            } else if popupPhase?.isConnecting == true {
                // 先看「这次是否失败」：失败后上一台连接可能已经被恢复（connected 为真），
                // 那就不能按成功来演。
                if model.lastConnectFailed, let message = model.errorMessage {
                    popupPhase = .failed(message)
                } else if model.connected {
                    finishPopup()
                } else {
                    dismissPopup()
                }
            }
        }
        .onChange(of: model.connected) { _, isConnected in
            if isConnected, popupPhase?.isConnecting == true {
                finishPopup()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.resumeAfterForeground() }
            case .background:
                // 退到后台立刻停掉轮询，别让路由器替一个看不见的界面干活。
                model.pausePolling()
            default:
                break
            }
        }
    }

    /// 弹窗上要显示的「这次在连哪一台」。
    /// 失败回滚之后 currentProfile 已经退回上一台，所以优先用这次尝试的目标。
    private var popupTarget: RouterProfile? {
        model.attemptTarget?.profile ?? model.currentProfile
    }

    /// 连上了：先让弹窗停一下显示成功，再自己收起来。
    private func finishPopup() {
        popupPhase = .connected
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if popupPhase?.isConnected == true {
                withAnimation { popupPhase = nil }
            }
        }
    }

    private func dismissPopup() {
        withAnimation { popupPhase = nil }
        connectStartedAt = nil
    }

    /// 用户主动停止：先收弹窗再让 model 收尾，
    /// 这样 connected 回落时不会被上面的 onChange 误判成「连接成功」。
    private func cancelConnect() {
        withAnimation { popupPhase = nil }
        connectStartedAt = nil
        model.cancelConnect()
    }

    private func retryConnect() {
        // 用这次尝试的目标重试。失败回滚后 currentProfile 已经变回上一台，
        // 用它重试会莫名其妙去连另一台路由器。
        guard let target = model.attemptTarget else {
            dismissPopup()
            return
        }
        connectStartedAt = Date()
        popupPhase = .connecting
        Task { await model.connect(profile: target.profile, password: target.password) }
    }

    private var colorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = 0

    var body: some View {
        // 系统 TabView 只当作「页面容器」用：它负责保留每一页的滚动位置和弹窗状态，
        // 但底下那条栏由我们自绘（见 AppTabBar），这样才能做到
        // 「选中后图标变实心」—— 系统的 .tabItem 只有一种图，给不了选中态。
        TabView(selection: $selection) {
            OverviewView()
                .tag(0)
                .toolbar(.hidden, for: .tabBar)
            ProxyView()
                .tag(1)
                .toolbar(.hidden, for: .tabBar)
            SettingsView()
                .tag(2)
                .toolbar(.hidden, for: .tabBar)
        }
        // 底栏用 overlay 浮在内容之上：滚动时卡片会滑到栏底下被玻璃模糊掉，
        // 既能看到「下面还有内容」又不会被硬切断——这正是液态玻璃想要的效果。
        // 「最后一行不被栏压住」由每一页 ScrollView 自己的 `.safeAreaInset(edge: .bottom)`
        // 留白来保证，不依赖 TabView 的 inset 向下传播（实测部分 iOS 版本上传不进子页，
        // 会导致最底行被盖住，正是之前截图里看到的现象）。
        .overlay(alignment: .bottom) {
            AppTabBar(selection: $selection)
                .padding(.bottom, AppTabBar.bottomPadding)
        }
        // 采集跟着页面走：切到哪一页就只采那一页要用的数据，设置页完全不采。
        .onChange(of: selection) { _, value in
            model.setActivePage(AppPage(tab: value))
        }
        .onAppear {
            model.setActivePage(AppPage(tab: selection))
        }
    }
}

/// 自绘的底部导航栏。
///
/// 尺寸是按另一款系统级 App 的底栏截图量出来的（402pt 宽的机器上）：
/// 胶囊宽 274、高 62、离屏幕物理底边 21、内边距 4、三格等分；
/// 选中项铺一块 `systemFill` 胶囊，图标换实心、文字加粗——
/// 也就是系统 App 那种「只有一个选中项有底色」的写法，不再给图标上蓝色。
struct AppTabBar: View {    @Binding var selection: Int

    private enum Metrics {
        static let width: CGFloat = 274      // 胶囊总宽
        static let height: CGFloat = 62      // 胶囊总高
        static let inset: CGFloat = 4        // 胶囊内边距（选中胶囊离外框的距离）
        static let icon: CGFloat = 26        // 图标框（墨迹约 23，和系统底栏的图标一样大）
        static let label: CGFloat = 10       // 标签字号
        static let bottomGap: CGFloat = 21   // 栏底到屏幕物理底边
    }

    private let items: [(glyph: TabGlyphKind, title: String)] = [
        (.overview, "概览"),
        (.proxy, "代理"),
        (.settings, "设置")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemView(index: index, item: item)
            }
        }
        .padding(Metrics.inset)
        .frame(width: Metrics.width, height: Metrics.height)
        .modifier(TabBarGlass())
        .animation(.easeOut(duration: 0.16), value: selection)
    }

    private func itemView(index: Int, item: (glyph: TabGlyphKind, title: String)) -> some View {
        let isSelected = selection == index
        return Button {
            guard !isSelected else { return }
            selection = index
        } label: {
            VStack(spacing: 4) {
                // 图标和文字都用「具体的黑/白」而不是 `.primary`：玻璃底栏会把
                // 层级色降级渲染，选中项的实心图标曾经因此变成 tertiary 那一档的灰。
                TabGlyph(kind: item.glyph,
                         filled: isSelected,
                         tint: Color(uiColor: .label))
                    .frame(width: Metrics.icon, height: Metrics.icon)
                Text(item.title)
                    .font(.system(size: Metrics.label, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(Color(uiColor: .label))
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.height - Metrics.inset * 2)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color(.systemFill))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TabBarButtonStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 底栏按钮：按下时只轻微缩小，**不变淡**。
///
/// `.plain` 在按下时会把 label 整体压低不透明度，黑色图标于是变成灰的——
/// 底栏图标本来就小，一淡就像「没选中」或「被禁用」，切换的那一下观感很差。
private struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension AppTabBar {
    /// home indicator 那一截的高度（没有的机型为 0）。
    @MainActor
    private static var safeBottomInset: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.bottom ?? 34
    }

    /// 让栏底落在离屏幕物理底边 21pt 的位置。
    ///
    /// 底栏是挂在 TabView 下沿的 overlay 上的，而 TabView 的边界是**安全区**边界
    /// （底部让出了 home indicator 那 34pt）。所以要往下压 34-21=13pt，
    /// 这里算成内边距就是负数；没有 home indicator 的机型（inset 为 0）会自然退回 21。
    @MainActor
    static var bottomPadding: CGFloat {
        Metrics.bottomGap - safeBottomInset
    }

    /// 各页 ScrollView 底部要给底栏留的高度。
    ///
    /// = 栏高 + 栏底到屏幕底的距离 + 6 的一点余量 - 页面自己已经让出的安全区。
    /// 写死 84 的话，栏往下压了 23pt 之后底部会多出一大块空白。
    @MainActor
    static var contentBottomInset: CGFloat {
        Metrics.height + 6 + bottomPadding
    }
}

/// 导航栏的玻璃底：iOS 26 用系统「液态玻璃」(`glassEffect`)，
/// 胶囊会实时把背后的页面渐变、卡片折进玻璃里，滑动时内容滑到栏下会被自然模糊，
/// 既看得到「底下还有东西」，又不会被硬生生切断。低于 iOS 26 退回 `ultraThinMaterial`
/// 毛玻璃 + 一圈细边，照样是半透明的悬浮胶囊。
struct TabBarGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.45), lineWidth: 0.5)
                        }
                }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var host = ""
    @State private var port = "22"
    @State private var user = "root"
    @State private var password = ""
    @State private var didAutoConnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    // 和桌面图标同一枚线稿（见 RouterGlyph），不再用 SF Symbols 的路由器。
                    RouterGlyph(size: 34)
                        .frame(width: 54, height: 54)
                        .softTile(.blue, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenWrt 监控")
                            .font(.title2.bold())
                        Text("SSH 直连 · 数据仅在本机处理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("路由器地址").font(.caption).foregroundStyle(.secondary)
                    TextField("192.168.1.1", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SSH 端口").font(.caption).foregroundStyle(.secondary)
                        TextField("22", text: $port)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("用户名").font(.caption).foregroundStyle(.secondary)
                        TextField("root", text: $user)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("密码").font(.caption).foregroundStyle(.secondary)
                    SecureField("路由器 root 密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("自动登录", isOn: Binding(
                    get: { model.autoLogin },
                    set: { model.autoLogin = $0 }
                ))

                Button {
                    LocalNetworkPermission.shared.request()
                    Task {
                        await model.connect(
                            host: host,
                            port: Int(port) ?? 22,
                            user: user,
                            password: password
                        )
                    }
                } label: {
                    HStack {
                        if model.connecting { ProgressView().tint(.white) }
                        Text(model.connecting ? "正在连接…" : "连接路由器")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(GlassProminentButtonStyle())
                .disabled(model.connecting)
                .opacity(model.connecting ? 0.6 : 1)

                if let error = model.errorMessage {
                    ErrorBanner(text: error) { model.clearError() }
                }

                Text("请确认路由器已启用 SSH，并允许局域网访问。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
            .glassCard(padding: 20, cornerRadius: 28)
        }
        .background(Color.clear)
        .task {
            guard !didAutoConnect else { return }
            didAutoConnect = true
            LocalNetworkPermission.shared.request()
            if let profile = model.currentProfile {
                host = profile.host
                port = String(profile.port)
                user = profile.user
                password = KeychainStore.loadPassword(
                    account: KeychainStore.passwordAccount(for: profile)
                ) ?? ""
            }
            await model.autoConnectIfPossible()
        }
    }
}
