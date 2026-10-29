import Foundation
import SwiftUI

enum AppError: LocalizedError {
    case notConnected
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "SSH 尚未连接"
        case .message(let value): return value
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var connected = false
    @Published var connecting = false
    @Published var reconnecting = false
    @Published var activityTitle: String?
    @Published var activitySubtitle: String?
    @Published var busy = false
    @Published var status = "未连接"
    @Published var errorMessage: String?
    @Published var stats = OverviewStats()
    @Published var flashInfo = FlashInfo()
    @Published var routerInfo = RouterInfo()
    @Published var devices: [DeviceInfo] = []

    @Published var openClash = OpenClashInfo()
    @Published var ocMetrics = OpenClashMetrics()
    @Published var accessChecks = AccessCheck.Site.allCases.map { AccessCheck(site: $0) }
    @Published var history: [HistoryPoint] = []
    @Published var profiles: [RouterProfile] = []
    @Published var currentProfileID: UUID?
    @Published var moduleOrder: [OverviewModule] = OverviewModule.allCases
    @Published var hiddenModules: Set<OverviewModule> = []
    @Published var autoLogin: Bool {
        didSet { UserDefaults.standard.set(autoLogin, forKey: "autoLogin") }
    }
    /// 采集配置：现在只有一个全局刷新间隔，改完立即生效。
    @Published var pollConfig: PollConfiguration {
        didSet {
            pollConfig.save()
            if connected { startPolling() }
        }
    }
    /// 当前在看的标签页。采集只跟着它走：切到设置页就完全停下。
    @Published private(set) var activePage: AppPage = .overview

    private let ssh = SSHService()
    private var pollTask: Task<Void, Never>?
    private var activePassword: String?
    private var lastSuccessfulPoll: Date?
    private var lastReconnectAttempt: Date?
    private var lastCpuTotal: Double?
    private var lastCpuIdle: Double?
    private var lastRx: Double?
    private var lastTx: Double?
    private var lastNetDate: Date?
    private var lastOcPid = ""
    private var lastOcTicks: Double?
    private var lastOcTotal: Double?

    init() {
        autoLogin = UserDefaults.standard.object(forKey: "autoLogin") as? Bool ?? true
        pollConfig = PollConfiguration.load()
        loadProfiles()
        loadModules()
    }

    var currentProfile: RouterProfile? {
        profiles.first { $0.id == currentProfileID }
    }

    var visibleModules: [OverviewModule] {
        moduleOrder.filter { !hiddenModules.contains($0) }
    }

    func isVisible(_ module: OverviewModule) -> Bool {
        !hiddenModules.contains(module)
    }

    func setModule(_ module: OverviewModule, visible: Bool) {
        if visible { hiddenModules.remove(module) } else { hiddenModules.insert(module) }
        saveModules()
    }

    func moveModules(from source: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: source, toOffset: destination)
        saveModules()
    }

    func resetModules() {
        moduleOrder = OverviewModule.allCases
        hiddenModules = []
        saveModules()
    }

    // MARK: - Connections

    func connect(host: String, port: Int, user: String, password: String,
                 label: String = "", webPort: Int = 80) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, !password.isEmpty else {
            errorMessage = "请填写路由器地址和密码"
            return
        }

        var profile: RouterProfile
        if let index = profiles.firstIndex(where: {
            $0.host == cleanHost && $0.port == port && $0.user == user
        }) {
            profile = profiles[index]
            if !label.isEmpty { profile.label = label }
            profile.webPort = webPort
            profiles[index] = profile
        } else {
            profile = RouterProfile(label: label, host: cleanHost, port: port,
                                    user: user, webPort: webPort)
            profiles.append(profile)
        }
        currentProfileID = profile.id
        saveProfiles()
        if autoLogin {
            KeychainStore.savePassword(
                password,
                account: KeychainStore.passwordAccount(for: profile)
            )
        }
        await connect(profile: profile, password: password)
    }

    func connect(profile: RouterProfile, password: String) async {
        await disconnect(keepPassword: true)
        connecting = true
        errorMessage = nil
        status = "正在连接…"
        do {
            try await ssh.connect(
                host: profile.host,
                port: profile.port,
                user: profile.user,
                password: password
            )
            currentProfileID = profile.id
            connected = true
            connecting = false
            activePassword = password
            lastSuccessfulPoll = Date()
            lastReconnectAttempt = nil
            status = "已连接"
            await bootstrapRefresh()
            startPolling()
        } catch {
            connected = false
            connecting = false
            status = "连接失败"
            errorMessage = describe(error)
        }
    }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.localizedDescription)\n[\(ns.domain) \(ns.code)]\n\(String(describing: error))"
    }

    func autoConnectIfPossible() async {
        guard autoLogin, !connected, let profile = currentProfile,
              let password = KeychainStore.loadPassword(
                account: KeychainStore.passwordAccount(for: profile)
              ) else { return }
        await connect(profile: profile, password: password)
    }

    func switchTo(_ profile: RouterProfile) async {
        guard let password = KeychainStore.loadPassword(
            account: KeychainStore.passwordAccount(for: profile)
        ) else {
            errorMessage = "该连接没有保存密码，请重新输入"
            return
        }
        currentProfileID = profile.id
        saveProfiles()
        await connect(profile: profile, password: password)
    }

    func saveNewProfile(host: String, port: Int, user: String,
                        password: String, label: String, webPort: Int = 80) async {
        await connect(host: host, port: port, user: user, password: password,
                      label: label, webPort: webPort)
    }

    func updateProfile(_ profile: RouterProfile, host: String, port: Int,
                       user: String, password: String, label: String,
                       webPort: Int) async {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profiles[index]
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.host = cleanHost
        updated.port = port
        updated.user = user
        updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.webPort = webPort
        profiles[index] = updated
        currentProfileID = updated.id
        saveProfiles()
        if autoLogin {
            KeychainStore.savePassword(
                password,
                account: KeychainStore.passwordAccount(for: updated)
            )
        }
        await connect(profile: updated, password: password)
    }

    var currentPassword: String? {
        if let activePassword { return activePassword }
        guard let currentProfile else { return nil }
        return KeychainStore.loadPassword(
            account: KeychainStore.passwordAccount(for: currentProfile)
        )
    }

    var routerWebURL: URL? {
        guard let profile = currentProfile else { return nil }
        return URL(string: "http://\(profile.host):\(profile.webPortValue)/")
    }

    func deleteProfile(_ profile: RouterProfile) {
        KeychainStore.deletePassword(account: KeychainStore.passwordAccount(for: profile))
        profiles.removeAll { $0.id == profile.id }
        if currentProfileID == profile.id {
            currentProfileID = profiles.first?.id
        }
        saveProfiles()
    }

    func disconnect(keepPassword: Bool = false) async {
        pollTask?.cancel()
        pollTask = nil
        ssh.disconnect()
        connected = false
        reconnecting = false
        busy = false
        connecting = false
        activePassword = nil
        lastSuccessfulPoll = nil
        lastReconnectAttempt = nil
        status = "未连接"
        lastCpuTotal = nil
        lastCpuIdle = nil
        lastRx = nil
        lastTx = nil
        lastNetDate = nil
        lastOcPid = ""
        lastOcTicks = nil
        lastOcTotal = nil
        if !keepPassword, let profile = currentProfile {
            KeychainStore.deletePassword(account: KeychainStore.passwordAccount(for: profile))
        }
    }

    func resumeAfterForeground() async {
        guard connected else { return }
        if let lastSuccessfulPoll,
           Date().timeIntervalSince(lastSuccessfulPoll) < 10 {
            startPolling()
            return
        }
        await reconnect(force: true)
    }

    func manualRefresh() async {
        guard connected else { return }
        if status == "连接中断" || reconnecting ||
            (lastSuccessfulPoll.map { Date().timeIntervalSince($0) > 12 } ?? true) {
            await reconnect(force: true)
            return
        }
        await bootstrapRefresh()
    }

    func reconnect(force: Bool) async {
        guard !reconnecting, let profile = currentProfile else { return }
        if !force, let lastReconnectAttempt,
           Date().timeIntervalSince(lastReconnectAttempt) < 5 {
            return
        }
        guard let password = activePassword ?? KeychainStore.loadPassword(
            account: KeychainStore.passwordAccount(for: profile)
        ) else {
            return
        }

        lastReconnectAttempt = Date()
        reconnecting = true
        do {
            try await ssh.connect(
                host: profile.host,
                port: profile.port,
                user: profile.user,
                password: password
            )
            activePassword = password
            connected = true
            await bootstrapRefresh()
            startPolling()
            reconnecting = false
            lastReconnectAttempt = nil
            status = "已连接"
            errorMessage = nil
        } catch {
            reconnecting = false
            status = "连接中断"
            errorMessage = describe(error)
            if connected {
                startPolling()
            }
        }
    }

    func logout() async {
        await disconnect(keepPassword: false)
        for profile in profiles {
            KeychainStore.deletePassword(account: KeychainStore.passwordAccount(for: profile))
        }
        profiles = []
        currentProfileID = nil
        saveProfiles()
        stats = OverviewStats()
        routerInfo = RouterInfo()
        devices = []
        history = []
    }

    // MARK: - SSH

    func execute(_ command: String) async throws -> String {
        try await ssh.execute(command)
    }

    // MARK: - Polling
    //
    // 采集跟着页面走：只有当前标签页要用的数据才会被采集，切到设置页就完全停下，
    // 路由器不用替一个看不见的界面干活。同一次刷新里的所有项拼成**一条**命令、
    // 一个 shell 跑完，全部以 nice -n 19 执行，所以进程数不会随项数增加。

    /// 当前页面要采集的数据项。
    var activeItems: [PollItem] {
        pollConfig.items(on: activePage)
    }

    /// 当前页面上会反复采集的项（OpenClash 配置只在进页面时取一次）。
    private var periodicItems: [PollItem] {
        activeItems.filter(\.isPeriodic)
    }

    var pollSeconds: Double { pollConfig.clampedSeconds }

    func setPollSeconds(_ value: Double) {
        var config = pollConfig
        config.setSeconds(value)
        pollConfig = config
    }

    /// 切换标签页：立刻为这一页取一次数据，然后按新的一组项继续轮询。
    func setActivePage(_ page: AppPage) {
        guard page != activePage else { return }
        activePage = page
        guard connected else { return }
        startPolling(refreshNow: true)
    }

    /// 轮询循环：固定间隔，跑的永远是当前页面的那一组数据。
    private func startPolling(refreshNow: Bool = false) {
        pollTask?.cancel()
        pollTask = nil
        guard !periodicItems.isEmpty else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if refreshNow {
                // 切页后的第一轮把这一页的项全取一次（包括只在进页面时取的那几项）
                await self.pollTick(includeOnce: true)
                if Task.isCancelled { return }
            }
            while !Task.isCancelled {
                let interval = self.pollSeconds
                try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
                if Task.isCancelled { return }
                await self.pollTick()
            }
        }
    }

    /// App 进入后台时停掉轮询，回前台由 resumeAfterForeground() 重新拉起。
    func pausePolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 连接后的首次填充：先取当前页面的数据（界面立刻有数字），再补静态信息。
    private func bootstrapRefresh() async {
        do {
            try await runItems(activeItems)
            lastSuccessfulPoll = Date()
        } catch {
            status = "连接中断"
            return
        }
        await refreshInfo()
    }

    /// 一轮：把当前页面要采集的项拼成一条命令发出去。
    /// includeOnce 为真时连「只在进页面时取」的项一起跑（切页后的第一轮）。
    private func pollTick(includeOnce: Bool = false) async {
        guard connected else { return }
        let items = includeOnce ? activeItems : periodicItems
        guard !items.isEmpty else { return }
        do {
            try await runItems(items)
            lastSuccessfulPoll = Date()
            if status != "已连接" { status = "已连接" }
        } catch {
            status = "连接中断"
            if !reconnecting, activePassword != nil {
                Task { await self.reconnect(force: false) }
            }
        }
    }

    /// 跑一组数据项。OpenClash 状态和它的指标必须分成两条命令：
    /// 指标里要用的端口和密钥，来自状态查询的结果。
    private func runItems(_ items: [PollItem]) async throws {
        guard !items.isEmpty else { return }
        let stateItems = items.filter { $0 == .clashState }
        let otherItems = items.filter { $0 != .clashState }
        if !stateItems.isEmpty {
            apply(parseSections(try await execute(command(for: stateItems))), items: stateItems)
        }
        if !otherItems.isEmpty {
            apply(parseSections(try await execute(command(for: otherItems))), items: otherItems)
        }
    }

    private func apply(_ sections: [String: String], items: [PollItem]) {
        if items.contains(.core) { applyCore(sections) }
        if items.contains(.sensors) {
            updateSensors(temp: sections["TEMP"] ?? "", fan: sections["FAN"] ?? "")
        }
        if items.contains(.flash) { updateFlash(sections["FLASH"] ?? "") }
        if items.contains(.devices) { updateDevices(sections["LEASES"] ?? "") }
        if items.contains(.clashState) {
            openClash = parseOpenClashInfo(sections, current: openClash)
        }
        if items.contains(.clashTraffic) || items.contains(.clashConnections) {
            applyClashPresence(sections)
            applyMetrics(sections)
        }
    }

    /// 指标脚本里自带 pidof 和面板端口，所以每轮都能自己确认运行状态，
    /// 不用等状态档先跑过——旧版这里就是「流量和内核状态一直不更新」的根源。
    private func applyClashPresence(_ sections: [String: String]) {
        var info = openClash
        let state = firstLine(sections["OCSTATE"])
        if !state.isEmpty {
            info.installed = ["running", "stopped", "installed"].contains(state)
            info.running = state == "running"
        }
        if let port = Int(firstLine(sections["OCPORT"])), port > 0 {
            info.panelPort = port
        }
        if sections["OCSECRET"] != nil {
            info.secret = firstLine(sections["OCSECRET"])
        }
        info.panelURL = buildPanelURL(info)
        openClash = info
    }

    private func applyCore(_ sections: [String: String]) {
        updateCPU(sections["STAT"] ?? "")
        updateMemory(sections["MEMINFO"] ?? "")
        let wan = parseWanDevice(sections["ROUTE"] ?? "")
        if !wan.isEmpty, wan != stats.wanDevice {
            stats.wanDevice = wan
            lastRx = nil
            lastTx = nil
            lastNetDate = nil
        }
        updateNetwork(sections["DEV"] ?? "")
        if let value = firstLine(sections["UPTIME"]).split(separator: " ").first,
           let uptime = Double(value) {
            stats.uptime = uptime
        }
        let loadValues = firstLine(sections["LOADAVG"])
            .split(separator: " ")
            .compactMap { Double($0) }
        if loadValues.count >= 1 { stats.load = loadValues[0] }
        if loadValues.count >= 2 { stats.load5 = loadValues[1] }
        if loadValues.count >= 3 { stats.load15 = loadValues[2] }
        appendHistory()
    }

    /// OpenClash 指标：/traffic 和 /connections 可能只成功一个，哪段有就更新哪段，
    /// 缺的部分保持上一次的值，不会因为一次失败就把数字清成 0。
    private func applyMetrics(_ sections: [String: String]) {
        var value = ocMetrics
        var reachable = false
        if let data = json(sections["TRAFFIC"]),
           let up = number(data["up"]), let down = number(data["down"]) {
            value.upload = up
            value.download = down
            reachable = true
        }
        if let data = json(sections["CONN"]) {
            value.uploadTotal = UInt64(number(data["uploadTotal"]) ?? 0)
            value.downloadTotal = UInt64(number(data["downloadTotal"]) ?? 0)
            if let rows = data["connections"] as? [[String: Any]] {
                value.connections = rows.count
            }
            reachable = true
        }
        if let status = sections["OCSTATUS"] {
            let memory = parseVmRSS(status)
            if memory > 0 { value.memory = memory }
        }
        if sections["OCSTAT"] != nil, sections["SYSTAT"] != nil {
            updateCoreCPU(sections, into: &value)
        }
        // 负载取 5 分钟均值除以核数，跟指标同一条命令取回来，不额外 fork。
        let load = firstLine(sections["LOADAVG"])
            .split(separator: " ")
            .compactMap { Double($0) }
        if load.count >= 2 {
            let cores = max(1, Double(routerInfo.cpuCores > 0 ? routerInfo.cpuCores : 1))
            value.load = max(0, load[1] / cores * 100)
        }
        value.apiReachable = reachable
        ocMetrics = value
    }

    /// JSONSerialization 出来的数字都是 NSNumber，统一走这里取，整数也能取到。
    private func number(_ any: Any?) -> Double? {
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? Double { return value }
        return nil
    }
    func refreshInfo() async {
        do {
            let sections = parseSections(try await execute(infoCommand))
            var value = RouterInfo()
            value.model = firstLine(sections["MODEL"])
            value.hostname = firstLine(sections["HOST"])
            value.kernel = firstLine(sections["KERNEL"])
            value.architecture = firstLine(sections["ARCH"])
            value.cpuModel = parseCPUModel(sections["CPUINFO"] ?? "")
            value.cpuCores = parseCPUCores(sections["CPUINFO"] ?? "")
            value.firmware = parseRelease(sections["RELEASE"] ?? "")
            routerInfo = value
            let wan = parseWanDevice(sections["ROUTE"] ?? "")
            if !wan.isEmpty { stats.wanDevice = wan }
        } catch {
            // 静态信息拿不到就先不显示，别把连接状态改成错误
        }
    }

    func refreshOpenClash() async {
        do {
            let sections = parseSections(try await execute(command(for: [.clashState])))
            openClash = parseOpenClashInfo(sections, current: openClash)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startOpenClash() async {
        if openClash.running {
            errorMessage = nil
            status = "OpenClash 已启动"
            return
        }
        await action("uci -q set openclash.config.enable='1'; uci -q commit openclash; /etc/init.d/openclash start >/dev/null 2>&1; echo done",
                     title: "正在启动", subtitle: "正在启动 OpenClash…")
    }

    func stopOpenClash() async {
        if !openClash.running {
            errorMessage = nil
            status = "OpenClash 已关闭"
            return
        }
        await action("uci -q set openclash.config.enable='0'; uci -q commit openclash; /etc/init.d/openclash stop >/dev/null 2>&1; echo done",
                     title: "正在关闭", subtitle: "正在停止 OpenClash…")
    }

    func restartOpenClash() async {
        await action("uci -q set openclash.config.enable='1'; uci -q commit openclash; /etc/init.d/openclash restart >/dev/null 2>&1; echo done",
                     title: "正在重启", subtitle: "正在重启 OpenClash…")
    }

    func switchMode(_ mode: String) async {
        await action("uci -q set openclash.config.proxy_mode='\(mode)'; uci -q set 'openclash.@overwrite[0].proxy_mode'='\(mode)'; uci -q commit openclash; /etc/init.d/openclash restart >/dev/null 2>&1; echo done",
                     title: "正在切换模式", subtitle: "正在应用新的代理模式…")
    }

    func switchConfig(_ name: String) async {
        guard !name.isEmpty, !name.contains("'") else { return }
        await action("uci -q set openclash.config.config_path='/etc/openclash/config/\(name)'; uci -q set openclash.config.enable='1'; uci -q commit openclash; /etc/init.d/openclash restart >/dev/null 2>&1; echo done",
                     title: "正在切换配置", subtitle: "正在应用新的配置文件…")
    }

    private func action(_ command: String, title: String, subtitle: String) async {
        busy = true
        activityTitle = title
        activitySubtitle = subtitle
        defer {
            busy = false
            activityTitle = nil
            activitySubtitle = nil
        }
        do {
            _ = try await execute(command)
            try? await Task.sleep(for: .seconds(2))
            await refreshOpenClash()
            status = "已连接"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkAccess() async {
        guard connected else { return }
        busy = true
        defer { busy = false }
        do {
            let sections = parseSections(try await execute(accessCommand))
            var results: [AccessCheck.Site: (Bool, Int)] = [:]
            for line in (sections["CHECK"] ?? "").split(separator: "\n") {
                let fields = line.split(separator: "\t").map(String.init)
                guard fields.count >= 4, fields[0] == "C",
                      let site = AccessCheck.Site(rawValue: fields[1]) else { continue }
                results[site] = (fields[2] == "1", Int(fields[3]) ?? 0)
            }
            accessChecks = AccessCheck.Site.allCases.map { site in
                let previous = accessChecks.first { $0.site == site }
                var check = AccessCheck(site: site, tested: true)
                if let result = results[site] {
                    check.success = result.0
                    check.latency = result.1
                    check.history = Array(((previous?.history ?? []) + [result.1]).suffix(10))
                }
                return check
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parsing

    private func parseOpenClashInfo(_ sections: [String: String],
                                    current: OpenClashInfo) -> OpenClashInfo {
        var info = current
        let state = firstLine(sections["OCSTATE"])
        info.installed = ["running", "stopped", "installed"].contains(state)
        info.running = state == "running"
        if !info.running {
            ocMetrics = OpenClashMetrics()
        }
        info.mode = firstLine(sections["OCMODE"])
        if info.mode.isEmpty { info.mode = "rule" }
        info.config = (firstLine(sections["OCCONFIG"]) as NSString).lastPathComponent
        info.configs = (sections["OCCONFIGS"] ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        let port = Int(firstLine(sections["OCPORT"])) ?? 9090
        info.panelPort = port
        info.secret = firstLine(sections["OCSECRET"])
        info.dashboards = (sections["OCDIRS"] ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        var dash = firstLine(sections["OCDASH"]).lowercased()
        if dash.isEmpty || (!info.dashboards.isEmpty && !info.dashboards.contains(dash)) {
            dash = info.dashboards.first ?? "zashboard"
        }
        info.dashboard = dash
        info.panelURL = buildPanelURL(info)
        return info
    }

    private func buildPanelURL(_ info: OpenClashInfo) -> URL? {
        guard let profile = currentProfile else { return nil }
        let base = "http://\(profile.host):\(info.panelPort)/ui/\(info.dashboard)"
        let host = profile.host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profile.host
        let secret = info.secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let secretPart = secret.isEmpty ? "" : "&secret=\(secret)"
        switch info.dashboard {
        case "yacd":
            return URL(string: "\(base)/?hostname=\(host)&port=\(info.panelPort)\(secretPart)")
        case "dashboard":
            return URL(string: "\(base)/#/?host=\(host)&port=\(info.panelPort)\(secretPart)")
        case "zashboard", "metacubexd":
            return URL(string: "\(base)/#/setup?hostname=\(host)&port=\(info.panelPort)\(secretPart)")
        default:
            return URL(string: base + "/")
        }
    }

    private func updateCPU(_ text: String) {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("cpu ") }) else { return }
        let values = line.split(separator: " ").dropFirst().compactMap { Double($0) }
        guard values.count >= 4 else { return }
        let total = values.prefix(8).reduce(0, +)
        let idle = values[3] + (values.count > 4 ? values[4] : 0)
        if let lastTotal = lastCpuTotal, let lastIdle = lastCpuIdle {
            let deltaTotal = total - lastTotal
            let deltaIdle = idle - lastIdle
            if deltaTotal > 0 {
                stats.cpu = max(0, min(100, (deltaTotal - deltaIdle) / deltaTotal * 100))
            }
        }
        lastCpuTotal = total
        lastCpuIdle = idle
    }

    private func updateMemory(_ text: String) {
        var total: UInt64 = 0
        var available: UInt64 = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { continue }
            if parts[0] == "MemTotal:" { total = (UInt64(parts[1]) ?? 0) * 1024 }
            if parts[0] == "MemAvailable:" { available = (UInt64(parts[1]) ?? 0) * 1024 }
        }
        stats.memoryTotal = total
        stats.memoryUsed = total > available ? total - available : 0
    }

    private func updateFlash(_ text: String) {
        var total: UInt64 = 0
        var system: UInt64 = 0
        var app: UInt64 = 0
        var available: UInt64 = 0

        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count >= 2 else { continue }
            switch fields[0] {
            case "SYS":
                system = (UInt64(fields[1]) ?? 0) * 1024
            case "TOTAL" where fields.count >= 6:
                total = (UInt64(fields[1]) ?? 0) * 1024
                app = (UInt64(fields[3]) ?? 0) * 1024
                available = (UInt64(fields[5]) ?? 0) * 1024
            case "ROOT" where fields.count >= 4:
                total = (UInt64(fields[1]) ?? 0) * 1024
                app = (UInt64(fields[2]) ?? 0) * 1024
                available = (UInt64(fields[3]) ?? 0) * 1024
            default:
                break
            }
        }

        guard total > 0 else { return }
        if system == 0 {
            let remainder = app &+ available
            system = total > remainder ? total - remainder : 0
        }
        if app == 0 {
            let remainder = system &+ available
            app = total > remainder ? total - remainder : 0
        }
        if available == 0 {
            let remainder = system &+ app
            available = total > remainder ? total - remainder : 0
        }
        flashInfo = FlashInfo(
            total: total,
            systemUsed: system,
            appUsed: app,
            available: available
        )
    }

    private func updateNetwork(_ text: String) {
        guard !stats.wanDevice.isEmpty else { return }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(stats.wanDevice + ":") else { continue }
            let numbers = trimmed.split(separator: ":").dropFirst().joined()
                .split(separator: " ").compactMap { Double($0) }
            guard numbers.count >= 9 else { return }
            let rx = numbers[0]
            let tx = numbers[8]
            let now = Date()
            if let lastRx, let lastTx, let lastNetDate {
                let elapsed = now.timeIntervalSince(lastNetDate)
                if elapsed > 0 {
                    stats.download = max(0, (rx - lastRx) / elapsed)
                    stats.upload = max(0, (tx - lastTx) / elapsed)
                    stats.sessionDownload += max(0, rx - lastRx)
                    stats.sessionUpload += max(0, tx - lastTx)
                }
            }
            lastRx = rx
            lastTx = tx
            lastNetDate = now
            return
        }
    }

    private func updateSensors(temp: String, fan: String) {
        let temps = temp.split(separator: "\n").compactMap { line -> Double? in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "T" else { return nil }
            let value = Double(parts[1]) ?? 0
            return value > 1000 ? value / 1000 : value
        }
        if let value = temps.max(), value > 0 { stats.temperature = value }
        let fans = fan.split(separator: "\n").compactMap { line -> Double? in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "F" else { return nil }
            return Double(parts[1])
        }
        if let value = fans.max(), value > 0 { stats.fanRPM = value }
    }

    private func updateDevices(_ text: String) {
        var result: [DeviceInfo] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count >= 4 else { continue }
            result.append(DeviceInfo(
                ip: fields[2],
                mac: fields[1],
                name: fields[3] == "*" ? fields[2] : fields[3]
            ))
        }
        devices = result
    }

    private func updateCoreCPU(_ sections: [String: String], into value: inout OpenClashMetrics) {
        let pid = firstLine(sections["OCPID"])
        let stat = sections["OCSTAT"] ?? ""
        let sys = sections["SYSTAT"] ?? ""
        guard let procTicks = parseProcTicks(stat), let total = parseTotalTicks(sys) else { return }
        if pid != lastOcPid {
            lastOcPid = pid
            lastOcTicks = nil
            lastOcTotal = nil
        }
        if let lastTicks = lastOcTicks, let lastTotal = lastOcTotal,
           total > lastTotal, procTicks >= lastTicks {
            value.cpu = max(0, (procTicks - lastTicks) / (total - lastTotal) * 100)
        }
        lastOcTicks = procTicks
        lastOcTotal = total
    }

    private func parseVmRSS(_ status: String) -> UInt64 {
        for line in status.split(separator: "\n") where line.hasPrefix("VmRSS:") {
            let parts = line.split(separator: " ")
            if parts.count >= 2 { return (UInt64(parts[1]) ?? 0) * 1024 }
        }
        return 0
    }

    private func parseProcTicks(_ stat: String) -> Double? {
        guard let close = stat.lastIndex(of: ")") else { return nil }
        let rest = stat[stat.index(after: close)...].split(separator: " ")
        guard rest.count >= 13 else { return nil }
        return (Double(rest[11]) ?? 0) + (Double(rest[12]) ?? 0)
    }

    private func parseTotalTicks(_ stat: String) -> Double? {
        guard let line = stat.split(separator: "\n").first else { return nil }
        let fields = line.split(separator: " ")
        guard fields.count >= 5 else { return nil }
        return fields.dropFirst().prefix(8).compactMap { Double($0) }.reduce(0, +)
    }

    /// WAN 口取自 /proc/net/route：Destination 为 00000000 的那行就是默认路由，
    /// 比每次 `ip route show default` 便宜得多。也兼容 `ip route` 的 "dev X" 形式。
    private func parseWanDevice(_ route: String) -> String {
        if let range = route.range(of: "dev ") {
            let value = route[range.upperBound...].split(separator: " ").first.map(String.init) ?? ""
            if !value.isEmpty { return value }
        }
        for line in route.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, fields[0] != "Iface" else { continue }
            if fields[1] == "00000000" { return fields[0] }
        }
        return ""
    }

    private func parseCPUModel(_ text: String) -> String {
        var fallback = ""
        for line in text.split(separator: "\n") {
            let lower = line.lowercased()
            let value = (line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "")
                .trimmingCharacters(in: .whitespaces)
            if lower.contains("model name") || lower.contains("cpu model") {
                if !value.isEmpty { return value }
            }
            if lower.hasPrefix("processor") && fallback.isEmpty {
                fallback = value
            }
        }
        return fallback
    }

    private func parseCPUCores(_ text: String) -> Int {
        let count = text
            .split(separator: "\n")
            .filter { $0.lowercased().hasPrefix("processor") }
            .count
        return count
    }

    private func parseRelease(_ text: String) -> String {
        for line in text.split(separator: "\n") {
            if line.contains("DISTRIB_DESCRIPTION") || line.contains("PRETTY_NAME") {
                let value = (line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    private func appendHistory() {
        history.append(HistoryPoint(
            date: Date(),
            cpu: stats.cpu,
            memory: memoryFraction * 100,
            download: stats.download,
            upload: stats.upload
        ))
        if history.count > 40 { history.removeFirst(history.count - 40) }
    }

    var memoryFraction: Double {
        stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0
    }

    private func splitSections(_ raw: String) -> [String: String] {
        parseSections(raw)
    }

    private func parseSections(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var key: String?
        for line in raw.replacingOccurrences(of: "\r", with: "").split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            if line.hasPrefix("@@") {
                key = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                result[key!] = ""
            } else if let key {
                result[key, default: ""] += String(line) + "\n"
            }
        }
        return result
    }

    private func firstLine(_ text: String?) -> String {
        guard let text else { return "" }
        return text.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func json(_ text: String?) -> [String: Any]? {
        guard let text, let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let value = String(text[start...end])
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: "profiles"),
              let decoded = try? JSONDecoder().decode([RouterProfile].self, from: data) else {
            return
        }
        profiles = decoded
        if let raw = UserDefaults.standard.string(forKey: "currentProfileID"),
           let id = UUID(uuidString: raw) {
            currentProfileID = id
        }
        if currentProfileID == nil { currentProfileID = profiles.first?.id }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "profiles")
        }
        UserDefaults.standard.set(currentProfileID?.uuidString, forKey: "currentProfileID")
    }

    private func loadModules() {
        if let raw = UserDefaults.standard.stringArray(forKey: "moduleOrder") {
            let values = raw.compactMap(OverviewModule.init(rawValue:))
            if !values.isEmpty { moduleOrder = values }
        }
        let hidden = UserDefaults.standard.stringArray(forKey: "hiddenModules") ?? []
        hiddenModules = Set(hidden.compactMap(OverviewModule.init(rawValue:)))
        let missing = OverviewModule.allCases.filter { !moduleOrder.contains($0) }
        for module in missing {
            if module == .flash,
               let resourcesIndex = moduleOrder.firstIndex(of: .resources) {
                moduleOrder.insert(.flash, at: resourcesIndex + 1)
            } else {
                moduleOrder.append(module)
            }
        }
    }

    private func saveModules() {
        UserDefaults.standard.set(moduleOrder.map(\.rawValue), forKey: "moduleOrder")
        UserDefaults.standard.set(hiddenModules.map(\.rawValue), forKey: "hiddenModules")
    }
}

// MARK: - Commands

private extension AppModel {
    /// 让路由器以最低调度优先级执行这段脚本。监控不该跟转发、防火墙、
    /// OpenClash 抢 CPU；万一固件里没有 nice，就退回普通执行，不影响功能。
    func lowPriority(_ script: String) -> String {
        let body = script
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "'\\''")
        return "if command -v nice >/dev/null 2>&1; then nice -n 19 sh -c '\(body)'; else sh -c '\(body)'; fi"
    }

    /// 连接后取一次静态信息。
    /// OpenClash 的运行状态改由 pidof 判断：`/etc/init.d/openclash status`
    /// 在部分固件里会 source 一整套 shell 函数、甚至去列防火墙规则，
    /// 弱 CPU 上这是最容易被忽略的一次高开销调用。
    var infoCommand: String {
        lowPriority("""
        echo @@MODEL; cat /tmp/sysinfo/model 2>/dev/null
        echo @@HOST; cat /proc/sys/kernel/hostname 2>/dev/null
        echo @@RELEASE; cat /etc/openwrt_release 2>/dev/null
        echo @@KERNEL; uname -r 2>/dev/null
        echo @@ARCH; uname -m 2>/dev/null
        echo @@CPUINFO; head -n 60 /proc/cpuinfo 2>/dev/null
        echo @@UPTIME; cat /proc/uptime 2>/dev/null
        echo @@LOAD; cat /proc/loadavg 2>/dev/null
        echo @@ROUTE; cat /proc/net/route 2>/dev/null
        echo @@OCSTATE
        set -- $(pidof clash clash_meta clash_tun clash_lite mihomo 2>/dev/null); OCPID=$1
        if [ -n "$OCPID" ]; then echo running
        elif [ -d /usr/share/openclash ] || [ -x /etc/init.d/openclash ]; then echo stopped
        else echo missing; fi
        echo @@OCPID; echo "$OCPID"
        echo @@OCMODE; uci -q get openclash.config.proxy_mode 2>/dev/null
        echo @@OCCONFIG; uci -q get openclash.config.config_path 2>/dev/null
        echo @@OCCONFIGS; ls /etc/openclash/config/*.yaml /etc/openclash/config/*.yml 2>/dev/null | xargs -n1 basename 2>/dev/null
        echo @@OCPORT; p=$(uci -q get openclash.config.cn_port 2>/dev/null); [ -n "$p" ] || p=9090; echo "$p"
        echo @@OCSECRET; uci -q get openclash.config.dashboard_password 2>/dev/null
        echo @@OCDASH; uci -q get openclash.config.default_dashboard 2>/dev/null
        echo @@OCDIRS; for d in zashboard metacubexd yacd dashboard; do [ -d "/usr/share/openclash/ui/$d" ] && echo "$d"; done
        true
        """)
    }

    /// 每个数据项对应一段脚本。同一档里的项用换行拼成一条命令，交给同一个 shell 跑完，
    /// 所以“项多了”只是脚本变长，不会多 fork 进程。
    func script(for item: PollItem) -> String {
        switch item {
        case .core:
            return """
            LC_ALL=C awk 'FNR==1{n=split(FILENAME,p,"/"); print "@@" toupper(p[n])} {print}' /proc/stat /proc/meminfo /proc/net/dev /proc/uptime /proc/loadavg /proc/net/route 2>/dev/null

            """
        case .sensors:
            return """
            echo @@TEMP
            for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do
              if [ -r "$f" ]; then read -r v < "$f"; echo "T $v"; fi
            done
            echo @@FAN
            for f in /sys/class/hwmon/hwmon*/fan*_input; do
              if [ -r "$f" ]; then read -r v < "$f"; echo "F $v"; fi
            done
            true

            """
        case .flash:
            return """
            echo @@FLASH
            df -k /rom /overlay / 2>/dev/null | awk 'NR>1{if($NF=="/rom")print "SYS",$3; else if($NF=="/overlay")print "TOTAL",$2,"APP",$3,"AVAIL",$4; else if($NF=="/")print "ROOT",$2,$3,$4}'

            """
        case .devices:
            return """
            echo @@LEASES
            cat /tmp/dhcp.leases 2>/dev/null

            """
        case .clashState:
            return """
            echo @@OCSTATE
            set -- $(pidof clash clash_meta clash_tun clash_lite mihomo 2>/dev/null); OCPID=$1
            if [ -n "$OCPID" ]; then echo running
            elif [ -d /usr/share/openclash ] || [ -x /etc/init.d/openclash ]; then echo stopped
            else echo missing; fi
            echo @@OCPID; echo "$OCPID"
            echo @@OCMODE; uci -q get openclash.config.proxy_mode 2>/dev/null
            echo @@OCCONFIG; uci -q get openclash.config.config_path 2>/dev/null
            echo @@OCCONFIGS; ls /etc/openclash/config/*.yaml /etc/openclash/config/*.yml 2>/dev/null | xargs -n1 basename 2>/dev/null
            echo @@OCPORT; p=$(uci -q get openclash.config.cn_port 2>/dev/null); [ -n "$p" ] || p=9090; echo "$p"
            echo @@OCSECRET; uci -q get openclash.config.dashboard_password 2>/dev/null
            echo @@OCDASH; uci -q get openclash.config.default_dashboard 2>/dev/null
            echo @@OCDIRS; for d in zashboard metacubexd yacd dashboard; do [ -d "/usr/share/openclash/ui/$d" ] && echo "$d"; done
            true

            """
        case .clashTraffic, .clashConnections:
            return metricsScript
        }
    }

    /// OpenClash 指标：一条命令里把状态、流量、连接表、内核内存/CPU、负载全取回来。
    ///
    /// 端口和密钥在这里自己查，不再依赖“状态档先跑过”。旧版靠状态查询把端口写进
    /// openClash.panelPort，一旦那条命令失败、或者切页时顺序不对，/traffic 就打在
    /// 默认 9090 上、或者带着错的密钥返回 4xx，界面就永远停在 0——
    /// 这正是“实时流量和内核状态不更新”的直接原因。
    /// 取数做了三层兜底：带密钥 curl → 不带密钥 curl → wget（部分固件只有 wget）。
    var metricsScript: String {
        lowPriority("""
        CURL=$(command -v curl 2>/dev/null)
        WGET=$(command -v wget 2>/dev/null)
        PORT=$(uci -q get openclash.config.cn_port 2>/dev/null)
        [ -n "$PORT" ] || PORT=9090
        SECRET=$(uci -q get openclash.config.dashboard_password 2>/dev/null)
        set -- $(pidof clash clash_meta clash_tun clash_lite mihomo 2>/dev/null); OCPID=$1
        echo @@OCSTATE
        if [ -n "$OCPID" ]; then echo running
        elif [ -d /usr/share/openclash ] || [ -x /etc/init.d/openclash ]; then echo stopped
        else echo missing; fi
        echo @@OCPID; echo "$OCPID"
        echo @@OCPORT; echo "$PORT"
        echo @@OCSECRET; echo "$SECRET"
        echo @@TRAFFIC
        T=""
        if [ -n "$OCPID" ] && [ -n "$CURL" ]; then
          if [ -n "$SECRET" ]; then T=$($CURL -s -f -m 3 -H "Authorization: Bearer $SECRET" "http://127.0.0.1:$PORT/traffic" 2>/dev/null); fi
          [ -n "$T" ] || T=$($CURL -s -f -m 3 "http://127.0.0.1:$PORT/traffic" 2>/dev/null)
        fi
        if [ -z "$T" ] && [ -n "$OCPID" ] && [ -n "$WGET" ]; then
          T=$($WGET -q -O - -T 3 "http://127.0.0.1:$PORT/traffic" 2>/dev/null)
        fi
        echo "$T"
        echo @@CONN
        C=""
        if [ -n "$OCPID" ] && [ -n "$CURL" ]; then
          if [ -n "$SECRET" ]; then C=$($CURL -s -f -m 3 -H "Authorization: Bearer $SECRET" "http://127.0.0.1:$PORT/connections" 2>/dev/null); fi
          [ -n "$C" ] || C=$($CURL -s -f -m 3 "http://127.0.0.1:$PORT/connections" 2>/dev/null)
        fi
        if [ -z "$C" ] && [ -n "$OCPID" ] && [ -n "$WGET" ]; then
          C=$($WGET -q -O - -T 3 "http://127.0.0.1:$PORT/connections" 2>/dev/null)
        fi
        echo "$C"
        echo @@OCSTATUS
        if [ -n "$OCPID" ]; then awk '/^VmRSS|^Threads/' /proc/$OCPID/status 2>/dev/null; fi
        echo @@OCSTAT
        if [ -n "$OCPID" ]; then cat /proc/$OCPID/stat 2>/dev/null; fi
        echo @@SYSTAT
        read -r SY < /proc/stat 2>/dev/null; echo "$SY"
        echo @@LOADAVG
        read -r LD < /proc/loadavg 2>/dev/null; echo "$LD"
        true

        """)
    }
    /// 把同一页的项拼成一条命令：同一个 shell 里按顺序跑完，只有一次进程创建。
    /// 有几项共用一个脚本（比如流量和连接数合成的一条），这里按内容去重，避免重复执行。
    func command(for items: [PollItem]) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        for item in items {
            let body = script(for: item)
            if seen.insert(body).inserted { parts.append(body) }
        }
        return lowPriority(parts.joined(separator: "\n"))
    }

    var accessCommand: String {
        lowPriority("""
        echo @@CHECK
        check(){ key=$1; domain=$2; r=$(curl -sIL -m 5 -o /dev/null -w '%{http_code} %{time_total}' "https://$domain" 2>/dev/null); code=${r%% *}; sec=${r##* }
        if [ -n "$code" ] && [ "$code" != "000" ] && [ -n "$sec" ]; then
          ms=$(awk "BEGIN{printf \\"%d\\", $sec*1000}")
          printf 'C\\t%s\\t1\\t%s\\n' "$key" "$ms"
        else
          printf 'C\\t%s\\t0\\t0\\n' "$key"
        fi; }
        check baidu www.baidu.com; check netease music.163.com; check github github.com; check youtube www.youtube.com
        """)
    }
}

func formatBytes(_ value: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var number = max(0, value)
    var index = 0
    while number >= 1024 && index < units.count - 1 {
        number /= 1024
        index += 1
    }
    return String(format: index == 0 ? "%.0f %@" : "%.1f %@", number, units[index])
}

func formatFlashBytes(_ value: UInt64) -> String {
    let bytes = Double(value)
    if bytes >= 1024 * 1024 * 1024 {
        return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
    }
    if bytes >= 1024 * 1024 {
        return String(format: "%.1f MB", bytes / (1024 * 1024))
    }
    return String(format: "%.0f KB", bytes / 1024)
}

func formatSpeed(_ value: Double) -> String {
    formatBytes(value) + "/s"
}

func formatUptime(_ seconds: Double) -> String {
    let total = Int(seconds)
    let days = total / 86400
    let hours = (total % 86400) / 3600
    let minutes = (total % 3600) / 60
    if days > 0 { return "\(days)天 \(hours)小时" }
    if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
    return "\(minutes)分钟"
}
