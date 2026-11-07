import Foundation
import Darwin

/// 自动发现随身 WiFi 的管理地址。
///
/// 策略：
/// 1. 遍历本机网卡，找私有网段里 `en*` 接口的对端网关（x.x.x.1）；
/// 2. 再补充常见随身 WiFi 的管理地址；
/// 3. 并发探测 `/goform/goform_get_cmd_process`，谁的返回里带 `network_type` 就认定是谁。
enum DeviceDiscovery {
    static let knownHosts = [
        "10.168.1.1", "192.168.0.1", "192.168.1.1",
        "192.168.8.1", "192.168.43.1", "192.168.100.1",
        "192.168.1.100"
    ]

    /// 本机所有私有网段网卡计算出的候选网关。
    static func interfaceCandidates() -> [String] {
        var results: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return results }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let p = pointer {
            let ent = p.pointee
            if let addr = ent.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: ent.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("bridge") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let len = socklen_t(addr.pointee.sa_len)
                    if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if let maskAddr = ent.ifa_netmask {
                            var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                            if getnameinfo(maskAddr, socklen_t(maskAddr.pointee.sa_len), &maskBuf,
                                           socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                                let mask = String(cString: maskBuf)
                                if let net = gateway(for: ip, netmask: mask) {
                                    results.append(net)
                                }
                            }
                        }
                    }
                }
            }
            pointer = ent.ifa_next
        }
        return results
    }

    /// 由 IP + 掩码推出网关候选（私有段才返回）。
    private static func gateway(for ip: String, netmask: String) -> String? {
        let ipParts = ip.split(separator: ".").compactMap { Int($0) }
        guard ipParts.count == 4 else { return nil }
        // 只处理常见私网
        let isPrivate = ipParts[0] == 10
            || (ipParts[0] == 192 && ipParts[1] == 168)
            || (ipParts[0] == 172 && (16...31).contains(ipParts[1]))
        guard isPrivate else { return nil }
        return "\(ipParts[0]).\(ipParts[1]).\(ipParts[2]).1"
    }

    /// 并发探测候选地址，返回第一个可用的管理地址。
    static func discover() async -> URL? {
        var seen = Set<String>()
        var candidates: [String] = []
        for host in interfaceCandidates() + knownHosts where seen.insert(host).inserted {
            candidates.append(host)
        }

        return await withTaskGroup(of: URL?.self) { group in
            for host in candidates {
                group.addTask { await probe(host: host) }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    /// 探测单个地址是否是目标设备的 UFI 接口。
    static func probe(host: String) async -> URL? {
        guard let url = URL(string: "http://\(host)/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=network_type,signalbar") else {
            return nil
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.0
        config.timeoutIntervalForResource = 1.2
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        var req = URLRequest(url: url)
        req.setValue("PGYMenu/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: req)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if obj["network_type"] != nil || obj["signalbar"] != nil {
                return URL(string: "http://\(host)")
            }
        } catch {
            return nil
        }
        return nil
    }
}
