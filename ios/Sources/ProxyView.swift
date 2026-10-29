import SwiftUI
import Charts

struct ProxyView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedConfig = ""
    @State private var showPanel = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    actionCard
                    metricsCard
                    configCard
                    panelCard
                    accessCard
                }
                .padding(16)
            }
            .background(Color.clear)
            .navigationTitle("网络代理")
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable {
                await model.manualRefresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.manualRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                if selectedConfig.isEmpty {
                    selectedConfig = model.openClash.config
                }
            }
            .onChange(of: model.openClash.config) { _, newValue in
                if selectedConfig.isEmpty || !model.openClash.configs.contains(selectedConfig) {
                    selectedConfig = newValue
                }
            }
            .sheet(isPresented: $showPanel) {
                if let url = model.openClash.panelURL {
                    PanelView(url: url)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenClash").font(.title3.bold())
                    Text(model.openClash.installed
                         ? (model.openClash.running ? "服务运行中" : "服务已停止")
                         : "未检测到 OpenClash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(model.openClash.running ? .green : .orange).frame(width: 8, height: 8)
                    Text(model.openClash.running ? "运行中" : "已停止")
                        .font(.caption)
                        .foregroundStyle(model.openClash.running ? .green : .secondary)
                }
            }
            Text("代理模式").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                modeButton("规则", value: "rule")
                modeButton("全局", value: "global")
                modeButton("直连", value: "direct")
            }
            .disabled(model.busy)
        }
        .cardStyle()
    }

    private func modeButton(_ title: String, value: String) -> some View {
        Button {
            Task {
                await model.switchMode(value)
                await model.refreshOpenClash()
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.openClash.mode == value ? .blue : .secondary)
        .background(
            model.openClash.mode == value ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var actionCard: some View {
        HStack(spacing: 10) {
            actionButton(title: "启动", icon: "play.fill", color: .blue, filled: true) {
                await model.startOpenClash()
            }
            actionButton(title: "关闭", icon: "power", color: .red, filled: false) {
                await model.stopOpenClash()
            }
            actionButton(title: "重启", icon: "arrow.clockwise", color: .blue, filled: false) {
                await model.restartOpenClash()
            }
        }
        .disabled(model.busy)
    }

    private func actionButton(
        title: String, icon: String, color: Color, filled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(filled ? .white : color)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(filled ? 0.30 : 0.38), lineWidth: 1)
            }
            .shadow(color: color.opacity(filled ? 0.20 : 0.05), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var metricsCard: some View {
        let m = model.ocMetrics
        return VStack(alignment: .leading, spacing: 12) {
            Text("运行数据").font(.headline)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                metric("上传", formatSpeed(m.upload))
                metric("下行", formatSpeed(m.download))
                metric("上传总量", formatBytes(Double(m.uploadTotal)))
                metric("下载总量", formatBytes(Double(m.downloadTotal)))
                metric("连接", "\(m.connections)")
                metric("内存", formatBytes(Double(m.memory)))
                metric("CPU", String(format: "%.1f%%", m.cpu))
                metric("负载", String(format: "%.1f%%", m.load))
            }
        }
        .cardStyle()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置文件").font(.headline)
            Text(model.openClash.config.isEmpty ? "未选择" : model.openClash.config)
                .font(.subheadline)
            if model.openClash.configs.isEmpty {
                Text("未找到配置文件").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("选择配置文件", selection: $selectedConfig) {
                    ForEach(model.openClash.configs, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task {
                        await model.switchConfig(selectedConfig)
                        await model.refreshOpenClash()
                    }
                } label: {
                    Text("切换配置")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedConfig.isEmpty || selectedConfig == model.openClash.config || model.busy)
            }
        }
        .cardStyle()
    }

    private var panelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("控制面板").font(.headline)
            Text(model.openClash.running ? "服务运行中" : "服务未运行")
                .font(.caption)
                .foregroundStyle(model.openClash.running ? .green : .secondary)
            if let url = model.openClash.panelURL {
                Text(url.absoluteString)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                showPanel = true
            } label: {
                Text("打开后端")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.openClash.running || model.openClash.panelURL == nil)
        }
        .cardStyle()
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("访问检查").font(.headline)
                Spacer()
                Button("测试连通性") {
                    Task { await model.checkAccess() }
                }
                .font(.caption)
                .disabled(model.busy)
            }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(model.accessChecks) { check in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(check.site.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(check.tested
                             ? (check.success ? "\(check.latency) ms" : "-- ms")
                             : "-- ms")
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 4) {
                            Circle()
                                .fill(check.success ? .green : (check.tested ? .red : .gray))
                                .frame(width: 6, height: 6)
                            Text(check.tested ? (check.success ? "正常" : "连接超时") : "未检测")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
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
                            .frame(height: 24)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .cardStyle()
    }
}
