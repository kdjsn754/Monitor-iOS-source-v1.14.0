import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    ForEach(model.visibleModules) { module in
                        moduleView(module)
                    }
                }
                .padding(16)
            }
            .background(Color.clear)
            .navigationTitle("概览")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.manualRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await model.manualRefresh()
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
            if model.history.count > 1 {
                Chart(model.history) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("下载", point.download),
                        series: .value("方向", "下载")
                    )
                    .foregroundStyle(.blue)
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("上传", point.upload),
                        series: .value("方向", "上传")
                    )
                    .foregroundStyle(.purple)
                }
                .chartXAxis(.hidden)
                .frame(height: 76)
            }
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatFlashBytes(info.usedBytes))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("已用 / 共 \(formatFlashBytes(info.total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        Text("\(Int((info.usedFraction * 100).rounded()))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(flashAccent(info.usedFraction))
                            .monospacedDigit()
                    }
                    FlashCompositionBar(info: info)
                    VStack(spacing: 7) {
                        FlashLegendRow(
                            label: "系统占用",
                            bytes: info.systemUsed,
                            fraction: info.systemFraction,
                            color: Color(.systemGray)
                        )
                        FlashLegendRow(
                            label: "应用程序",
                            bytes: info.appUsed,
                            fraction: info.appFraction,
                            color: .blue
                        )
                        FlashLegendRow(
                            label: "可用空间",
                            bytes: info.available,
                            fraction: info.availableFraction,
                            color: Color(.systemGray3)
                        )
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

    /// 剩余空间少于 10% 转橙、少于 3% 转红，其余用蓝色。
    private func flashAccent(_ used: Double) -> Color {
        if used >= 0.97 { return .red }
        if used >= 0.90 { return .orange }
        return .blue
    }

    private var hardwareContent: some View {
        HStack(spacing: 12) {
            hardwareTile(
                icon: "thermometer.medium",
                title: "温度",
                value: model.stats.temperature.map { String(format: "%.1f °C", $0) } ?? "无传感器",
                color: .orange
            )
            hardwareTile(
                icon: "fanblades",
                title: "风扇",
                value: model.stats.fanRPM.map { String(format: "%.0f RPM", $0) } ?? "无传感器",
                color: .teal
            )
        }
    }

    private func hardwareTile(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var devicesContent: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(model.devices.count)")
                    .font(.title.bold())
                    .foregroundStyle(.blue)
                Text("台设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("仅 DHCP 租约")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.devices.prefix(4)) { device in
                HStack {
                    Text(device.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(device.ip)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !model.devices.isEmpty {
                NavigationLink("查看全部设备") {
                    DeviceListView()
                }
                .font(.caption)
            }
        }
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

/// 一条横向"容量条"，按系统 / 应用 / 可用三段拼接，一眼看出空间构成。
private struct FlashCompositionBar: View {
    let info: FlashInfo

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray6))
                HStack(spacing: 0) {
                    segment(width: width * CGFloat(info.systemFraction), color: Color(.systemGray))
                    segment(width: width * CGFloat(info.appFraction), color: .blue)
                    segment(width: width * CGFloat(info.availableFraction), color: Color(.systemGray3))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已用 \(Int((info.usedFraction * 100).rounded()))%")
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width))
    }
}

private struct FlashLegendRow: View {
    let label: String
    let bytes: UInt64
    let fraction: Double
    let color: Color

    private var percent: Int {
        Int((max(0, min(1, fraction)) * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Text(formatFlashBytes(bytes))
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
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

    private var value: Double {
        guard percent.isFinite else { return 0 }
        return max(0, min(100, percent))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 12)

            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.25), radius: 4)

            VStack(spacing: 1) {
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("占用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
    }
}

extension View {
    func cardStyle() -> some View {
        glassCard(padding: 14, cornerRadius: 22)
    }
}
