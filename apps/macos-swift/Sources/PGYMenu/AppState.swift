import Foundation
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.xuyaoshi.pgymenu", category: "device")

/// 全局状态与设备操作入口。
@MainActor
final class AppState: ObservableObject {
    // MARK: - 设备连接

    @Published private(set) var baseURL: URL?
    @Published private(set) var reachable = false
    @Published private(set) var status = DeviceStatus()
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var menuBarIcon: NSImage = MenuBarIcon.make(bars: 0, connected: false, known: false)

    // MARK: - 详情/设置数据

    @Published private(set) var wifi = WiFiSettings()
    @Published private(set) var apns: [APNProfile] = []
    @Published private(set) var clients: [WiFiClient] = []
    @Published private(set) var networkMode: NetworkMode = .auto
    @Published private(set) var bandLocked = false
    @Published private(set) var lan = LANSettings()
    @Published private(set) var dmz = DMZSettings()
    @Published private(set) var upnpEnabled = true
    @Published private(set) var simMode: SIMMode = .external
    @Published private(set) var simSwitchAvailable = false
    @Published private(set) var settingsLoaded = false

    // MARK: - 交互反馈

    @Published private(set) var busyCount = 0
    @Published var toast: String?
    @Published var toastIsError = false

    var isBusy: Bool { busyCount > 0 }

    // MARK: - 偏好

    @Published var refreshSeconds: Double {
        didSet { UserDefaults.standard.set(refreshSeconds, forKey: Keys.refresh) }
    }
    @Published var showTextInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showTextInMenuBar, forKey: Keys.showText) }
    }
    /// 菜单栏文字（随状态实时计算，避免与图标刷新互相触发）
    var menuBarText: String {
        guard showTextInMenuBar else { return "" }
        if !reachable { return "" }
        if status.connected {
            return status.networkLabel == "--" ? "4G" : status.networkLabel
        }
        return status.statusText
    }
    @Published var adminPassword: String = Keychain.loadPassword() ?? "admin" {
        didSet { Keychain.savePassword(adminPassword) }
    }
    @Published var preferredHost: String = UserDefaults.standard.string(forKey: Keys.host) ?? "" {
        didSet {
            UserDefaults.standard.set(preferredHost, forKey: Keys.host)
            if let url = URL(string: "http://\(preferredHost)") {
                api = DeviceAPI(baseURL: url)
                baseURL = url
            }
        }
    }

    // MARK: - 内部

    private enum Keys {
        static let refresh = "pgy.refreshSeconds"
        static let showText = "pgy.showTextInMenuBar"
        static let host = "pgy.preferredHost"
    }

    private var api = DeviceAPI(baseURL: URL(string: "http://10.168.1.1")!)
    private var pollTask: Task<Void, Never>?
    private var slowCounter = 0
    private var lastRx: Int64 = -1
    private var lastTx: Int64 = -1
    private var lastSample: Date?
    private var loginInFlight = false

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.refresh)
        refreshSeconds = stored > 0 ? stored : 2.0
        showTextInMenuBar = UserDefaults.standard.bool(forKey: Keys.showText)
        if !preferredHost.isEmpty, let url = URL(string: "http://\(preferredHost)") {
            api = DeviceAPI(baseURL: url)
            baseURL = url
        }
    }

    // MARK: - 生命周期

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func runLoop() async {
        await discoverIfNeeded(force: true)
        var tick = 0
        while !Task.isCancelled {
            await poll()
            tick += 1
            if tick % 5 == 0 {
                await refreshSettings(silent: true)
            }
            let interval = max(1.0, refreshSeconds)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    // MARK: - 发现设备

    func discoverIfNeeded(force: Bool = false) async {
        if reachable && !force { return }
        if !preferredHost.isEmpty, let url = URL(string: "http://\(preferredHost)") {
            if await DeviceDiscovery.probe(host: preferredHost) != nil {
                api = DeviceAPI(baseURL: url)
                baseURL = url
                reachable = true
                await ensureLogin()
                return
            }
        }
        if let url = await DeviceDiscovery.discover() {
            api = DeviceAPI(baseURL: url)
            baseURL = url
            reachable = true
            lastError = nil
            logger.info("发现设备: \(url.absoluteString, privacy: .public)")
            await ensureLogin()
        } else {
            reachable = false
            lastError = "未找到随身 WiFi（请确认已插在电脑上，管理地址通常是 http://10.168.1.1）"
            updateMenuIcon()
        }
    }

    func retryDiscovery() {
        Task {
            await discoverIfNeeded(force: true)
            await poll()
            await refreshSettings(silent: true)
        }
    }

    func openWebUI() {
        let host = baseURL?.absoluteString ?? "http://10.168.1.1"
        if let url = URL(string: host) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 登录

    @discardableResult
    private func ensureLogin() async -> Bool {
        if status.loggedIn { return true }
        if loginInFlight { return false }
        loginInFlight = true
        defer { loginInFlight = false }
        do {
            try await api.login(username: "admin", password: adminPassword)
            status.loggedIn = true
            return true
        } catch {
            status.loggedIn = false
            lastError = "管理密码错误：请在「设置 → 设备」里修改管理密码"
            return false
        }
    }

    // MARK: - 轮询

    private static let fastCommands = [
        "signalbar", "network_type", "sub_network_type", "network_provider",
        "ppp_status", "modem_main_state", "cpin", "simcard_roam",
        "wifi_cur_state", "has_wifi",
        "lte_rsrp", "rssi", "nv_rsrq", "nv_sinr", "nv_band", "nv_bandwidth",
        "nv_arfcn", "nv_pci", "nv_cellid", "nv_globecellid", "nv_cqi0",
        "realtime_tx_bytes", "realtime_rx_bytes", "realtime_time",
        "monthly_tx_bytes", "monthly_rx_bytes", "monthly_time",
        "data_volume_limit_switch", "data_volume_limit_unit",
        "data_volume_limit_size", "data_volume_alert_percent",
        "run_time", "loginfo", "battery_pers", "has_battery"
    ]

    static let slowCommands = [
        "SSID1", "HideSSID", "AuthMode", "EncrypType", "WPAPSK1_encode",
        "MAX_Access_num", "MAX_Station_num", "wifi_coverage", "Sleep_interval",
        "Channel", "m_ssid_enable", "NoForwarding", "wifi_cur_state", "has_wifi",
        "net_select", "current_network_mode", "net_select_mode",
        "imei", "imsi", "msisdn", "ziccid", "cr_version", "hw_version", "web_version",
        "LteBandLockSet", "LteBandLockState",
        "upnpEnabled", "DMZEnable", "DMZIPAddress",
        "lan_ipaddr", "lan_netmask", "dhcpEnabled", "dhcpStart", "dhcpEnd", "dhcpLease_hour",
        "sim_esim_mode", "user_web_disp_sim_esim_config"
    ]

    func poll() async {
        guard reachable else {
            await discoverIfNeeded(force: false)
            return
        }
        do {
            let fields = try await api.get(Self.fastCommands)
            apply(fields)
            lastUpdated = Date()
            lastError = nil
            if fields["loginfo"] == "ok" { status.loggedIn = true }
            logger.debug("poll ok bars=\(self.status.bars) type=\(self.status.networkType, privacy: .public) rsrp=\(self.status.rsrp ?? -999)")
        } catch {
            reachable = false
            if let de = error as? DeviceError, case .unreachable = de {
                lastError = "设备连接中断，正在重新检测…"
            } else {
                lastError = error.localizedDescription
            }
            await discoverIfNeeded(force: true)
        }
    }

    private func apply(_ fields: [String: String]) {
        var s = status
        s.bars = Int(fields["signalbar"] ?? "") ?? 0
        s.networkType = fields["network_type"] ?? ""
        s.subNetworkType = fields["sub_network_type"] ?? ""
        s.operatorName = fields["network_provider"] ?? ""
        s.pppStatus = fields["ppp_status"] ?? ""
        s.modemState = fields["modem_main_state"] ?? ""
        s.simCardState = fields["cpin"] ?? ""
        s.roaming = (fields["simcard_roam"] ?? "") != "Home"
        s.hasWifi = (fields["has_wifi"] ?? "1") != "0"
        s.wifiOn = (fields["wifi_cur_state"] ?? "0") == "1"

        s.rsrp = Int(fields["lte_rsrp"] ?? "") ?? Int(fields["rssi"] ?? "")
        s.rsrqRaw = Int(fields["nv_rsrq"] ?? "")
        s.sinr = Int(fields["nv_sinr"] ?? "")
        s.band = Int(fields["nv_band"] ?? "")
        s.bandwidth = Int(fields["nv_bandwidth"] ?? "")
        s.arfcn = Int(fields["nv_arfcn"] ?? "")
        s.pci = Int(fields["nv_pci"] ?? "")
        s.cellID = Int(fields["nv_cellid"] ?? "")
        s.cellIDGlobal = Int64(fields["nv_globecellid"] ?? "")
        s.cqi = Int(fields["nv_cqi0"] ?? "")

        s.sessionRx = Int64(fields["realtime_rx_bytes"] ?? "") ?? 0
        s.sessionTx = Int64(fields["realtime_tx_bytes"] ?? "") ?? 0
        s.sessionSeconds = Int(fields["realtime_time"] ?? "") ?? 0
        s.monthlyRx = Int64(fields["monthly_rx_bytes"] ?? "") ?? 0
        s.monthlyTx = Int64(fields["monthly_tx_bytes"] ?? "") ?? 0
        s.monthlySeconds = Int(fields["monthly_time"] ?? "") ?? 0
        s.dataLimitOn = (fields["data_volume_limit_switch"] ?? "0") == "1"
        s.dataLimitUnit = fields["data_volume_limit_unit"] ?? ""
        s.dataLimitSize = fields["data_volume_limit_size"] ?? ""
        s.dataLimitPercent = fields["data_volume_alert_percent"] ?? ""
        s.uptime = Int(fields["run_time"] ?? "") ?? 0
        s.loggedIn = (fields["loginfo"] ?? "") == "ok"
        s.batteryPercent = Int(fields["battery_pers"] ?? "")
        if (fields["has_battery"] ?? "1") == "0" { s.batteryPercent = nil }

        // 实时速度
        let now = Date()
        if lastRx >= 0, let lastSample {
            let dt = now.timeIntervalSince(lastSample)
            if dt > 0.2 {
                s.rxSpeed = max(0, Double(s.sessionRx - lastRx) / dt)
                s.txSpeed = max(0, Double(s.sessionTx - lastTx) / dt)
            }
        }
        lastRx = s.sessionRx
        lastTx = s.sessionTx
        lastSample = now

        status = s
        updateMenuIcon()
    }

    private func updateMenuIcon() {
        menuBarIcon = MenuBarIcon.make(bars: status.bars, connected: status.connected, known: reachable)
    }

    // MARK: - 设置数据

    func refreshSettings(silent: Bool = false) async {
        guard reachable else { return }
        if !status.loggedIn { _ = await ensureLogin() }
        do {
            let fields = try await api.get(Self.slowCommands)
            var w = wifi
            w.ssid = fields["SSID1"] ?? w.ssid
            w.hideSSID = (fields["HideSSID"] ?? "0") == "1"
            w.authMode = fields["AuthMode"] ?? w.authMode
            w.cipher = fields["EncrypType"] ?? w.cipher
            w.maxClients = Int(fields["MAX_Access_num"] ?? "") ?? w.maxClients
            w.enabled = (fields["wifi_cur_state"] ?? "0") == "1"
            w.coverage = fields["wifi_coverage"] ?? w.coverage
            w.sleepMinutes = Int(fields["Sleep_interval"] ?? "") ?? -1
            w.channel = fields["Channel"] ?? "0"
            if let encoded = fields["WPAPSK1_encode"], let data = Data(base64Encoded: encoded),
               let pwd = String(data: data, encoding: .utf8) {
                w.password = pwd
            }
            wifi = w

            if let mode = NetworkMode(rawValue: fields["net_select"] ?? "") {
                networkMode = mode
            }
            bandLocked = (fields["LteBandLockSet"] ?? "0") == "1"

            var l = lan
            l.ipAddress = fields["lan_ipaddr"] ?? l.ipAddress
            l.subnetMask = fields["lan_netmask"] ?? l.subnetMask
            l.dhcpEnabled = (fields["dhcpEnabled"] ?? "1") == "1"
            l.dhcpStart = fields["dhcpStart"] ?? l.dhcpStart
            l.dhcpEnd = fields["dhcpEnd"] ?? l.dhcpEnd
            l.dhcpLease = Int(fields["dhcpLease_hour"] ?? "") ?? l.dhcpLease
            lan = l

            dmz = DMZSettings(enabled: (fields["DMZEnable"] ?? "0") == "1",
                              ipAddress: fields["DMZIPAddress"] ?? "")
            upnpEnabled = (fields["upnpEnabled"] ?? "1") == "1"
            simSwitchAvailable = (fields["user_web_disp_sim_esim_config"] ?? "0") == "1"
            if let raw = fields["sim_esim_mode"], let value = Int(raw), let mode = SIMMode(rawValue: value) {
                simMode = mode
            }

            var s = status
            s.imei = fields["imei"] ?? s.imei
            s.imsi = fields["imsi"] ?? s.imsi
            s.phoneNumber = fields["msisdn"] ?? s.phoneNumber
            s.iccid = fields["ziccid"] ?? s.iccid
            s.firmware = fields["cr_version"] ?? s.firmware
            s.hardware = fields["hw_version"] ?? s.hardware
            s.webVersion = fields["web_version"] ?? s.webVersion
            status = s
            settingsLoaded = true

            await loadAPNs()
            await loadClients()
        } catch {
            if !silent { showToast(error.localizedDescription, isError: true) }
        }
    }

    private func loadAPNs() async {
        var cmds = ["apn_mode", "Current_index", "m_profile_name", "wan_apn", "pdp_type"]
        for i in 0..<20 { cmds.append("APN_config\(i)") }
        do {
            let fields = try await api.get(cmds)
            let currentName = fields["m_profile_name"] ?? ""
            var list: [APNProfile] = []
            for i in 0..<20 {
                if let profile = APNProfile.parse(fields["APN_config\(i)"] ?? "") {
                    var p = profile
                    p.isCurrent = !currentName.isEmpty && p.profileName == currentName
                    list.append(p)
                }
            }
            if list.contains(where: { $0.isCurrent }) == false {
                // 回退：优先标记 manual 模式的那条
                if let idx = list.firstIndex(where: { $0.mode == "manual" }) {
                    list[idx].isCurrent = true
                } else if list.isEmpty == false {
                    list[0].isCurrent = true
                }
            }
            apns = list
        } catch {
            // 忽略
        }
    }

    private func loadClients() async {
        do {
            let raw = try await api.get(cmd: "station_list")
            var list: [WiFiClient] = []
            if let arr = raw["station_list"] as? [[String: Any]] {
                for item in arr {
                    let mac = DeviceAPI.stringValue(item["mac_addr"] ?? "")
                    let host = DeviceAPI.stringValue(item["hostname"] ?? "")
                    let ip = DeviceAPI.stringValue(item["ip_addr"] ?? "")
                    list.append(WiFiClient(macAddress: mac, hostName: host.isEmpty ? "未知设备" : host, ipAddress: ip))
                }
            }
            clients = list
            var s = status
            s.clientCount = list.count
            status = s
        } catch {
            // 忽略
        }
    }

    // MARK: - 提示

    func showToast(_ message: String, isError: Bool = false) {
        toast = message
        toastIsError = isError
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, self.toast == message else { return }
            self.toast = nil
        }
    }

    private func beginBusy() { busyCount += 1 }
    private func endBusy() { busyCount = max(0, busyCount - 1) }

    /// 执行一个需要登录的写操作，自动处理登录、提示与刷新。
    func perform(_ label: String, _ operation: @escaping (DeviceAPI) async throws -> Void) {
        Task {
            guard reachable else {
                showToast("设备未连接", isError: true)
                return
            }
            beginBusy()
            defer { endBusy() }
            _ = await ensureLogin()
            do {
                try await operation(api)
                showToast(label + "成功")
                try? await Task.sleep(nanoseconds: 400_000_000)
                await poll()
                await refreshSettings(silent: true)
            } catch {
                showToast("\(label)失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - WiFi 操作

    func setWiFiEnabled(_ enabled: Bool) {
        let mSsid = wifi.enabled ? "1" : "0"
        perform(enabled ? "开启 WiFi" : "关闭 WiFi") { api in
            try await api.set("SET_WIFI_INFO", [
                ("wifiEnabled", enabled ? "1" : "0"),
                ("m_ssid_enable", mSsid)
            ])
        }
    }

    func saveWiFiSettings(ssid: String, password: String, authMode: String,
                          hidden: Bool, maxClients: Int) {
        perform("保存 WiFi 设置") { [weak self] api in
            guard let self else { return }
            var params: [(String, String)] = [
                ("ssid", ssid),
                ("broadcastSsidEnabled", hidden ? "0" : "1"),
                ("MAX_Access_num", String(maxClients)),
                ("security_mode", authMode),
                ("cipher", self.wifi.cipher.isEmpty ? "TKIPAES" : self.wifi.cipher),
                ("NoForwarding", "0"),
                ("show_qrcode_flag", "1")
            ]
            if authMode == "OPEN" {
                params.append(("security_shared_mode", "NONE"))
            } else {
                params.append(("security_shared_mode", self.wifi.cipher.isEmpty ? "TKIPAES" : self.wifi.cipher))
                params.append(("passphrase", Data(password.utf8).base64EncodedString()))
            }
            try await api.set("SET_WIFI_SSID1_SETTINGS", params)
        }
    }

    func setWiFiSleep(minutes: Int) {
        perform("设置 WiFi 休眠") { api in
            try await api.set("SET_WIFI_SLEEP_INFO", [("sysIdleTimeToSleep", String(minutes))])
        }
    }

    // MARK: - 网络操作

    func setCellular(on: Bool) {
        perform(on ? "拨号连接" : "断开连接") { api in
            try await api.set(on ? "CONNECT_NETWORK" : "DISCONNECT_NETWORK")
        }
    }

    func setNetworkMode(_ mode: NetworkMode) {
        perform("切换网络模式") { api in
            try await api.set("SET_BEARER_PREFERENCE", [("BearerPreference", mode.rawValue)])
        }
    }

    func setDataLimit(enabled: Bool, unit: DataLimitUnit, size: String, alertPercent: String) {
        perform("保存流量限额") { api in
            var params: [(String, String)] = [("data_volume_limit_switch", enabled ? "1" : "0")]
            if enabled {
                params.append(("data_volume_limit_unit", unit.rawValue))
                params.append(("data_volume_limit_size", size))
                params.append(("data_volume_alert_percent", alertPercent))
            }
            try await api.set("DATA_LIMIT_SETTING", params)
        }
    }

    func setDefaultAPN(_ apn: APNProfile) {
        perform("切换 APN") { api in
            try await api.set("APN_PROC_EX", [
                ("apn_mode", "manual"),
                ("apn_action", "set_default"),
                ("set_default_flag", "1"),
                ("pdp_type", apn.pdpType.isEmpty ? "IPv4" : apn.pdpType),
                ("index", String(apn.id))
            ])
        }
    }

    // MARK: - 局域网 / 路由

    func saveLAN(ip: String, mask: String, dhcpEnabled: Bool,
                 start: String, end: String, lease: Int) {
        perform("保存局域网设置") { api in
            var params: [(String, String)] = [
                ("lanIp", ip),
                ("lanNetmask", mask),
                ("lanDhcpType", dhcpEnabled ? "SERVER" : "DISABLE")
            ]
            if dhcpEnabled {
                params.append(("dhcpStart", start))
                params.append(("dhcpEnd", end))
                params.append(("dhcpLease", String(lease)))
            }
            params.append(("dhcp_reboot_flag", "1"))
            try await api.set("DHCP_SETTING", params)
        }
    }

    func setUpnp(_ enabled: Bool) {
        perform(enabled ? "开启 UPnP" : "关闭 UPnP") { api in
            try await api.set("UPNP_SETTING", [("upnp_setting_option", enabled ? "1" : "0")])
        }
    }

    func saveDMZ(enabled: Bool, ip: String) {
        perform("保存 DMZ 设置") { api in
            var params: [(String, String)] = [("DMZEnabled", enabled ? "1" : "0")]
            if enabled {
                params.append(("DMZIPAddress", ip))
            }
            try await api.set("DMZ_SETTING", params)
        }
    }

    /// 切换内置/外置 SIM：设备会重启、网络中断约 1 分钟。
    func setSIMMode(_ mode: SIMMode) {
        guard mode != simMode else { return }
        Task {
            beginBusy()
            defer { endBusy() }
            do {
                try await api.set("set_esim", [("esimmode", String(mode.rawValue))])
                simMode = mode
                showToast("已提交切换为\(mode.shortTitle)，设备将重启，约 1 分钟内恢复")
                reachable = false
                status = DeviceStatus()
                updateMenuIcon()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                await discoverIfNeeded(force: true)
                await poll()
            } catch {
                showToast("切换 SIM 失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - 设备操作

    func rebootDevice() {
        perform("重启设备") { api in
            try await api.set("REBOOT_DEVICE")
        }
    }

    func powerOffDevice() {
        perform("关机") { api in
            try await api.set("TURN_OFF_DEVICE")
        }
    }

    func factoryReset() {
        perform("恢复出厂设置") { api in
            try await api.set("RESTORE_FACTORY_SETTINGS")
        }
    }

    func changeAdminPassword(old: String, new: String) {
        Task {
            beginBusy()
            defer { endBusy() }
            do {
                // 先用旧密码登录，兼容“App 里存的密码和设备不一致”的情况
                try await api.login(username: "admin", password: old)
                try await api.set("CHANGE_PASSWORD", [
                    ("oldPassword", Data(old.utf8).base64EncodedString()),
                    ("newPassword", Data(new.utf8).base64EncodedString())
                ])
                adminPassword = new
                showToast("管理密码已修改")
            } catch {
                showToast("修改密码失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

}
