import SwiftUI

/// 设置页：顶部一张「路由器」卡把连接、切换、编辑全收进去，
/// 采集频率只留一行摘要，细项进二级页。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var confirmLogout = false
    @State private var editorRoute: ConnectionEditorRoute?
    @State private var showRouterWeb = false
    /// 哪一行的「…」是展开状态。行内操作条，不再是系统菜单浮层。
    @State private var expandedProfileID: UUID?
    /// 等待确认删除的连接。
    @State private var pendingDelete: RouterProfile?
    @State private var confirmDelete = false
    @State private var screen = ScreenInfo.Snapshot()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader("设置")
                    routerCard
                    connectionsCard
                    appearanceCard
                    pollingCard
                    aboutCard
                    dangerCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.clear)
            // 见 OverviewView：标题画在内容里，导航栏整条不要。
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editorRoute) { route in
                ConnectionEditorView(profile: route.profile)
                    .id(route.id)
            }
            .sheet(isPresented: $showRouterWeb) {
                if let url = model.routerWebURL {
                    PanelView(
                        url: url,
                        title: "路由器网页后台",
                        autoLoginUser: model.currentProfile?.user,
                        autoLoginPassword: model.currentPassword
                    )
                }
            }
            .confirmationDialog("退出后需要重新输入密码", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("断开并清除密码", role: .destructive) {
                    Task { await model.logout() }
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear { screen = ScreenInfo.current }
        }
    }

    // MARK: - 路由器（连接 + 切换 + 编辑，全在这一张卡里）

    private var routerCard: some View {
        SectionCard("路由器", icon: "wifi.router.fill") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 46, height: 46)
                        Image(systemName: "wifi.router.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.currentProfile?.title ?? "还没有连接")
                            .font(.headline)
                            .lineLimit(1)
                        Text(model.currentProfile?.subtitle
                             ?? "在下面「已保存连接」里添加一台路由器")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)
                    statusPill
                }

                HStack(spacing: 8) {
                    chip("重新连接", icon: "arrow.clockwise") {
                        Task { await model.manualRefresh() }
                    }
                    chip("网页后台", icon: "safari") { showRouterWeb = true }
                    chip("编辑", icon: "pencil") {
                        openEditor(model.currentProfile ?? model.profiles.first)
                    }
                }

                // 错误提示：8 秒自动消失，也能点叉立刻收掉。
                // 以前只在「下一次连接成功」时才清，连不上的红字会一直挂在设置页上，
                // 除非退出 App 重进——这就是截图里那行一直不走的报错。
                if let error = model.errorMessage {
                    ErrorBanner(text: error) { model.clearError() }
                }
            }
        }
    }

    // MARK: - 已保存连接（整块重做）

    private var connectionsCard: some View {
        SectionCard("已保存连接", icon: "list.bullet.rectangle") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text(model.profiles.isEmpty
                         ? "还没有保存过连接"
                         : "\(model.profiles.count) 个连接，点名称即可切换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 6)

                    Button {
                        expandedProfileID = nil
                        openEditor(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("新建")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.blue)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if model.profiles.isEmpty {
                    Text("点右上角「新建」填地址和密码，连接成功后会自动存一条。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 {
                                Divider().opacity(0.5).padding(.leading, 46)
                            }
                            connectionRow(profile)
                        }
                    }
                }

                Divider().opacity(0.5)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("自动登录")
                            .font(.subheadline)
                        Text(model.autoLogin
                             ? "启动 App 时自动连当前这个连接"
                             : "启动 App 后停在登录页，手动连接")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 6)
                    Toggle("", isOn: Binding(
                        get: { model.autoLogin },
                        set: { model.autoLogin = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
        .confirmationDialog(
            pendingDelete.map { "删除「\($0.title)」？" } ?? "删除这个连接？",
            isPresented: $confirmDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { profile in
            Button("删除连接", role: .destructive) {
                model.deleteProfile(profile)
                expandedProfileID = nil
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { profile in
            Text(profile.id == model.currentProfileID
                 ? "这是当前正在使用的连接，删除后会立即断开，需要重新填写密码。"
                 : "密码会一起从钥匙串里删除，重新添加时要再输一次。")
        }
    }

    /// 一行连接：左边点一下切换，右边「…」展开编辑 / 删除。
    private func connectionRow(_ profile: RouterProfile) -> some View {
        let isCurrent = profile.id == model.currentProfileID
        let expanded = expandedProfileID == profile.id
        let isConnecting = model.connecting
            && model.attemptTarget?.profile.id == profile.id

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    guard !isCurrent else { return }
                    expandedProfileID = nil
                    Task { await model.switchTo(profile) }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isCurrent ? Color.blue.opacity(0.14) : Color(.tertiarySystemFill))
                                .frame(width: 34, height: 34)
                            Image(systemName: isCurrent ? "wifi.router.fill" : "wifi.router")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(isCurrent ? Color.blue : Color.secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.title)
                                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(profile.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrent)

                if isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                } else if isCurrent {
                    Text("当前")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14), in: Capsule())
                        .foregroundStyle(.green)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedProfileID = expanded ? nil : profile.id
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(expanded ? Color.blue : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            expanded ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 9)

            if expanded {
                HStack(spacing: 8) {
                    rowAction("编辑", icon: "pencil", tint: .blue) {
                        expandedProfileID = nil
                        openEditor(profile)
                    }
                    rowAction("删除", icon: "trash", tint: .red) {
                        pendingDelete = profile
                        confirmDelete = true
                    }
                }
                .padding(.leading, 44)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
    }

    private func rowAction(_ title: String, icon: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.10), in: Capsule())
            .foregroundStyle(tint)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                // 正在连新连接时旧会话还在，别让胶囊显示「已连接」骗人。
                .fill(model.connecting ? Color.blue : (model.connected ? Color.green : Color.orange))
                .frame(width: 6, height: 6)
            Text(model.connecting ? "正在连接…" : (model.connected ? "已连接" : model.status))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func chip(_ title: String, icon: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func openEditor(_ profile: RouterProfile?) {
        editorRoute = profile.map(ConnectionEditorRoute.edit) ?? .new
    }


    // MARK: - 外观

    private struct ThemeOption: Identifiable {
        let id: String
        let title: String
    }

    private var themeOptions: [ThemeOption] {
        [ThemeOption(id: "system", title: "跟随系统"),
         ThemeOption(id: "light", title: "浅色"),
         ThemeOption(id: "dark", title: "深色")]
    }

    private var appearanceCard: some View {
        SectionCard("外观", icon: "circle.lefthalf.filled") {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(themeOptions) { option in
                        Button {
                            themeMode = option.id
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(themeMode == option.id ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    themeMode == option.id
                                        ? Color.blue.opacity(0.14)
                                        : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .foregroundStyle(themeMode == option.id ? Color.blue : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().opacity(0.5)

                NavigationLink {
                    ModuleSettingsView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("概览模块").font(.subheadline)
                            Text("显示或隐藏卡片、拖动排序")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 采集与刷新（摘要，细则进二级页）

    private var pollingCard: some View {
        SectionCard("采集与刷新", icon: "clock.arrow.circlepath") {
            NavigationLink {
                PollSettingsView()
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("每 \(Int(model.pollSeconds.rounded())) 秒")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(PollItem.allCases.count) 项数据，只采当前页面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        ForEach(AppPage.allCases) { page in
                            pageChip(page)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 一眼看出「哪一页采哪些数据」，比之前三档的格子干净得多。
    private func pageChip(_ page: AppPage) -> some View {
        let count = model.pollConfig.items(on: page).count
        let active = page == model.activePage && count > 0
        return HStack(spacing: 4) {
            Image(systemName: page.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(count > 0 ? "\(page.title) \(count) 项" : "\(page.title) 不采集")
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            active ? Color.blue.opacity(0.14) : Color(.tertiarySystemFill),
            in: Capsule()
        )
        .foregroundStyle(active ? Color.blue : Color.secondary)
    }

    // MARK: - 关于

    private var aboutCard: some View {
        SectionCard("关于", icon: "info.circle") {
            VStack(spacing: 9) {
                infoRow("版本", "1.22.0")
                infoRow("连接方式", "SSH 直连")
                infoRow("屏幕", screen.sizeText)
                infoRow("运行模式", screen.modeText,
                        color: screen.isLetterboxed ? .orange : .secondary)
                infoRow("构建 SDK", ScreenInfo.sdkName,
                        color: sdkIsOld ? .orange : .secondary)
                infoRow("采集范围", "只采当前页面要用的数据")
                infoRow("数据去向", "只在本机与路由器之间")

                if screen.isLetterboxed {
                    // 这条不是布局问题：系统不认识这块屏，就把界面整体放大到物理像素上，
                    // 上下自然留出黑边。App 内改不了窗口大小，只能换新 SDK 重打包。
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("系统把界面按 \(Int(screen.size.width.rounded()))×\(Int(screen.size.height.rounded())) 排版后放大，"
                             + "所以上下有黑边。请用 Xcode 16 及以上（iOS 18+ SDK）重新打包，"
                             + "界面上无法绕过。")
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 构建 SDK 低于 ios 26 就说明工具链太老，正是黑边的来源。
    private var sdkIsOld: Bool {
        let name = ScreenInfo.sdkName            // 形如 iphoneos26.0
        let rest = name.contains("iphoneos")
            ? String(name.dropFirst("iphoneos".count))
            : name
        let major = rest.split(separator: ".").first.flatMap { Int($0) } ?? 0
        return major > 0 && major < 26
    }

    private func infoRow(_ title: String, _ value: String,
                         color: Color = .secondary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var dangerCard: some View {
        VStack(spacing: 10) {
            Button {
                confirmLogout = true
            } label: {
                Text("断开并清除密码")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)

            Text("清空后需要重新输入密码才能连接，保存的监控设置不会丢。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}

// MARK: - 卡片容器

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            content
        }
        .glassCard()
    }
}

// MARK: - 连接编辑

/// 编辑器要打开哪一种：新建，还是编辑某一个已保存的连接。
///
/// 之前用 `showEditor` 布尔 + 单独的 `editProfile` 两个状态驱动 `.sheet(isPresented:)`，
/// 点「编辑」时 sheet 的内容闭包可能拿到还没写入的旧值（nil），于是第一次点开
/// 总是「新建连接」。改成用 item 驱动，数据本身决定弹窗，就不会再错位。
private enum ConnectionEditorRoute: Identifiable {
    case new
    case edit(RouterProfile)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let profile): return profile.id.uuidString
        }
    }

    var profile: RouterProfile? {
        switch self {
        case .new: return nil
        case .edit(let profile): return profile
        }
    }
}

private struct ConnectionEditorView: View {
    let profile: RouterProfile?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var host: String
    @State private var port: String
    @State private var webPort: String
    @State private var user: String
    @State private var password: String

    init(profile: RouterProfile?) {
        self.profile = profile
        _label = State(initialValue: profile?.label ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: String(profile?.port ?? 22))
        _webPort = State(initialValue: String(profile?.webPortValue ?? 80))
        _user = State(initialValue: profile?.user ?? "root")
        _password = State(initialValue: profile.flatMap {
            KeychainStore.loadPassword(account: KeychainStore.passwordAccount(for: $0))
        } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接信息") {
                    TextField("连接名称（可选）", text: $label)
                    TextField("路由器地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("SSH 端口", text: $port)
                        .keyboardType(.numberPad)
                    TextField("网页后台端口（LuCI）", text: $webPort)
                        .keyboardType(.numberPad)
                    TextField("用户名", text: $user)
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $password)
                }

                Section {
                    Button {
                        Task {
                            let sshPort = Int(port) ?? 22
                            let web = Int(webPort) ?? 80
                            if let profile {
                                await model.updateProfile(
                                    profile,
                                    host: host,
                                    port: sshPort,
                                    user: user,
                                    password: password,
                                    label: label,
                                    webPort: web
                                )
                            } else {
                                await model.saveNewProfile(
                                    host: host,
                                    port: sshPort,
                                    user: user,
                                    password: password,
                                    label: label,
                                    webPort: web
                                )
                            }
                            // 连上了就收起表单；失败则留在这里让用户改地址，
                            // 上一台连接已经自动恢复，关掉也不会掉线。
                            if model.connected && !model.lastConnectFailed { dismiss() }
                        }
                    } label: {
                        HStack {
                            if model.connecting { ProgressView() }
                            Text(model.connecting ? "正在连接…" : "连接并保存")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(model.connecting || host.isEmpty || password.isEmpty)
                }

                if let error = model.errorMessage {
                    Section {
                        ErrorBanner(text: error) { model.clearError() }
                    }
                }
            }
            .navigationTitle(profile == nil ? "新建连接" : "编辑连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
