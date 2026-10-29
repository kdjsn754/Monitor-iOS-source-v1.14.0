import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var confirmLogout = false
    @State private var showEditor = false
    @State private var editProfile: RouterProfile? = nil
    @State private var showRouterWeb = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $themeMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    NavigationLink {
                        ModuleSettingsView()
                    } label: {
                        Label("管理概览模块", systemImage: "square.grid.2x2")
                    }
                }

                Section("路由器") {
                    if let profile = model.currentProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.title).font(.subheadline.weight(.semibold))
                            Text(profile.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(model.profiles) { profile in
                        Button {
                            Task { await model.switchTo(profile) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.title)
                                    Text(profile.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == model.currentProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                model.deleteProfile(profile)
                            }
                        }
                    }

                    Button {
                        editProfile = model.currentProfile
                        showEditor = true
                    } label: {
                        Label("编辑当前连接", systemImage: "pencil")
                    }

                    Button {
                        showRouterWeb = true
                    } label: {
                        Label("打开路由器网页后台", systemImage: "safari")
                    }

                    Button {
                        editProfile = nil
                        showEditor = true
                    } label: {
                        Label("新建连接", systemImage: "plus.circle")
                    }

                    Toggle("自动登录", isOn: Binding(
                        get: { model.autoLogin },
                        set: { model.autoLogin = $0 }
                    ))

                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("刷新策略") {
                    Toggle("低功耗模式", isOn: Binding(
                        get: { model.lowPower },
                        set: { model.lowPower = $0 }
                    ))

                    LabeledContent("快档 / 慢档", value: model.pollSummary)

                    Text("轮询已按最省 CPU 的方式重排：CPU、内存、网口速率、温度风扇走短周期，闪存、租约、端口和 OpenClash 接口拆到长周期，所有脚本都以最低优先级执行。低功耗模式会再拉长一档，适合性能较弱的路由器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("所有监控数据只在本机和路由器之间传输，不经过云端。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("断开并清除密码", role: .destructive) {
                        confirmLogout = true
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.14.1")
                    LabeledContent("连接方式", value: "SSH 直连")
                    LabeledContent("OpenClash", value: model.openClash.installed ? "已安装" : "未检测到")
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color(.secondarySystemGroupedBackground))
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
