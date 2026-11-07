import Foundation

/// `--selftest`：不弹界面，直接验证发现、轮询、登录与各读取接口是否正常。
///
/// 用法：`dist/PGYMenu.app/Contents/MacOS/PGYMenu --selftest`
enum SelfTest {
    static func run() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await perform()
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func perform() async {
        print("== PGY 随身 WiFi 自检 ==")
        print("时间: \(Date())")

        guard let url = await DeviceDiscovery.discover() else {
            print("❌ 未发现设备（请确认随身 WiFi 已插好，管理地址通常为 10.168.1.1）")
            print("   已尝试: \(DeviceDiscovery.interfaceCandidates() + DeviceDiscovery.knownHosts)")
            return
        }
        print("✅ 发现设备: \(url.absoluteString)")

        let api = DeviceAPI(baseURL: url)

        // 1. 免登录状态
        do {
            let fields = try await api.get([
                "signalbar", "network_type", "sub_network_type", "network_provider",
                "ppp_status", "lte_rsrp", "nv_rsrq", "nv_sinr", "nv_band",
                "nv_arfcn", "nv_pci", "nv_cellid", "monthly_rx_bytes", "monthly_tx_bytes"
            ])
            let rsrq = Int(fields["nv_rsrq"] ?? "").map { (Double($0) - 40) / 2 }
            print("✅ 状态读取: 信号 \(fields["signalbar"] ?? "-")/5, \(fields["network_provider"] ?? "-"), \(fields["sub_network_type"] ?? fields["network_type"] ?? "-"), \(fields["ppp_status"] ?? "-")")
            print("   RSRP \(fields["lte_rsrp"] ?? "-") dBm, RSRQ \(rsrq.map { String(format: "%.1f", $0) } ?? "-") dB, SINR \(fields["nv_sinr"] ?? "-") dB, Band \(fields["nv_band"] ?? "-"), PCI \(fields["nv_pci"] ?? "-"), CellID \(fields["nv_cellid"] ?? "-")")
        } catch {
            print("❌ 状态读取失败: \(error.localizedDescription)")
            return
        }

        // 2. 登录
        let password = Keychain.loadPassword() ?? "admin"
        var loggedIn = false
        do {
            loggedIn = try await api.login(username: "admin", password: password)
            print("✅ 登录成功（账号 admin / 密码 \(password == "admin" ? "默认 admin" : "来自钥匙串")）")
        } catch {
            print("⚠️ 登录失败: \(error.localizedDescription)（下面只能验证免登录接口）")
        }

        // 3. 需要登录的接口
        if loggedIn {
            do {
                let fields = try await api.get([
                    "SSID1", "HideSSID", "AuthMode", "EncrypType", "WPAPSK1_encode",
                    "MAX_Access_num", "wifi_cur_state", "wifi_coverage", "Sleep_interval",
                    "net_select", "imei", "msisdn", "ziccid", "cr_version", "hw_version",
                    "web_version", "LteBandLockSet"
                ])
                let pwd = Data(base64Encoded: fields["WPAPSK1_encode"] ?? "")
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("✅ 设置读取: WiFi \(fields["wifi_cur_state"] == "1" ? "开" : "关") SSID=\(fields["SSID1"] ?? "-") 密码=\(pwd) 加密=\(fields["AuthMode"] ?? "-") 最大连接=\(fields["MAX_Access_num"] ?? "-") 覆盖=\(fields["wifi_coverage"] ?? "-") 休眠=\(fields["Sleep_interval"] ?? "-") 分钟")
                print("   网络模式=\(fields["net_select"] ?? "-"), 频段锁定=\(fields["LteBandLockSet"] ?? "(空)")")
                print("   IMEI=\(fields["imei"] ?? "-") 号码=\(fields["msisdn"] ?? "-") ICCID=\(fields["ziccid"] ?? "-")")
                print("   固件=\(fields["cr_version"] ?? "-") 硬件=\(fields["hw_version"] ?? "-") Web=\(fields["web_version"] ?? "-")")
            } catch {
                print("❌ 设置读取失败: \(error.localizedDescription)")
            }

            // 4. 已连接设备
            do {
                let raw = try await api.get(cmd: "station_list")
                let arr = raw["station_list"] as? [[String: Any]] ?? []
                print("✅ 已连接 WiFi 设备: \(arr.count) 台")
                for item in arr.prefix(5) {
                    print("   - \(DeviceAPI.stringValue(item["hostname"] ?? "")) \(DeviceAPI.stringValue(item["ip_addr"] ?? "")) \(DeviceAPI.stringValue(item["mac_addr"] ?? ""))")
                }
            } catch {
                print("⚠️ 读取已连接设备失败: \(error.localizedDescription)")
            }

            // 5. 短信能力（本机实测为未启用）
            do {
                let raw = try await api.get(cmd: "sms_capacity_info")
                let nvTotal = DeviceAPI.stringValue(raw["sms_nv_total"] ?? "0")
                let simTotal = DeviceAPI.stringValue(raw["sms_sim_total"] ?? "0")
                print("ℹ️ 短信存储容量: 设备 \(nvTotal) 条 / SIM \(simTotal) 条（为 0 表示该设备未启用短信）")
            } catch {
                print("⚠️ 读取短信容量失败: \(error.localizedDescription)")
            }
        }

        // 6. 自动发现的候选地址
        print("   网卡候选网关: \(DeviceDiscovery.interfaceCandidates())")
        print("== 自检结束 ==")
    }
}
