import Foundation

enum OverviewModule: String, CaseIterable, Codable, Identifiable {
    case speed
    case resources
    case flash
    case hardware
    case devices
    case ports
    case openclash
    case trend
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: return "实时速度"
        case .resources: return "资源占用"
        case .flash: return "闪存"
        case .hardware: return "硬件状态"
        case .devices: return "连接设备"
        case .ports: return "网络端口"
        case .openclash: return "网络代理"
        case .trend: return "资源趋势"
        case .system: return "系统信息"
        }
    }

    var subtitle: String {
        switch self {
        case .speed: return "上下行速率与速度曲线"
        case .resources: return "CPU 与内存使用率"
        case .flash: return "系统、应用程序与可用空间"
        case .hardware: return "温度和风扇转速"
        case .devices: return "DHCP 租约设备"
        case .ports: return "LAN 端口和 LAN 桥接"
        case .openclash: return "OpenClash 状态入口"
        case .trend: return "最近两分钟 CPU/内存"
        case .system: return "主机、固件、内核与负载"
        }
    }

    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .resources: return "cpu"
        case .flash: return "internaldrive"
        case .hardware: return "thermometer.medium"
        case .devices: return "laptopcomputer.and.iphone"
        case .ports: return "cable.connector"
        case .openclash: return "shield.lefthalf.filled"
        case .trend: return "chart.xyaxis.line"
        case .system: return "info.circle"
        }
    }
}

struct RouterProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var host: String
    var port: Int
    var user: String
    var webPort: Int? = nil

    var title: String { label.isEmpty ? host : label }
    var subtitle: String { "\(user)@\(host):\(port)" }
    var webPortValue: Int {
        guard let webPort, (1...65535).contains(webPort) else { return 80 }
        return webPort
    }
}

struct DeviceInfo: Identifiable {
    let id = UUID()
    var ip: String
    var mac: String
    var name: String
}

struct PortInfo: Identifiable {
    let id = UUID()
    var name: String
    var state: String
    var speed: String
    var duplex: String
    var rx: UInt64
    var tx: UInt64
    var ip: String
    var bridgePorts: Int
}

struct OverviewStats {
    var cpu: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var download: Double = 0
    var upload: Double = 0
    var sessionDownload: Double = 0
    var sessionUpload: Double = 0
    var uptime: Double = 0
    var load: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    var temperature: Double?
    var fanRPM: Double?
    var wanDevice = ""
}

struct RouterInfo {
    var hostname = ""
    var model = ""
    var architecture = ""
    var firmware = ""
    var kernel = ""
    var cpuModel = ""
    var cpuCores = 0
    var load = ""
}

struct OpenClashInfo {
    var installed = false
    var running = false
    var mode = "rule"
    var config = ""
    var configs: [String] = []
    var panelPort = 9090
    var secret = ""
    var dashboard = ""
    var dashboards: [String] = []
    var panelURL: URL?
}

struct OpenClashMetrics {
    var upload: Double = 0
    var download: Double = 0
    var uploadTotal: UInt64 = 0
    var downloadTotal: UInt64 = 0
    var connections: Int = 0
    var memory: UInt64 = 0
    var cpu: Double = 0
    var load: Double = 0
}

struct AccessCheck: Identifiable {
    enum Site: String, CaseIterable, Identifiable {
        case baidu
        case netease
        case github
        case youtube

        var id: String { rawValue }

        var title: String {
            switch self {
            case .baidu: return "百度搜索"
            case .netease: return "网易云音乐"
            case .github: return "GitHub"
            case .youtube: return "YouTube"
            }
        }

        var domain: String {
            switch self {
            case .baidu: return "www.baidu.com"
            case .netease: return "music.163.com"
            case .github: return "github.com"
            case .youtube: return "www.youtube.com"
            }
        }
    }

    let id = UUID()
    var site: Site
    var success = false
    var latency: Int = 0
    var tested = false
    var history: [Int] = []
}

struct FlashInfo {
    var total: UInt64 = 0
    var systemUsed: UInt64 = 0
    var appUsed: UInt64 = 0
    var available: UInt64 = 0

    var hasData: Bool { total > 0 }

    var systemFraction: Double {
        total > 0 ? min(1, Double(systemUsed) / Double(total)) : 0
    }

    var appFraction: Double {
        total > 0 ? min(1, Double(appUsed) / Double(total)) : 0
    }

    var availableFraction: Double {
        max(0, 1 - systemFraction - appFraction)
    }

    /// 已用字节数：总容量减可用容量，兜底用系统 + 应用之和。
    var usedBytes: UInt64 {
        guard total > 0 else { return 0 }
        let sum = systemUsed &+ appUsed
        let derived = total > available ? total - available : 0
        return min(total, max(derived, sum))
    }

    /// 已用占比，用于总览数字和颜色档位。
    var usedFraction: Double {
        total > 0 ? min(1, Double(usedBytes) / Double(total)) : 0
    }
}

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
    let download: Double
    let upload: Double
}

// MARK: - 轮询配置

/// 数据项挂在哪一档。三档独立计时，同一档里的项会合并成一条命令。
enum PollTier: String, CaseIterable, Identifiable, Codable {
    case fast
    case medium
    case slow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "快档"
        case .medium: return "中档"
        case .slow: return "慢档"
        }
    }

    var shortTitle: String {
        switch self {
        case .fast: return "快"
        case .medium: return "中"
        case .slow: return "慢"
        }
    }

    var caption: String {
        switch self {
        case .fast: return "界面上的核心数字，越短越跟手，路由器也越忙"
        case .medium: return "闪存、设备、端口这类变化慢的数据"
        case .slow: return "OpenClash 状态与连接表，最贵的一组"
        }
    }

    /// 秒数允许范围：下限保证路由器有机会喘气，上限防止数据老得没法看。
    var secondsRange: ClosedRange<Double> {
        switch self {
        case .fast: return 1...15
        case .medium: return 3...120
        case .slow: return 10...600
        }
    }

    /// 加减按钮一次跳多少。
    var step: Double {
        self == .slow ? 5 : 1
    }
}

/// 可以单独决定挂在哪一档的数据项。
enum PollItem: String, CaseIterable, Identifiable, Codable {
    case core
    case sensors
    case flash
    case devices
    case ports
    case clashState
    case clashTraffic
    case clashConnections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: return "CPU / 内存 / 网速"
        case .sensors: return "温度 / 风扇"
        case .flash: return "闪存空间"
        case .devices: return "在线设备"
        case .ports: return "LAN 端口"
        case .clashState: return "OpenClash 状态"
        case .clashTraffic: return "OpenClash 流量"
        case .clashConnections: return "OpenClash 连接数"
        }
    }

    var subtitle: String {
        switch self {
        case .core: return "CPU、内存、上下行、负载、运行时间"
        case .sensors: return "thermal / hwmon 里的温度与风扇转速"
        case .flash: return "系统、应用程序与可用空间"
        case .devices: return "DHCP 租约里的设备列表"
        case .ports: return "各网口的速率、双工、IP 与桥接"
        case .clashState: return "是否运行、模式、配置文件、面板端口"
        case .clashTraffic: return "实时上下行与内核内存、CPU"
        case .clashConnections: return "累计流量与连接数（会序列化整张表，最贵）"
        }
    }

    var icon: String {
        switch self {
        case .core: return "cpu"
        case .sensors: return "thermometer.medium"
        case .flash: return "internaldrive"
        case .devices: return "laptopcomputer.and.iphone"
        case .ports: return "cable.connector"
        case .clashState: return "shield.lefthalf.filled"
        case .clashTraffic: return "arrow.up.arrow.down"
        case .clashConnections: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// 核心项必须有：没有它整页都是空的，所以固定挂在快档。
    var isRequired: Bool { self == .core }

    var defaultTier: PollTier? {
        switch self {
        case .core: return .fast
        case .sensors: return .fast
        case .flash, .devices, .ports, .clashTraffic: return .medium
        case .clashState, .clashConnections: return .slow
        }
    }
}

/// 一键预设。
enum PollPreset: String, CaseIterable, Identifiable {
    case saver
    case balanced
    case smooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saver: return "省电"
        case .balanced: return "均衡"
        case .smooth: return "流畅"
        }
    }

    var fast: Double {
        switch self {
        case .saver: return 5
        case .balanced: return 2
        case .smooth: return 1
        }
    }

    var medium: Double {
        switch self {
        case .saver: return 30
        case .balanced: return 10
        case .smooth: return 5
        }
    }

    var slow: Double {
        switch self {
        case .saver: return 60
        case .balanced: return 20
        case .smooth: return 15
        }
    }
}

/// 存进 UserDefaults 的轮询配置。
struct PollConfiguration: Codable, Equatable {
    var fastSeconds: Double = 2
    var mediumSeconds: Double = 10
    var slowSeconds: Double = 20
    /// 数据项 → 档位。键不存在表示沿用默认档位，"off" 表示关闭。
    var assignments: [String: String] = [:]

    func tier(for item: PollItem) -> PollTier? {
        guard let raw = assignments[item.rawValue] else { return item.defaultTier }
        if raw == "off" { return nil }
        return PollTier(rawValue: raw)
    }

    mutating func setTier(_ tier: PollTier?, for item: PollItem) {
        assignments[item.rawValue] = tier?.rawValue ?? "off"
    }

    func seconds(for tier: PollTier) -> Double {
        let value: Double
        switch tier {
        case .fast: value = fastSeconds
        case .medium: value = mediumSeconds
        case .slow: value = slowSeconds
        }
        let range = tier.secondsRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    mutating func setSeconds(_ value: Double, for tier: PollTier) {
        let range = tier.secondsRange
        let clamped = min(max(value.rounded(), range.lowerBound), range.upperBound)
        switch tier {
        case .fast: fastSeconds = clamped
        case .medium: mediumSeconds = clamped
        case .slow: slowSeconds = clamped
        }
    }

    /// 关掉了多少项，设置页用来提示“关掉就看不到”。
    var disabledCount: Int {
        PollItem.allCases.filter { !$0.isRequired && tier(for: $0) == nil }.count
    }

    static func load() -> PollConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "pollConfiguration"),
              let decoded = try? JSONDecoder().decode(PollConfiguration.self, from: data) else {
            return PollConfiguration()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "pollConfiguration")
        }
    }
}
