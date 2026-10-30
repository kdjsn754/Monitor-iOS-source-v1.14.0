import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAllDevices = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    PageHeader("概览") {
                        HeaderButton("arrow.clockwise") {
                            Task { await model.manualRefresh() }
                        }
                    }
                    header
                    ForEach(model.visibleModules) { module in
                        moduleView(module)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(Color.clear)
            // 标题画在内容里了，导航栏整条不要：留着它状态栏下面会空出一整条。
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.manualRefresh()
            }
            .sheet(isPresented: $showAllDevices) {
                DeviceListView()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.router.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.routerInfo.model.isEmpty ? "OpenWrt" : model.routerInfo.model)
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(model.connected ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.stats.wanDevice.isEmpty {
                        Text("· \(model.stats.wanDevice)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func moduleView(_ module: OverviewModule) -> some View {
        switch module {
        case .speed:
            moduleCard(module) { speedContent }
        case .resources:
            resourcesCards
        case .flash:
            moduleCard(module) { flashContent }
        case .hardware:
            moduleCard(module) { hardwareContent }
        case .devices:
            moduleCard(module) { devicesContent }
        case .system:
            moduleCard(module) { systemContent }
        }
    }

    private func moduleCard<Content: View>(
        _ module: OverviewModule,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(module.title, systemImage: module.icon)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var speedContent: some View {
        VStack(spacing: 10) {
            HStack {
                speedValue("下载", value: formatSpeed(model.stats.download), color: .blue, icon: "arrow.down")
                Divider().frame(height: 34)
                speedValue("上传", value: formatSpeed(model.stats.upload), color: .purple, icon: "arrow.up")
            }
            SpeedSparkline(points: model.history)
            HStack {
                Text("本次会话 ↓ \(formatBytes(model.stats.sessionDownload))")
                Spacer()
                Text("↑ \(formatBytes(model.stats.sessionUpload))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func speedValue(_ label: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resourcesCards: some View {
        HStack(alignment: .top, spacing: 12) {
            ResourceRingCard(
                title: "CPU",
                icon: "cpu",
                accent: .orange,
                percent: model.stats.cpu,
                topRight: model.routerInfo.cpuCores > 0
                    ? "\(model.routerInfo.cpuCores) 核" : "-- 核",
                bottom: String(
                    format: "负载 %.2f / %.2f / %.2f",
                    model.stats.load,
                    model.stats.load5,
                    model.stats.load15
                )
            )
            ResourceRingCard(
                title: "内存",
                icon: "memorychip",
                accent: .indigo,
                percent: model.memoryFraction * 100,
                topRight: "可用 \(formatBytes(Double(max(0, model.stats.memoryTotal - model.stats.memoryUsed))))",
                bottom: "\(formatBytes(Double(model.stats.memoryUsed))) / \(formatBytes(Double(model.stats.memoryTotal)))"
            )
        }
    }

    private var flashContent: some View {
        let info = model.flashInfo
        return Group {
            if info.hasData {
                VStack(alignment: .leading, spacing: 12) {
                    // 和 CPU / 内存同一套圆环：中间是已用百分比，
                    // 右边只留「已用 / 剩余」两个数字加总容量，
                    // 不再把闪存拆成系统、应用、可用三段去讲。
                    HStack(alignment: .center, spacing: 16) {
                        RingGauge(
                            percent: info.usedFraction * 100,
                            accent: flashTone(info.usedFraction),
                            diameter: 98,
                            caption: "已用",
                            lineWidth: 11
                        )

                        VStack(spacing: 11) {
                            flashRow("已用", bytes: info.usedBytes,
                                     color: flashTone(info.usedFraction))
                            flashRow("剩余", bytes: info.available,
                                     color: Color(.systemGray3), hollow: true)
                            Divider().opacity(0.5)
                            HStack(spacing: 6) {
                                Text("总容量")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Text(formatFlashBytes(info.total))
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                            }
                        }
                    }

                    if info.usedFraction >= 0.9 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(info.usedFraction >= 0.97
                                 ? "闪存已接近写满，建议清理日志或卸载不用的插件"
                                 : "闪存空间偏紧，建议清理日志或卸载不用的插件")
                                .font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(flashTone(info.usedFraction))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("正在读取闪存信息…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
    }

    /// 闪存的一行：色点（剩余是空心）→ 名称 → 容量数字。
    private func flashRow(_ title: String, bytes: UInt64,
                          color: Color, hollow: Bool = false) -> some View {
        HStack(spacing: 7) {
            Group {
                if hollow {
                    Circle().strokeBorder(color, lineWidth: 1.5)
                } else {
                    Circle().fill(color)
                }
            }
            .frame(width: 8, height: 8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text(formatFlashBytes(bytes))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 占用低于 90% 用蓝色，90% 起转橙，97% 起转红——和进度条、百分比同一套颜色。
    private func flashTone(_ used: Double) -> Color {
        if used >= 0.97 { return .red }
        if used >= 0.90 { return .orange }
        return .blue
    }

    private var hardwareContent: some View {
        HStack(spacing: 12) {
            hardwareTile(
                icon: temperatureIcon,
                title: "温度",
                value: model.stats.temperature.map { String(format: "%.1f °C", $0) } ?? "无传感器",
                color: temperatureTone,
                badge: temperatureBadge
            )
            hardwareTile(
                // 停转时用静态叶轮；转起来由 spin 换成会转的叶轮（见 FanBlades）。
                icon: "fanblades",
                title: "风扇",
                value: model.stats.fanRPM.map { String(format: "%.0f RPM", $0) } ?? "无传感器",
                color: fanTone,
                badge: fanBadge,
                spin: model.stats.fanRPM
            )
        }
    }

    // 图标跟着读数走：温度计低/中/高三档，风扇叶轮越转越快、颜色由青转橙，
    // 一眼能看出「凉/热」「慢/快」，不用先读数字。

    private var temperatureIcon: String {
        guard let t = model.stats.temperature else { return "thermometer.medium" }
        if t >= 70 { return "thermometer.high" }
        if t <= 40 { return "thermometer.low" }
        return "thermometer.medium"
    }

    private var temperatureTone: Color {
        guard let t = model.stats.temperature else { return Color(.systemGray) }
        if t >= 70 { return .red }
        if t >= 55 { return .orange }
        return .teal
    }

    private var temperatureBadge: String? {
        guard let t = model.stats.temperature else { return nil }
        if t >= 70 { return "偏高" }
        if t >= 55 { return "温热" }
        return nil
    }

    private var fanTone: Color {
        guard let rpm = model.stats.fanRPM, rpm > 0 else { return Color(.systemGray) }
        if rpm >= 2400 { return .orange }
        if rpm >= 1200 { return .teal }
        return .mint
    }

    private var fanBadge: String? {
        guard let rpm = model.stats.fanRPM else { return nil }
        if rpm <= 0 { return "静止" }
        if rpm >= 2400 { return "高速" }
        if rpm >= 1200 { return "中速" }
        return "低速"
    }

    private func hardwareTile(icon: String, title: String, value: String,
                              color: Color, badge: String? = nil,
                              spin: Double? = nil) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)

                if let rpm = spin, rpm > 0 {
                    FanBlades(rpm: rpm, color: color, size: 18)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 连接设备：左边一律「头像 + 名字 / IP」两行，右边不再放任何数字，
    /// 所有文字共用同一条左边界。旧版是「名字左、IP 右」两端对齐，
    /// 设备名长短不一，右侧 IP 就被顶得忽左忽右，看起来整块都是歪的。
    private var devicesContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(model.devices.count)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                Text("台设备在线")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("DHCP 租约")
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.bottom, 8)

            if model.devices.isEmpty {
                Text("还没读到 DHCP 租约，下一轮刷新再看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                // 用 IP 当标识：DeviceInfo 每轮都重建，UUID 每次都变，
                // 会让这几行每 2 秒被整体重建一次。
                ForEach(Array(model.devices.prefix(4).enumerated()), id: \.element.ip) { index, device in
                    if index > 0 {
                        Divider().opacity(0.6).padding(.leading, 38)
                    }
                    deviceRow(device)
                }

                Divider().opacity(0.6).padding(.top, 2)

                Button {
                    showAllDevices = true
                } label: {
                    HStack(spacing: 4) {
                        Text(model.devices.count > 4
                             ? "查看全部 \(model.devices.count) 台设备"
                             : "查看全部设备")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.top, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 一行设备：30pt 圆底首字母 + 名字 / IP。行高固定，四行高度不会因为
    /// 名字里有没有中文、有没有改名而参差。
    private func deviceRow(_ device: DeviceInfo) -> some View {
        HStack(spacing: 8) {
            Text(initial(of: device))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(for: device))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(device.ip)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func initial(of device: DeviceInfo) -> String {
        let name = model.displayName(for: device)
        guard let first = name.first, first.isLetter || first.isNumber else { return "?" }
        return String(first).uppercased()
    }

    private var systemContent: some View {
        VStack(spacing: 0) {
            InfoRow(label: "主机名", value: model.routerInfo.hostname.isEmpty ? "--" : model.routerInfo.hostname)
            Divider()
            InfoRow(label: "型号", value: model.routerInfo.model.isEmpty ? "--" : model.routerInfo.model)
            Divider()
            InfoRow(label: "架构", value: model.routerInfo.architecture.isEmpty ? "--" : model.routerInfo.architecture)
            Divider()
            InfoRow(label: "固件", value: model.routerInfo.firmware.isEmpty ? "--" : model.routerInfo.firmware)
            Divider()
            InfoRow(label: "内核", value: model.routerInfo.kernel.isEmpty ? "--" : model.routerInfo.kernel)
            Divider()
            InfoRow(label: "运行时间", value: formatUptime(model.stats.uptime))
            Divider()
            InfoRow(label: "负载", value: String(format: "%.2f", model.stats.load))
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 9)
    }
}

/// 速度曲线。
///
/// 以前用 Swift Charts：每 2 秒数据一变，整套图表场景图（坐标轴、标度、图例、
/// 动画事务）都要重建一次，是概览页最贵的一块，也是「点一下概览就发热」的主因。
/// 换成一个 Canvas 路径之后只画两条折线 + 一块渐变，成本跟点数线性相关。
private struct SpeedSparkline: View {
    let points: [HistoryPoint]

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            guard points.count > 1 else {
                // 刚连上还没攒够两个点：画一条淡基线，卡片高度不会跳。
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 1))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(baseline, with: .color(Color(.separator).opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                return
            }

            // 两条线共用一个峰值，上下行的高低关系才看得出来。
            let peak = max(points.map { max($0.download, $0.upload) }.max() ?? 0, 1)
            let stepX = size.width / CGFloat(points.count - 1)
            let height = size.height - 2

            func path(_ value: (HistoryPoint) -> Double) -> Path {
                var path = Path()
                for (index, point) in points.enumerated() {
                    let ratio = max(0, min(1, value(point) / peak))
                    let point2D = CGPoint(x: CGFloat(index) * stepX,
                                          y: size.height - 1 - CGFloat(ratio) * height)
                    if index == 0 { path.move(to: point2D) } else { path.addLine(to: point2D) }
                }
                return path
            }

            let downloadPath = path { $0.download }
            var area = downloadPath
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [Color.blue.opacity(0.20), Color.blue.opacity(0)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            context.stroke(downloadPath, with: .color(.blue), style: line)
            context.stroke(path { $0.upload }, with: .color(.purple), style: line)
        }
        .frame(height: 76)
        .accessibilityHidden(true)
    }
}

private struct ResourceRingCard: View {
    let title: String
    let icon: String
    let accent: Color
    let percent: Double
    let topRight: String
    let bottom: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                // 和「硬件状态」同一个做法：淡色圆角底 + 系统图标，
                // 不再是裸图标贴在标题前面（那样一眼看过去像两个字母飘着）。
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(topRight)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            RingGauge(percent: percent, accent: accent)

            Text(bottom)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 11, cornerRadius: 16)
    }
}

private struct RingGauge: View {
    let percent: Double
    let accent: Color
    var diameter: CGFloat = 112
    var caption: String = "占用"
    var lineWidth: CGFloat = 12

    private var value: Double {
        guard percent.isFinite else { return 0 }
        return max(0, min(100, percent))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: diameter * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 会转的风扇叶轮：转速越高转得越快，停转时静止。
///
/// 用「重复的旋转动画」而不是按帧重绘：动画由渲染进程（Core Animation）执行，
/// App 不会为此每秒重画一次界面——概览页本来就是靠降低重绘量压 CPU 的。
/// 时长只分四档，档位变了才用 .id 重建转子、从 0 度重新起转，
/// 避免「改了时长但旧动画还在跑」导致的忽快忽慢。
private struct FanBlades: View {
    let rpm: Double
    let color: Color
    var size: CGFloat = 18

    /// 一圈用多久：600 RPM 转一圈 1.5 秒，2400 往上接近 0.4 秒一圈。
    private var period: Double {
        switch rpm {
        case ..<900: return 1.5
        case ..<1600: return 0.95
        case ..<2400: return 0.62
        default: return 0.42
        }
    }

    var body: some View {
        Rotor(period: period, color: color, size: size)
            .id(period)
    }
}

private struct Rotor: View {
    let period: Double
    let color: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "fanblades.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func cardStyle() -> some View {
        glassCard(padding: 14, cornerRadius: 22)
    }
}
