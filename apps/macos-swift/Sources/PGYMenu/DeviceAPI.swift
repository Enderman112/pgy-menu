import Foundation

/// 设备返回的统一错误。
enum DeviceError: LocalizedError {
    case unreachable
    case http(Int)
    case badResponse
    case loginRequired
    case loginFailed
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: return "无法连接随身 WiFi，请检查 USB 线/接口"
        case .http(let code): return "设备返回 HTTP \(code)"
        case .badResponse: return "设备返回的数据无法解析"
        case .loginRequired: return "需要先登录设备管理后台"
        case .loginFailed: return "登录失败，请检查管理密码"
        case .failed(let message): return message
        }
    }
}

/// 一个极简的 HTTP 客户端，负责和随身 WiFi 的 UFI WebAPI 通讯。
final class DeviceAPI {
    private(set) var baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        config.httpShouldUsePipelining = false
        config.httpAdditionalHeaders = [
            "Accept": "*/*",
            "User-Agent": "Mozilla/5.0 (Macintosh) PGYMenu/1.0"
        ]
        self.session = URLSession(configuration: config)
    }

    func update(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - 原始请求

    private func request(path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw DeviceError.unreachable
        }
        var items = [URLQueryItem(name: "isTest", value: "false")]
        items.append(contentsOf: query)
        if path.hasSuffix("get_cmd_process") {
            comps.queryItems = items
        }
        guard let url = comps.url else { throw DeviceError.unreachable }

        var req = URLRequest(url: url)
        req.setValue("http://\(baseURL.host ?? "10.168.1.1")/index.html", forHTTPHeaderField: "Referer")
        req.setValue("http://\(baseURL.host ?? "10.168.1.1")", forHTTPHeaderField: "Origin")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw DeviceError.unreachable
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw DeviceError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceError.badResponse
        }
        return obj
    }

    private func post(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: baseURL.appendingPathComponent("/goform/goform_set_cmd_process"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("http://\(baseURL.host ?? "10.168.1.1")/index.html", forHTTPHeaderField: "Referer")
        req.setValue("http://\(baseURL.host ?? "10.168.1.1")", forHTTPHeaderField: "Origin")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        var comps = URLComponents()
        comps.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        let encoded = (comps.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        req.httpBody = encoded.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw DeviceError.unreachable
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw DeviceError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceError.badResponse
        }
        return obj
    }

    // MARK: - 读取

    /// 批量读取设备字段（goform_get_cmd_process, multi_data=1）。
    func get(_ cmds: [String]) async throws -> [String: String] {
        let raw = try await request(
            path: "/goform/goform_get_cmd_process",
            query: [
                URLQueryItem(name: "multi_data", value: "1"),
                URLQueryItem(name: "cmd", value: cmds.joined(separator: ","))
            ]
        )
        return raw.mapValues { Self.stringValue($0) }
    }

    /// 读取任意参数组合（短信列表等需要额外参数）。
    func getRaw(_ params: [URLQueryItem]) async throws -> [String: Any] {
        try await request(path: "/goform/goform_get_cmd_process", query: params)
    }

    func get(cmd: String, extra: [URLQueryItem] = []) async throws -> [String: Any] {
        var qs = [URLQueryItem(name: "cmd", value: cmd)]
        qs.append(contentsOf: extra)
        return try await request(path: "/goform/goform_get_cmd_process", query: qs)
    }

    // MARK: - 写入

    /// 执行一条 set 命令。成功返回 true。
    @discardableResult
    func set(_ goformId: String, _ params: [(String, String)] = []) async throws -> [String: Any] {
        var form: [String: String] = ["goformId": goformId]
        for (k, v) in params { form[k] = v }
        let result = try await post(form)
        let value = Self.stringValue(result["result"] ?? "")
        if value == "success" || value == "0" {
            return result
        }
        if value == "failure" {
            throw DeviceError.failed("操作被设备拒绝（可能未登录或参数不合法）")
        }
        throw DeviceError.failed("设备返回：\(value)")
    }

    // MARK: - 登录

    @discardableResult
    func login(username: String, password: String) async throws -> Bool {
        let result = try await post([
            "goformId": "LOGIN",
            "username": Data(username.utf8).base64EncodedString(),
            "password": Data(password.utf8).base64EncodedString()
        ])
        let value = Self.stringValue(result["result"] ?? "")
        if value == "0" || value == "4" { return true }
        throw DeviceError.loginFailed
    }

    func isLoggedIn() async -> Bool {
        guard let fields = try? await get(["loginfo"]) else { return false }
        return fields["loginfo"] == "ok"
    }

    func logout() async {
        _ = try? await set("LOGOUT")
    }

    // MARK: - 工具

    static func stringValue(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case is NSNull: return ""
        default: return ""
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    static func int64Value(_ value: Any?) -> Int64? {
        guard let value else { return nil }
        if let s = value as? String { return Int64(s.trimmingCharacters(in: .whitespaces)) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }
}
