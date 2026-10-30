import SwiftUI

/// 风扇控制面板（对接路由器的 `gl-fanctrl` 插件）。
///
/// 为什么不自己接管风扇：这个 App 只能走 SSH，没有常驻进程。真要自己按温度调 PWM，
/// 就得不停地 `cat 温度` → `echo pwm`，手机一锁屏、一断开，风扇就停在最后一个值上，
/// 那是最危险的失败模式。插件的守护进程本来就跑在路由器上，掉线也不影响它，
/// 所以这里只当它的「遥控器」：读写同一份 UCI 配置，然后让它自己重启生效。
///
/// 版式跟「连接设备 / 切换连接」两个面板一致：同一套 `SheetSurface` 底色、
/// 同一个「标题 + 小字 + 圆形叉」表头。
struct FanControlView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// 自动曲线的编辑副本。没按「应用」之前不碰路由器——七个 Stepper 每动一格
    /// 就 commit + 重启一次服务，路由器上的 flash 和风扇都受不了。
    @State private var draft = FanDraft()
    @State private var manualValue: Double = 0
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if !model.fan.loaded {
                        loadingCard
                    } else if !model.fan.installed {
                        installCard
                    } else {
                        statusCard
                        takeoverCard
                        modeCard
                        if model.fan.mode == .auto {
                            curveCard
                        } else {
                            manualCard
                        }
                        resetRow
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
        }
        .background(SheetSurface())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await model.refreshFan()
            seed()
        }
        // 每次动作之后 model 会回读一遍状态，这里跟着把草稿对齐，
        // 免得「应用完还显示旧值」。
        .onChange(of: model.fan) { _, _ in seed() }
        .confirmationDialog("恢复插件的默认配置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                Task { await model.restoreFanDefaults() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会把接管关掉、曲线恢复成 70/76/88 °C，风扇交回官方 gl_fan 服务。")
        }
    }

    // MARK: - 表头

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("风扇控制")
                    .font(.headline)
                Text(headerCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                Task { await model.refreshFan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .softTile(.blue, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.fanBusy)
            .accessibilityLabel("刷新风扇状态")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .softTile(.blue, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var headerCaption: String {
        guard model.fan.loaded else { return "正在读取插件状态…" }
        guard model.fan.installed else { return "路由器上没找到 gl-fanctrl" }
        let takeover = model.fan.enabled ? "已接管" : "未接管"
        return "gl-fanctrl · \(takeover) · \(model.fan.mode.title)模式"
    }

    // MARK: - 状态

    private var statusCard: some View {
        SectionCard("当前状态", icon: "fanblades") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    statTile("温度", value: model.fan.temperature.map { String(format: "%.0f°", $0) } ?? "—", color: .teal)
                    statTile("转速", value: model.fan.rpm.map { String(format: "%.0f", $0) } ?? "—", unit: "RPM", color: .mint)
                    statTile("PWM", value: model.fan.pwmPercent.map { "\($0)" } ?? "—", unit: "%", color: .blue)
                }

                // 自动模式给一句「现在应该转多少」，用户能自己判断风扇是不是跟着曲线走。
                if model.fan.mode == .auto, let expected = model.fan.expectedPercent {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("按曲线此刻应为 \(expected)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let pwm = model.fan.pwmPercent, abs(pwm - expected) > 12 {
                            Text("实测偏差较大")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func statTile(_ title: String, value: String, unit: String? = nil, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .softTile(color, radius: 11)
    }

    // MARK: - 接管

    private var takeoverCard: some View {
        SectionCard("接管", icon: "hand.raised") {
            VStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { model.fan.enabled },
                    set: { value in Task { await model.setFanEnabled(value) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("由插件接管风扇")
                            .font(.subheadline)
                        Text(model.fan.enabled
                             ? "官方 gl_fan 已停止，风扇归 gl-fanctrl 守护进程管"
                             : "官方 gl_fan 在管，插件不干预")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(.blue)
                .disabled(model.fanBusy)

                Divider().opacity(0.5)

                HStack(spacing: 6) {
                    serviceChip("守护进程", running: model.fan.pluginRunning)
                    serviceChip(model.fan.enabled ? "已接管" : "未接管", running: model.fan.enabled)
                    Spacer(minLength: 0)
                    if model.fanBusy {
                        ProgressView().controlSize(.mini)
                    }
                }

                // 最危险的组合：开关是开的，但守护进程不在了。这时官方服务已经被停掉，
                // 插件的进程又没起来——风扇没有任何人在管。这句话必须显眼。
                if model.fan.enabled && !model.fan.pluginRunning {
                    Text("接管开着，但没检测到 gl-fanctrl 守护进程——风扇此刻可能没人管。点右上角刷新，或先关掉接管交回官方服务。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func serviceChip(_ title: String, running: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(running ? Color.green : Color(.systemGray3))
                .frame(width: 6, height: 6)
            Text("\(title)\(running ? "运行" : "停止")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .rowTile(in: Capsule())
    }

    // MARK: - 模式

    private var modeCard: some View {
        SectionCard("控制模式", icon: "slider.horizontal.3") {
            Picker("控制模式", selection: Binding(
                get: { model.fan.mode },
                set: { value in Task { await model.setFanMode(value) } }
            )) {
                ForEach(FanControlState.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.fanBusy || !model.fan.enabled)
        }
    }

    // MARK: - 自动曲线

    private var curveCard: some View {
        SectionCard("自动温控曲线", icon: "thermometer.medium") {
            VStack(spacing: 11) {
                paramRow("起转温度", value: $draft.startTemp, range: 35...85, unit: "°C")
                paramRow("温度墙", value: $draft.wallTemp, range: 35...95, unit: "°C",
                         note: "达到即满速")
                paramRow("保护温度", value: $draft.criticalTemp, range: 35...105, unit: "°C",
                         note: "两种模式下都强制满速")
                paramRow("回差", value: $draft.hysteresis, range: 1...10, unit: "°C",
                         note: "避免临界点反复启停")
                Divider().opacity(0.5)
                paramRow("起转 PWM", value: $draft.startPercent, range: 0...100, unit: "%",
                         note: "低了可能起转失败")
                paramRow("最大 PWM", value: $draft.maxPercent, range: 0...100, unit: "%")
                paramRow("轮询间隔", value: $draft.pollInterval, range: 1...30, unit: "s")

                Button {
                    Task {
                        await model.applyFanAuto(
                            startTemp: draft.startTemp,
                            wallTemp: draft.wallTemp,
                            criticalTemp: draft.criticalTemp,
                            hysteresis: draft.hysteresis,
                            startPercent: draft.startPercent,
                            maxPercent: draft.maxPercent,
                            pollInterval: draft.pollInterval
                        )
                    }
                } label: {
                    Text(model.fanBusy ? "正在应用…" : "应用到路由器")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(GlassProminentButtonStyle())
                .disabled(model.fanBusy || !model.fan.enabled)
                .opacity(model.fan.enabled ? 1 : 0.5)
                .padding(.top, 2)

                if !model.fan.enabled {
                    Text("打开「由插件接管风扇」之后才能改曲线。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // 依赖关系就地夹紧：插件的校验规则是「温度墙 ≥ 起转+5、保护 ≥ 温度墙+3」，
            // 不满足时 commit 会被静默拒绝，界面却还显示着自己那套数字。
            .onChange(of: draft.startTemp) { _, new in
                if draft.wallTemp < new + 5 { draft.wallTemp = min(new + 5, 95) }
                if draft.criticalTemp < draft.wallTemp + 3 { draft.criticalTemp = min(draft.wallTemp + 3, 105) }
            }
            .onChange(of: draft.wallTemp) { _, new in
                if draft.criticalTemp < new + 3 { draft.criticalTemp = min(new + 3, 105) }
            }
        }
    }

    private func paramRow(_ title: String, value: Binding<Int>,
                          range: ClosedRange<Int>, unit: String,
                          note: String? = nil) -> some View {
        Stepper(value: value, in: range) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                    if let note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Text("\(value.wrappedValue)\(unit)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .tint(.blue)
        .disabled(model.fanBusy || !model.fan.enabled)
    }

    // MARK: - 手动

    private var manualCard: some View {
        SectionCard("手动转速", icon: "dial.medium") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(manualValue.rounded()))")
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                    Text("%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if let pwm = model.fan.pwmPercent {
                        Text("实际 PWM \(pwm)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 只在松手时下发：拖动的每一格都写一次 uci + 重启服务，
                // 一次拖动能把 flash 写几十遍。
                Slider(value: $manualValue, in: 0...100, step: 1) { editing in
                    guard !editing else { return }
                    let percent = Int(manualValue.rounded())
                    Task { await model.setFanManual(percent) }
                }
                .tint(.blue)
                .disabled(model.fanBusy || !model.fan.enabled)

                Text(model.fan.enabled
                     ? "0% 停转；1–100% 会被夹在「起转 PWM」和「最大 PWM」之间，避免低到起转失败。"
                     : "先打开上面的「由插件接管风扇」，才能手动调速。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 恢复默认 / 未安装

    private var resetRow: some View {
        Button {
            confirmReset = true
        } label: {
            Text("恢复插件默认配置")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .rowTile(radius: 12)
        .disabled(model.fanBusy)
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在读取风扇状态…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .rowTile(radius: 14)
    }

    private var installCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("路由器上没有 gl-fanctrl")
                    .font(.subheadline.weight(.semibold))
            }
            Text("风扇控制读写的是一份 UCI 配置（/etc/config/gl_fanctrl），需要先在路由器上装好这个插件。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                codeLine("opkg install /tmp/gl-fanctrl_0.1.0_all.ipk")
                codeLine("apk add --allow-untrusted /tmp/gl-fanctrl-0.1.0-r1.apk")
            }
            Text("opkg 用于 OpenWrt 21/22 固件，apk 用于 24.10+ 固件。装完回到这里点右上角刷新。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowTile(radius: 14)
    }

    private func codeLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// 面板里的数字跟着路由器回读的值走。用户没按「应用」之前，改动只存在草稿里。
    private func seed() {
        draft = FanDraft(model.fan)
        manualValue = Double(model.fan.manualPercent)
    }
}

/// 自动曲线在界面上的编辑副本。
private struct FanDraft: Equatable {
    var startTemp = 70
    var wallTemp = 76
    var criticalTemp = 88
    var hysteresis = 3
    var startPercent = 35
    var maxPercent = 100
    var pollInterval = 2

    init() {}

    init(_ state: FanControlState) {
        startTemp = state.startTemp
        wallTemp = state.wallTemp
        criticalTemp = state.criticalTemp
        hysteresis = state.hysteresis
        startPercent = state.startPercent
        maxPercent = state.maxPercent
        pollInterval = state.pollInterval
    }
}
