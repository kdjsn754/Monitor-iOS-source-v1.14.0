import SwiftUI

/// 网络代理（OpenClash）：功能与旧版一致，只是把信息按「状态 → 流量 → 内核 → 配置 → 检查」重排。
struct ProxyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPanel = false
    @State private var showConfigPicker = false
    @State private var isChecking = false

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
        // 面板地址已经挪到卡片下半部分，这里改说「当前跑的是哪份配置」，
        // 不再重复一遍端口号。
        let name = oc.config.isEmpty ? "" : (oc.config as NSString).lastPathComponent
        return name.isEmpty ? "运行中" : "配置 \(name)"
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
            .sheet(isPresented: $showPanel) {
                if let url = oc.panelURL {
                    PanelView(url: url)
                }
            }
            .sheet(isPresented: $showConfigPicker) {
                ConfigPickerSheet(
                    configs: oc.configs,
                    applied: oc.config
                ) { name in
                    Task {
                        await model.switchConfig(name)
                        await model.refreshOpenClash()
                    }
                }
            }
        }
    }

    // MARK: - 状态、操作与控制面板

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

                // 控制面板并进这张卡：以前它自己占一张卡，标题、图标、状态跟这里
                // 几乎是重复的。现在只隔一条细线，上半是「状态与操作」，下半是「面板入口」。
                Divider().opacity(0.5)

                panelBlock
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

    /// 面板：一行「图标 + 标题 + 状态标签 + 地址」，下面一条整宽主按钮。
    private var panelBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("控制面板")
                            .font(.subheadline.weight(.semibold))
                        Text(canOpenPanel ? "可打开" : "未就绪")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (canOpenPanel ? Color.green : Color.orange).opacity(0.14),
                                in: Capsule()
                            )
                            .foregroundStyle(canOpenPanel ? Color.green : Color.orange)
                    }
                    Text(panelAddress)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            Button {
                showPanel = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("打开控制面板")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    canOpenPanel ? Color.blue : Color(.systemGray4),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .foregroundStyle(canOpenPanel ? Color.white : Color(.systemGray))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canOpenPanel)
        }
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

                // 以前是「标签 12pt + 数值 12pt」挤在一行，跟上面的实时速率一比
                // 明显像脚注。改成两块同高的累计格：图标 + 小标签 + 17pt 数值。
                HStack(spacing: 10) {
                    totalTile("本次累计下载",
                              value: formatBytes(Double(metrics.downloadTotal)),
                              icon: "arrow.down.circle.fill", color: .blue)
                    totalTile("本次累计上传",
                              value: formatBytes(Double(metrics.uploadTotal)),
                              icon: "arrow.up.circle.fill", color: .purple)
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

    /// 累计流量格：左边一枚彩色箭头，右边「小标签 + 大数值」。
    private func totalTile(_ label: String, value: String,
                           icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    // MARK: - 配置

    /// 以前这一块是「一行标题 + 一个系统的 Menu 胶囊」。Menu 弹的是系统浮层：
    /// 灰底、系统字体、跟界面的圆角卡片完全不是一套，列表长了还得滚动整个系统面板。
    /// 现在改成一张可点的配置条 + 自绘的半屏选择器，全部用同一套卡片/胶囊样式。
    private var configCard: some View {
        SectionCard("代理配置", icon: "doc.text") {
            VStack(spacing: 10) {
                Button {
                    guard !oc.configs.isEmpty, !model.busy else { return }
                    showConfigPicker = true
                } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 38, height: 38)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前配置文件")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(configTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
                            Text(configDetail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if oc.configs.isEmpty {
                            Text("未找到")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Text("更换")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.blue)
                        }
                    }
                    .padding(11)
                    .background(Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(oc.configs.isEmpty || model.busy)
            }
        }
    }

    private var configTitle: String {
        guard !oc.config.isEmpty else { return "未选择" }
        return (oc.config as NSString).lastPathComponent
    }

    private var configDetail: String {
        guard !oc.configs.isEmpty else { return "没有可用配置" }
        return "共 \(oc.configs.count) 个配置文件"
    }

    private var canOpenPanel: Bool {
        oc.running && oc.panelURL != nil
    }

    private var panelAddress: String {
        guard let host = model.currentProfile?.host else { return "未获取到地址" }
        let base = "\(host):\(oc.panelPort)"
        return oc.dashboard.isEmpty ? base : "\(base) · \(oc.dashboard)"
    }

    // MARK: - 访问检查

    private var accessCard: some View {
        SectionCard("访问检查", icon: "globe.asia.australia") {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(lastCheckText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if testedCount > 0 {
                        Text("\(okCount)/\(testedCount) 可达")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(okCount == testedCount ? Color.green : Color.orange)
                    }
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(model.accessChecks) { check in
                        accessTile(check)
                    }
                }

                Button {
                    Task {
                        isChecking = true
                        await model.checkAccess()
                        isChecking = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isChecking {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isChecking ? "检测中…" : "重新检测")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isChecking || model.busy)
            }
        }
    }

    private var testedCount: Int {
        model.accessChecks.filter(\.tested).count
    }

    private var okCount: Int {
        model.accessChecks.filter { $0.tested && $0.success }.count
    }

    private var lastCheckText: String {
        guard let date = model.lastAccessCheckAt else { return "还没有检测结果" }
        return "最近检测 " + Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// 一个站点一格：右上角一枚小圆点，颜色就是延迟档位；下面是保留的延迟数值。
    ///
    /// 圆点以前只有「通 = 绿 / 不通 = 红」两档，延迟条又只有 3pt 高、看不出快慢。
    /// 现在把档位直接搬到圆点上（绿 ≤150 / 蓝 ≤400 / 橙 ≤800 / 红更慢或超时），
    /// 数值放大到 17pt 圆体，四格更矮更整齐，也不用再多画一条进度条。
    private func accessTile(_ check: AccessCheck) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(check.site.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                statusDot(check)
            }

            Text(latencyText(check))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(latencyColor(check))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 小圆点：里面实心 8pt，外面一层同色淡光晕，颜色即延迟档位。
    private func statusDot(_ check: AccessCheck) -> some View {
        let color = dotColor(check)
        return ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 16, height: 16)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .accessibilityLabel(dotLabel(check))
    }

    /// 绿 ≤150ms、蓝 ≤400ms、橙 ≤800ms、红 >800ms 或超时；没测过是灰的。
    private func dotColor(_ check: AccessCheck) -> Color {
        guard check.tested else { return Color(.systemGray3) }
        guard check.success else { return .red }
        if check.latency <= 150 { return .green }
        if check.latency <= 400 { return .blue }
        if check.latency <= 800 { return .orange }
        return .red
    }

    private func dotLabel(_ check: AccessCheck) -> String {
        guard check.tested else { return "还没有检测" }
        return check.success ? "延迟 \(check.latency) 毫秒" : "超时"
    }

    private func latencyText(_ check: AccessCheck) -> String {
        guard check.tested else { return "--" }
        return check.success ? "\(check.latency) ms" : "超时"
    }

    private func latencyColor(_ check: AccessCheck) -> Color {
        guard check.tested else { return .secondary }
        return check.success ? Color.primary : Color.red
    }
}

/// 配置文件选择器。
///
/// 之前点「选择」弹的是系统的 `Menu`：系统灰底浮层、系统字号、跟这套圆角卡片完全两个风格，
/// 列表一长还会被折成一列系统菜单项。这里改成自绘的半屏面板——
/// 每行一枚单选点、使用中的那条带绿色标签，底部一枚主按钮确认后才重启内核。
private struct ConfigPickerSheet: View {
    let configs: [String]
    let applied: String
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: String

    init(configs: [String], applied: String, onApply: @escaping (String) -> Void) {
        self.configs = configs
        self.applied = applied
        self.onApply = onApply
        let initial = configs.contains(applied) ? applied : (configs.first ?? "")
        _picked = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(configs, id: \.self) { name in
                        row(name)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            footer
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("选择配置文件")
                    .font(.headline)
                Text("共 \(configs.count) 个，当前用 \(appliedName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func row(_ name: String) -> some View {
        let selected = name == picked
        let isApplied = name == applied
        return Button {
            picked = name
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.blue : Color(.systemGray3),
                                      lineWidth: selected ? 6 : 1.5)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isApplied {
                        Text("使用中")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Spacer(minLength: 4)

                if selected, !isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isApplied ? 10 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.blue.opacity(0.08) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        selected ? Color.blue.opacity(0.35) : Color(.separator).opacity(0.4),
                        lineWidth: 0.8
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                guard !picked.isEmpty, picked != applied else {
                    dismiss()
                    return
                }
                onApply(picked)
                dismiss()
            } label: {
                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        canApply ? Color.blue : Color(.systemGray4),
                        in: Capsule()
                    )
                    .foregroundStyle(canApply ? Color.white : Color(.systemGray))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(picked.isEmpty)

            Text("切换后 OpenClash 会重启内核，正在走的连接会断一下。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var appliedName: String {
        applied.isEmpty ? "默认配置" : (applied as NSString).lastPathComponent
    }

    private var canApply: Bool {
        !picked.isEmpty && picked != applied
    }

    private var actionTitle: String {
        canApply ? "应用「\(picked)」" : "已在使用"
    }
}
