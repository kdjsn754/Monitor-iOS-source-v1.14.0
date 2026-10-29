import SwiftUI
import Charts

/// 网络代理（OpenClash）：功能与旧版一致，只是把信息按「状态 → 流量 → 内核 → 配置 → 检查」重排。
struct ProxyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedConfig = ""
    @State private var showPanel = false

    private var oc: OpenClashInfo { model.openClash }
    private var metrics: OpenClashMetrics { model.ocMetrics }
    private var accent: Color {
        if !oc.installed { return .gray }
        return oc.running ? .green : .orange
    }

    private var statusText: String {
        if !oc.installed { return "未检测到插件" }
        return oc.running ? "运行中" : "已停止"
    }

    private var statusDetail: String {
        if !oc.installed { return "未检测到 OpenClash" }
        if !oc.running { return "服务已停止，启动后可查看流量" }
        return "面板端口 \(oc.panelPort)"
    }

    private var canSwitchConfig: Bool {
        !selectedConfig.isEmpty && selectedConfig != oc.config
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader("网络代理") {
                        HeaderButton("arrow.clockwise") {
                            Task { await model.manualRefresh() }
                        }
                    }
                    heroCard
                    trafficCard
                    runtimeCard
                    configCard
                    accessCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(Color.clear)
            // 见 OverviewView：标题画在内容里，导航栏整条不要。
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.manualRefresh()
            }
            .onAppear { syncSelectedConfig() }
            .onChange(of: oc.config) { _, _ in syncSelectedConfig() }
            .sheet(isPresented: $showPanel) {
                if let url = oc.panelURL {
                    PanelView(url: url)
                }
            }
        }
    }

    private func syncSelectedConfig() {
        if selectedConfig.isEmpty || !oc.configs.contains(selectedConfig) {
            selectedConfig = oc.config
        }
    }

    // MARK: - 状态与操作

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenClash")
                        .font(.headline)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
                statusPill
            }

            if oc.installed {
                HStack(spacing: 6) {
                    modeButton("规则", value: "rule")
                    modeButton("全局", value: "global")
                    modeButton("直连", value: "direct")
                }
                .disabled(model.busy || !oc.running)
                .opacity(oc.running ? 1 : 0.55)

                HStack(spacing: 8) {
                    actionChip("启动", icon: "play.fill", color: .blue) {
                        await model.startOpenClash()
                    }
                    actionChip("关闭", icon: "stop.fill", color: .red) {
                        await model.stopOpenClash()
                    }
                    actionChip("重启", icon: "arrow.clockwise", color: .blue) {
                        await model.restartOpenClash()
                    }
                }
                .disabled(model.busy)
                .opacity(model.busy ? 0.55 : 1)
            } else {
                Text("确认路由器已安装 OpenClash 插件，且 SSH 账号有权限读取 /etc/config/openclash。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func modeButton(_ title: String, value: String) -> some View {
        let selected = oc.mode == value
        return Button {
            Task {
                await model.switchMode(value)
                await model.refreshOpenClash()
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    selected ? Color.blue.opacity(0.14) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .foregroundStyle(selected ? Color.blue : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func actionChip(_ title: String, icon: String, color: Color,
                            action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 流量

    private var trafficCard: some View {
        SectionCard("实时流量", icon: "arrow.up.arrow.down") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    flowBlock("下载", value: formatSpeed(metrics.download),
                              icon: "arrow.down", color: .blue)
                    Divider().frame(height: 42)
                    flowBlock("上传", value: formatSpeed(metrics.upload),
                              icon: "arrow.up", color: .purple)
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    totalBlock("本次累计下载", formatBytes(Double(metrics.downloadTotal)))
                    Spacer(minLength: 4)
                    totalBlock("上传", formatBytes(Double(metrics.uploadTotal)))
                }

                if oc.running, !metrics.apiReachable {
                    Label("读不到内核接口：端口 \(oc.panelPort) 无响应，或控制面板密码不一致。数字会停在上一次的值。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func flowBlock(_ label: String, value: String,
                           icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func totalBlock(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: - 内核

    private var runtimeCard: some View {
        SectionCard("内核状态", icon: "cpu") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                statTile("连接数", "\(metrics.connections)",
                         icon: "point.3.connected.trianglepath.dotted")
                statTile("内存", formatBytes(Double(metrics.memory)),
                         icon: "memorychip")
                statTile("CPU", String(format: "%.1f%%", metrics.cpu),
                         icon: "cpu")
                statTile("负载", String(format: "%.1f%%", metrics.load),
                         icon: "speedometer")
            }
        }
    }

    private func statTile(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - 配置与控制面板

    private var configCard: some View {
        SectionCard("配置与控制面板", icon: "doc.text") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前配置")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(oc.config.isEmpty ? "未选择" : oc.config)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)

                    if oc.configs.isEmpty {
                        Text("未找到配置")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(oc.configs, id: \.self) { name in
                                Button {
                                    selectedConfig = name
                                } label: {
                                    Label(name, systemImage: name == oc.config
                                          ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("选择")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.blue)
                        }
                    }
                }

                if !oc.configs.isEmpty {
                    Button {
                        Task {
                            await model.switchConfig(selectedConfig)
                            await model.refreshOpenClash()
                        }
                    } label: {
                        Text(canSwitchConfig ? "切换到 \(selectedConfig)" : "已应用")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Color.blue.opacity(canSwitchConfig ? 0.14 : 0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(canSwitchConfig ? Color.blue : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSwitchConfig || model.busy)
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("控制面板")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(oc.panelURL?.absoluteString ?? "未获取到地址")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)

                    Button {
                        showPanel = true
                    } label: {
                        Text("打开")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!oc.running || oc.panelURL == nil)
                    .opacity(!oc.running || oc.panelURL == nil ? 0.45 : 1)
                }
            }
        }
    }

    // MARK: - 访问检查

    private var accessCard: some View {
        SectionCard("访问检查", icon: "globe.asia.australia") {
            VStack(spacing: 12) {
                if model.accessChecks.isEmpty {
                    Text("还没有检查结果，点下面的按钮跑一次。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(model.accessChecks) { check in
                            accessTile(check)
                        }
                    }
                }

                Button {
                    Task { await model.checkAccess() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.busy ? "检测中…" : "重新检测")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }
        }
    }

    private func accessTile(_ check: AccessCheck) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(check.site.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(dotColor(check))
                    .frame(width: 6, height: 6)
            }

            Text(latencyText(check))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(latencyColor(check))

            if check.history.count > 1 {
                Chart {
                    ForEach(check.history.indices, id: \.self) { index in
                        LineMark(
                            x: .value("次数", index),
                            y: .value("延迟", check.history[index])
                        )
                        .foregroundStyle(check.success ? Color.green : Color.red)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func latencyText(_ check: AccessCheck) -> String {
        guard check.tested else { return "--" }
        return check.success ? "\(check.latency) ms" : "超时"
    }

    private func latencyColor(_ check: AccessCheck) -> Color {
        guard check.tested else { return .secondary }
        return check.success ? Color.primary : Color.red
    }

    private func dotColor(_ check: AccessCheck) -> Color {
        guard check.tested else { return Color(.tertiaryLabel) }
        return check.success ? .green : .red
    }
}
