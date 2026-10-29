import SwiftUI

/// 设置页：顶部一张「路由器」卡把连接、切换、编辑全收进去，
/// 采集频率只留一行摘要，细项进二级页。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var confirmLogout = false
    @State private var editorRoute: ConnectionEditorRoute?
    @State private var showRouterWeb = false
    @State private var showRouters = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    routerCard
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
            .navigationTitle("设置")
            .toolbarBackground(.hidden, for: .navigationBar)
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
                        Text(model.currentProfile?.subtitle ?? "点下面的「新建连接」添加一台路由器")
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

                if model.profiles.count > 1 {
                    Divider().opacity(0.5)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showRouters.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .frame(width: 18)
                            Text("已保存 \(model.profiles.count) 个连接")
                                .font(.subheadline)
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showRouters ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showRouters {
                        VStack(spacing: 10) {
                            ForEach(model.profiles) { profile in
                                routerRow(profile)
                            }
                        }
                        .padding(.leading, 26)
                    }
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    Button {
                        openEditor(nil)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text("新建连接")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.blue)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 6)

                    Toggle(isOn: Binding(
                        get: { model.autoLogin },
                        set: { model.autoLogin = $0 }
                    )) {
                        Text("自动登录")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .fixedSize()
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(model.connected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(model.connected ? "已连接" : model.status)
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

    private func routerRow(_ profile: RouterProfile) -> some View {
        let isCurrent = profile.id == model.currentProfileID
        return HStack(spacing: 9) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(isCurrent ? Color.blue : Color(.tertiaryLabel))

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(profile.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Menu {
                Button {
                    Task { await model.switchTo(profile) }
                } label: {
                    Label("切换到这个连接", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    openEditor(profile)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    model.deleteProfile(profile)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent else { return }
            Task { await model.switchTo(profile) }
        }
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
                infoRow("版本", "1.18.0")
                infoRow("连接方式", "SSH 直连")
                infoRow("采集范围", "只采当前页面要用的数据")
                infoRow("数据去向", "只在本机与路由器之间")
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
                            if model.connected { dismiss() }
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
                        Text(error).font(.caption).foregroundStyle(.red)
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
