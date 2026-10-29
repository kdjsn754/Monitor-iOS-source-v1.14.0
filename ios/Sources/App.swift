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
            if let phase = popupPhase {
                ConnectionPopupView(
                    phase: phase,
                    routerTitle: model.currentProfile?.title ?? "路由器",
                    routerSubtitle: model.currentProfile?.subtitle ?? "",
                    startedAt: connectStartedAt,
                    onDismiss: { dismissPopup() },
                    onRetry: { retryConnect() }
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
                if model.connected {
                    finishPopup()
                } else if let message = model.errorMessage {
                    popupPhase = .failed(message)
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

    private func retryConnect() {
        guard let profile = model.currentProfile,
              let password = KeychainStore.loadPassword(
                  account: KeychainStore.passwordAccount(for: profile)
              ) else {
            dismissPopup()
            return
        }
        connectStartedAt = Date()
        popupPhase = .connecting
        Task { await model.connect(profile: profile, password: password) }
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
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            OverviewView(selectedTab: $selection)
                .tabItem { Label("概览", systemImage: "square.grid.2x2") }
                .tag(0)
            ProxyView()
                .tabItem { Label("网络代理", systemImage: "globe") }
                .tag(1)
            SettingsView()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag(2)
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
                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.blue)
                        .frame(width: 54, height: 54)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .overlay {
                            Circle().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5)
                        }
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
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
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
