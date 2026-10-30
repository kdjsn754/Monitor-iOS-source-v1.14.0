import SwiftUI

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
        // 用 safeAreaInset 而不是 overlay：这样每页的 ScrollView 会自动把
        // 底部留出栏的高度，内容不会被栏压住，也不会在滑到底时钻到栏底下。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selection: $selection)
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
/// 三枚图标都是「空心 / 实心」一对：没选中画空心，选中画实心并转成主色。
/// 不给选中项铺浅色胶囊——那层淡蓝底和页面里的卡片打架，实心图标本身就够表明状态了。
struct AppTabBar: View {
    @Binding var selection: Int

    /// 顺序即标签顺序：图标、实心底图、标题。
    private let items: [(icon: String, filled: String, title: String)] = [
        ("square.grid.2x2", "square.grid.2x2.fill", "概览"),
        ("shield", "shield.fill", "代理"),
        ("gearshape", "gearshape.fill", "设置")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemView(index: index, item: item)
            }
        }
        .padding(5)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.45), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 44)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .animation(.easeOut(duration: 0.16), value: selection)
    }

    private func itemView(index: Int, item: (icon: String, filled: String, title: String)) -> some View {
        let isSelected = selection == index
        return Button {
            guard !isSelected else { return }
            selection = index
        } label: {
            VStack(spacing: 3) {
                // 统一框高：三枚符号的自带高度不一样（gearshape 比 shield 略高），
                // 不框住的话选中切换时文字会上下抖一两个点。
                Image(systemName: isSelected ? item.filled : item.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(height: 21)
                Text(item.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
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
