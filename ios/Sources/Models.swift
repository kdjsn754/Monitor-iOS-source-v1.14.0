import Foundation

enum OverviewModule: String, CaseIterable, Codable, Identifiable {
    case speed
    case resources
    case flash
    case hardware
    case devices
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: return "实时速度"
        case .resources: return "资源占用"
        case .flash: return "闪存"
        case .hardware: return "硬件状态"
        case .devices: return "连接设备"
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
    var cpuCores = 0
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
    /// 最近一次是否真的读到了内核接口（curl/wget 失败或密钥不对时为 false）。
    var apiReachable = false
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
    }

    /// 用站点做标识，不用新建 UUID：每次检测都会重建数组，
    /// 用 UUID 会让 SwiftUI 认为所有格子都换了新的，整块重新插入、动画乱闪。
    var id: String { site.id }
    var site: Site
    var success = false
    var latency: Int = 0
    var tested = false
}

struct FlashInfo {
    var total: UInt64 = 0
    var systemUsed: UInt64 = 0
    var appUsed: UInt64 = 0
    var available: UInt64 = 0

    var hasData: Bool { total > 0 }

    /// 三段共用同一个分母（total 由 系统 + 应用 + 可用 三者在解析时凑齐），
    /// 所以「已用 + 剩余 = 共」永远成立，进度条填到哪儿和右上角的百分比是同一个数。
    /// 旧版把三段各自归一，结果出现「已用 30 MB、剩余 90 MB、共 100 MB」这种
    /// 加起来超过总容量的组合，条的填充比例也和百分比对不上。
    var usedBytes: UInt64 {
        guard total > 0 else { return 0 }
        return min(total, systemUsed &+ appUsed)
    }

    var usedFraction: Double {
        total > 0 ? min(1, Double(usedBytes) / Double(total)) : 0
    }

    private func share(_ bytes: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(bytes) / Double(total)))
    }

    var systemShare: Double { share(systemUsed) }

    /// 应用段不能越界：两段加起来最多占满整条。
    var appShare: Double { min(1 - systemShare, share(appUsed)) }

    var availableShare: Double { max(0, 1 - systemShare - appShare) }
}

/// 速度曲线上的一个点。只保留画图要用的两个值，
/// 以前还顺带存了 cpu / memory，但没有任何视图读它——每 2 秒多存两份 Double，
/// 只为了让整个数组多一次拷贝。
struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let download: Double
    let upload: Double
}

// MARK: - 页面与采集

/// 轮询跟着页面走：只有当前标签页要用的数据才会被采集。
enum AppPage: String, CaseIterable, Identifiable {
    case overview
    case proxy
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .proxy: return "网络代理"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .proxy: return "globe"
        case .settings: return "slider.horizontal.3"
        }
    }

    /// TabView 的下标 ↔ 页面。
    init(tab: Int) {
        switch tab {
        case 1: self = .proxy
        case 2: self = .settings
        default: self = .overview
        }
    }
}

/// 一项可以单独采集的数据。每一项只属于一个页面，只有那一页在前台时才会去取。
enum PollItem: String, CaseIterable, Identifiable, Codable {
    case core
    case sensors
    case flash
    case devices
    case clashState
    case clashTraffic
    case clashConnections

    var id: String { rawValue }

    var page: AppPage {
        switch self {
        case .core, .sensors, .flash, .devices: return .overview
        case .clashState, .clashTraffic, .clashConnections: return .proxy
        }
    }

    var title: String {
        switch self {
        case .core: return "CPU / 内存 / 网速"
        case .sensors: return "温度 / 风扇"
        case .flash: return "闪存空间"
        case .devices: return "在线设备"
        case .clashState: return "OpenClash 状态与配置"
        case .clashTraffic: return "OpenClash 实时流量"
        case .clashConnections: return "连接数与内核状态"
        }
    }

    var subtitle: String {
        switch self {
        case .core: return "CPU、内存、上下行、负载、运行时间"
        case .sensors: return "thermal / hwmon 里的温度与风扇转速"
        case .flash: return "系统、应用程序与可用空间"
        case .devices: return "DHCP 租约里的设备列表"
        case .clashState: return "是否运行、代理模式、配置文件、面板端口"
        case .clashTraffic: return "实时上下行，来自内核 /traffic 接口"
        case .clashConnections: return "累计流量、连接数、内核内存与 CPU"
        }
    }

    var icon: String {
        switch self {
        case .core: return "cpu"
        case .sensors: return "thermometer.medium"
        case .flash: return "internaldrive"
        case .devices: return "laptopcomputer.and.iphone"
        case .clashState: return "shield.lefthalf.filled"
        case .clashTraffic: return "arrow.up.arrow.down"
        case .clashConnections: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// 是否跟着刷新间隔反复采集。
    /// OpenClash 的模式和配置文件列表要问 7 次 uci，只在进入代理页时取一次，
    /// 之后每轮只确认运行状态和面板端口，省下的都是路由器的 CPU。
    var isPeriodic: Bool { self != .clashState }
}

/// 存进 UserDefaults 的采集配置：现在只有一个全局刷新间隔。
struct PollConfiguration: Codable, Equatable {
    var seconds: Double = 2

    static let range: ClosedRange<Double> = 1...15

    var clampedSeconds: Double {
        min(max(seconds.rounded(), Self.range.lowerBound), Self.range.upperBound)
    }

    func items(on page: AppPage) -> [PollItem] {
        PollItem.allCases.filter { $0.page == page }
    }

    mutating func setSeconds(_ value: Double) {
        seconds = min(max(value.rounded(), Self.range.lowerBound), Self.range.upperBound)
    }

    init() {}

    /// 老版本的配置里存的是三档秒数，没有 seconds，这里回落默认值。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? 2
        seconds = min(max(value.rounded(), Self.range.lowerBound), Self.range.upperBound)
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
