import SwiftUI

/// 设置页：卡片式布局，一块一张卡，不再用 Form 的长列表。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var confirmLogout = false
    @State private var showEditor = false
    @State private var editProfile: RouterProfile? = nil
    @State private var showRouterWeb = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    appearanceCard
                    refreshCard
                    itemsCard
                    routersCard
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
            .sheet(isPresented: $showEditor) {
                ConnectionEditorView(profile: editProfile)
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

    // MARK: - 连接

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.currentProfile?.title ?? "还没有连接")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.currentProfile?.subtitle ?? "在下面添加一台路由器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                statusPill
            }

            HStack(spacing: 8) {
                actionChip("重新连接", icon: "arrow.clockwise") {
                    Task { await model.manualRefresh() }
                }
                actionChip("网页后台", icon: "safari") { showRouterWeb = true }
                actionChip("编辑", icon: "pencil") {
                    editProfile = model.currentProfile
                    showEditor = true
                }
            }
        }
        .glassCard()
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

    private func actionChip(_ title: String, icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2.weight(.semibold))
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
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
                            .frame(width: 22)
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

    // MARK: - 更新频率

    private var refreshCard: some View {
        SectionCard("更新频率", icon: "clock.arrow.circlepath") {
            VStack(spacing: 14) {
                ForEach(PollTier.allCases) { tier in
                    tierRow(tier)
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    Text("预设")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    ForEach(PollPreset.allCases) { preset in
                        Button(preset.title) {
                            model.applyPreset(preset)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.primary)
                        .buttonStyle(.plain)
                    }
                }

                Text("当前：\(model.pollSummary)。同一档里的项目会合并成一条命令发给路由器，所以把项挪到慢档比关掉更划算。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.items(in: .fast).count > 3 {
                    Text("快档已经挂了 \(model.items(in: .fast).count) 项，路由器性能一般的话建议把闪存、端口挪到中档。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func tierRow(_ tier: PollTier) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(tier.title)
                    .font(.subheadline.weight(.medium))
                Text("\(model.items(in: tier).count) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                secondsStepper(tier)
            }
            Text(tier.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func secondsStepper(_ tier: PollTier) -> some View {
        let value = model.seconds(for: tier)
        let range = tier.secondsRange
        return HStack(spacing: 9) {
            Button {
                model.setSeconds(value - tier.step, for: tier)
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(value > range.lowerBound ? Color.blue : Color(.tertiaryLabel))
            .disabled(value <= range.lowerBound)

            Text("\(Int(value)) 秒")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 50)

            Button {
                model.setSeconds(value + tier.step, for: tier)
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(value < range.upperBound ? Color.blue : Color(.tertiaryLabel))
            .disabled(value >= range.upperBound)
        }
    }

    // MARK: - 数据项

    private var itemsCard: some View {
        SectionCard("数据项", icon: "list.bullet.below.rectangle") {
            VStack(spacing: 12) {
                ForEach(PollItem.allCases) { item in
                    itemRow(item)
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    Text(model.pollConfig.disabledCount > 0
                         ? "已关闭 \(model.pollConfig.disabledCount) 项，对应的卡片会停在最后一次的值"
                         : "每项都可以挪到别的档，或者直接关掉")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("恢复默认") {
                        model.resetPollConfig()
                    }
                    .font(.caption.weight(.medium))
                }
            }
        }
    }

    private func itemRow(_ item: PollItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if item.isRequired {
                Text("固定快档")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            } else {
                tierMenu(item)
            }
        }
    }

    private func tierMenu(_ item: PollItem) -> some View {
        let current = model.pollConfig.tier(for: item)
        return Menu {
            ForEach(PollTier.allCases) { tier in
                Button {
                    model.setTier(tier, for: item)
                } label: {
                    Label("\(tier.title)（\(Int(model.seconds(for: tier))) 秒）",
                          systemImage: current == tier ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            Button {
                model.setTier(nil, for: item)
            } label: {
                Label("关闭（不采集）", systemImage: "slash.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Text(current?.title ?? "关闭")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                current == nil ? Color(.tertiarySystemFill) : Color.blue.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(current == nil ? Color.secondary : Color.blue)
        }
    }

    // MARK: - 路由器

    private var routersCard: some View {
        SectionCard("路由器", icon: "wifi.router") {
            VStack(spacing: 12) {
                if model.profiles.isEmpty {
                    Text("还没有保存的连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(model.profiles) { profile in
                    routerRow(profile)
                }

                Divider().opacity(0.5)

                Button {
                    editProfile = nil
                    showEditor = true
                } label: {
                    rowLabel("新建连接", subtitle: "SSH 地址、端口与密码",
                             icon: "plus.circle")
                }
                .buttonStyle(.plain)

                Button {
                    showRouterWeb = true
                } label: {
                    rowLabel("打开路由器网页后台", subtitle: "在 App 内打开 LuCI 面板",
                             icon: "safari")
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Toggle("自动登录", isOn: Binding(
                        get: { model.autoLogin },
                        set: { model.autoLogin = $0 }
                    ))
                    .font(.subheadline)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func routerRow(_ profile: RouterProfile) -> some View {
        let isCurrent = profile.id == model.currentProfileID
        return HStack(spacing: 10) {
            Button {
                Task { await model.switchTo(profile) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.router")
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.blue : Color.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text(profile.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    Task { await model.switchTo(profile) }
                } label: {
                    Label("切换到这个连接", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    editProfile = profile
                    showEditor = true
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
        }
    }

    private func rowLabel(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 关于

    private var aboutCard: some View {
        SectionCard("关于", icon: "info.circle") {
            VStack(spacing: 9) {
                infoRow("版本", "1.15.0")
                infoRow("连接方式", "SSH 直连")
                infoRow("OpenClash", model.openClash.installed
                        ? (model.openClash.running ? "运行中" : "已停止")
                        : "未检测到")
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
