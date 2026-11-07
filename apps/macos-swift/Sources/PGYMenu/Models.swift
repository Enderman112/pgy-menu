import Foundation

// MARK: - 设备状态

struct DeviceStatus: Equatable {
    var bars: Int = 0                 // signalbar 0...5
    var networkType: String = ""     // LTE / ...
    var subNetworkType: String = ""  // FDD_LTE / TDD_LTE
    var operatorName: String = ""
    var pppStatus: String = ""
    var modemState: String = ""
    var simCardState: String = ""
    var roaming: Bool = false

    var rsrp: Int?
    var rsrqRaw: Int?
    var sinr: Int?
    var band: Int?
    var bandwidth: Int?
    var arfcn: Int?
    var pci: Int?
    var cellID: Int?
    var cellIDGlobal: Int64?
    var cqi: Int?

    var wifiOn: Bool = false
    var ssid: String = ""
    var clientCount: Int = 0

    var sessionRx: Int64 = 0
    var sessionTx: Int64 = 0
    var sessionSeconds: Int = 0
    var monthlyRx: Int64 = 0
    var monthlyTx: Int64 = 0
    var monthlySeconds: Int = 0
    var rxSpeed: Double = 0   // 字节/秒
    var txSpeed: Double = 0

    var dataLimitOn: Bool = false
    var dataLimitSize: String = ""
    var dataLimitPercent: String = ""
    var dataLimitUnit: String = ""

    var imei: String = ""
    var phoneNumber: String = ""
    var imsi: String = ""
    var iccid: String = ""
    var firmware: String = ""
    var hardware: String = ""
    var webVersion: String = ""
    var uptime: Int = 0

    var loggedIn: Bool = false
    var batteryPercent: Int?
    var hasWifi: Bool = true

    // MARK: 派生值

    var connected: Bool { pppStatus == "ppp_connected" }
    var connecting: Bool { pppStatus == "ppp_connecting" || pppStatus == "ppp_disconnecting" }
    var hasService: Bool { bars > 0 && (networkType.isEmpty == false) }

    var rsrq: Double? {
        guard let raw = rsrqRaw else { return nil }
        return (Double(raw) - 40) / 2
    }

    /// 网络制式展示文案
    var networkLabel: String {
        let t = subNetworkType.isEmpty ? networkType : subNetworkType
        switch t.uppercased() {
        case "LTE", "FDD_LTE", "TDD_LTE", "TD-LTE", "FDD-LTE":
            return "4G LTE"
        case "LTE_CA": return "4G+"
        case "WCDMA", "HSDPA", "HSUPA", "HSPA", "HSPA+", "DC-HSPA+", "TD_SCDMA", "TD-SCDMA", "UMTS":
            return "3G"
        case "GSM", "GPRS", "EDGE":
            return "2G"
        case "": return "--"
        default: return t
        }
    }

    var statusText: String {
        if connecting { return "正在拨号…" }
        if connected { return "已连接" }
        if !simCardState.isEmpty && simCardState != "READY" { return "SIM 卡异常" }
        if bars == 0 { return "无信号" }
        return "未连接"
    }

    var bandText: String {
        guard let band, band > 0 else { return "--" }
        return "B\(band)"
    }

    var signalQualityText: String {
        switch bars {
        case 5: return "极佳"
        case 4: return "良好"
        case 3: return "一般"
        case 2: return "较弱"
        case 1: return "很弱"
        default: return "无信号"
        }
    }
}

// MARK: - WiFi 设置

struct WiFiSettings: Equatable {
    var enabled: Bool = false
    var ssid: String = ""
    var password: String = ""
    var hideSSID: Bool = false
    var authMode: String = "WPAPSKWPA2PSK"
    var cipher: String = "TKIPAES"
    var maxClients: Int = 8
    var coverage: String = "medium_mode"
    var channel: String = "0"
    var sleepMinutes: Int = -1
    var hasWEP: Bool = false
}

// MARK: - APN

struct APNProfile: Identifiable, Equatable {
    var id: Int              // index
    var profileName: String
    var apn: String
    var mode: String
    var dial: String
    var auth: String
    var username: String
    var password: String
    var pdpType: String
    var isCurrent: Bool = false

    /// 设备格式：index($)??($)profileName($)apn($)mode($)*99#($)auth($)user($)pass($)pdpType($)...
    static func parse(_ raw: String) -> APNProfile? {
        guard raw.isEmpty == false else { return nil }
        let parts = raw.components(separatedBy: "($)")
        guard parts.count >= 7, let idx = Int(parts[0]) else { return nil }
        func at(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
        return APNProfile(
            id: idx,
            profileName: at(2),
            apn: at(3),
            mode: at(4),
            dial: at(5),
            auth: at(6),
            username: at(7),
            password: at(8),
            pdpType: at(9)
        )
    }
}

// MARK: - 已连接客户端

struct WiFiClient: Identifiable, Equatable {
    var id: String { macAddress }
    var macAddress: String
    var hostName: String
    var ipAddress: String
}

// MARK: - 局域网 / 路由

struct LANSettings: Equatable {
    var ipAddress: String = "10.168.1.1"
    var subnetMask: String = "255.255.255.0"
    var dhcpEnabled: Bool = true
    var dhcpStart: String = "10.168.1.100"
    var dhcpEnd: String = "10.168.1.200"
    var dhcpLease: Int = 24
}

struct DMZSettings: Equatable {
    var enabled: Bool = false
    var ipAddress: String = ""
}

/// 内置（eSIM）/ 外置（实体卡）SIM 切换。设备值：0=外置，1=内置。
enum SIMMode: Int, CaseIterable, Identifiable {
    case external = 0
    case builtIn = 1
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .external: return "外置 SIM（实体卡）"
        case .builtIn: return "内置 SIM（eSIM）"
        }
    }
    var shortTitle: String {
        switch self {
        case .external: return "外置 SIM"
        case .builtIn: return "内置 SIM"
        }
    }
}

// MARK: - 网络模式

enum NetworkMode: String, CaseIterable, Identifiable {
    case auto = "NETWORK_auto"
    case lteOnly = "Only_LTE"
    case lte3g = "TD_LTE_auto"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动 (4G/3G/2G)"
        case .lteOnly: return "仅 4G (LTE)"
        case .lte3g: return "4G/3G"
        }
    }
}

// MARK: - 流量单位

enum DataLimitUnit: String, CaseIterable, Identifiable {
    case data = "data"
    case time = "time"
    var id: String { rawValue }
    var title: String { self == .data ? "流量" : "时长" }
}

// MARK: - 格式化工具

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        let v = Double(value)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var idx = 0
        var n = v
        while n >= 1024 && idx < units.count - 1 {
            n /= 1024
            idx += 1
        }
        if idx == 0 { return "\(Int(n)) B" }
        return String(format: n >= 100 ? "%.0f %@" : "%.2f %@", n, units[idx])
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(max(0, bytesPerSecond.rounded()))) + "/s"
    }

    static func duration(_ seconds: Int) -> String {
        if seconds <= 0 { return "--" }
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分" }
        if m > 0 { return "\(m) 分 \(s) 秒" }
        return "\(s) 秒"
    }

    static func dbm(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) dBm"
    }

    static func db(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f dB", value)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
