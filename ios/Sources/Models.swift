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
}

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
    let download: Double
    let upload: Double
}
