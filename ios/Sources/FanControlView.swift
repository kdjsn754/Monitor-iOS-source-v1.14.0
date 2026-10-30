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
            // 面板开着就每 2 秒刷一次**运行态**（温度 / 转速 / PWM / 守护进程）。
            // 以前只在打开那一刻读一次，之后不管风扇怎么转，界面都停在那张快照上。
            // 只刷运行态、不重读配置：`uci show` 又慢又没必要，而且整份 `fan`
            // 被覆盖会把正在拖的曲线草稿顶回旧值。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                await model.refreshFanRuntime()
            }
        }
        // 草稿只在**配置**变化时对齐：运行态每 2 秒都在变，拿它当触发条件的话，
        // 用户正拖着 Stepper 的时候草稿会被反复重置。
        .onChange(of: FanDraft(model.fan)) { _, _ in seed() }
        // 确认框自绘：sheet 里用系统 confirmationDialog，iOS 26 会把它锚到页面
        // 半空（看着像贴歪的气泡），所以和「连接设备」面板统一走这套浮层。
        .overlay {
            if confirmReset {
                SheetOverlay(onDismiss: { confirmReset = false }) {
                    SheetOverlayCard {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("恢复插件的默认配置？")
                                .font(.headline)
                            Text("会把接管关掉、曲线恢复成 70/76/88 °C，风扇交回官方温控。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
                            SheetOverlayButton(title: "取消") { confirmReset = false }
                            SheetOverlayButton(title: "恢复默认", tint: .red) {
                                confirmReset = false
                                Task { await model.restoreFanDefaults() }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 表头

    private var header: some View {
        SheetHeader("风扇控制", caption: headerCaption) {
            HStack(spacing: 8) {
                SheetIconButton(systemImage: "arrow.clockwise",
                                label: "刷新风扇状态") {
                    Task { await model.refreshFan() }
                }
                .disabled(model.fanBusy)
                SheetCloseButton { dismiss() }
            }
        }
    }

    /// 标题下面那行小字。**只写中文**：以前是「gl-fanctrl · 已接管 · 自动模式」，
    /// 插件名顶在最前面，每次进来第一眼先读一串英文缩写，真正要看的「谁在管、什么模式」
    /// 被挤到后面。插件名本来就在卡片和安装提示里出现过，这里不需要再报一遍。
    private var headerCaption: String {
        guard model.fan.loaded else { return "正在读取插件状态…" }
        guard model.fan.installed else { return "路由器上没找到这个插件" }
        // 只剩这里说一句状态。接管开着但守护进程不在，是最危险的组合：
        // 官方服务已停、插件进程又没起来，风扇没人管——所以这一条要压过常规文案。
        if model.fan.enabled && !model.fan.pluginRunning {
            return "已接管 · 但没检测到守护进程，风扇可能没人管"
        }
        return model.fan.enabled
            ? "插件接管中 · \(model.fan.mode.title)模式"
            : "风扇由官方温控在管 · \(model.fan.mode.title)模式"
    }

    // MARK: - 状态

    private var statusCard: some View {
        SheetSectionCard("当前状态", icon: "fanblades",
                         accessory: { controlPill }) {
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

    /// 标题行右上角那枚小胶囊：一眼看出风扇此刻归谁管。
    ///
    /// 以前这层信息只在标题下面一行小字里，和「自动模式」挤在一起；
    /// 现在挪成一个常驻标签，位置固定，扫一眼就行，不用读句子。
    private var controlPill: some View {
        let taken = model.fan.enabled
        return HStack(spacing: 4) {
            Circle()
                .fill(taken ? Color.blue : Color(.systemGray3))
                .frame(width: 5, height: 5)
            Text(taken ? "插件接管" : "官方温控")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(taken ? Color.blue : Color.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemFill), in: Capsule())
    }

    /// 状态小胶囊（接管卡里那两个）。
    /// 只写中文、只留「在不在跑」这一层信息：副词、解释、警告一律不进胶囊。
    private func stateChip(_ title: String, tone: Color, active: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? tone : Color(.systemGray3))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(active ? tone : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .softTile(active ? tone : Color(.systemGray), in: Capsule())
    }

    // MARK: - 接管

    /// 一行标题 + 右侧开关，下面跟两个状态胶囊。
    ///
    /// v1.28.14 曾把胶囊全删掉（那时底下还压着副标题和一段警告，四层信息挤在一个
    /// 开关上）。现在副标题和警告都不在了，只留两个胶囊回答「守护进程在不在跑」，
    /// 比让用户自己去标题小字里找要快。
    private var takeoverCard: some View {
        SheetSectionCard("由插件接管风扇", icon: "hand.raised",
                         accessory: {
                             Toggle("由插件接管风扇", isOn: Binding(
                                 get: { model.fan.enabled },
                                 set: { value in Task { await model.setFanEnabled(value) } }
                             ))
                             .labelsHidden()
                             .tint(.blue)
                             .disabled(model.fanBusy)
                         }) {
            HStack(spacing: 6) {
                stateChip(model.fan.pluginRunning ? "守护进程运行" : "守护进程未运行",
                          tone: .blue,
                          active: model.fan.pluginRunning)
                stateChip(model.fan.enabled ? "官方温控已停" : "官方温控在管",
                          tone: .green,
                          active: !model.fan.enabled)
                Spacer(minLength: 0)
                if model.fanBusy {
                    ProgressView().controlSize(.mini)
                }
            }
        }
    }

    // MARK: - 模式

    private var modeCard: some View {
        SheetSectionCard("风扇模式", icon: "slider.horizontal.3") {
            Picker("风扇模式", selection: Binding(
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
        SheetSectionCard("自动温控曲线", icon: "thermometer.medium") {
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
        SheetSectionCard("手动转速", icon: "dial.medium") {
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
            .background(Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.55), lineWidth: 0.5)
            }
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
