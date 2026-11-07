import Foundation
import ServiceManagement

/// 开机自动启动。
///
/// 优先用 macOS 13+ 的 `SMAppService`；如果 App 是 ad-hoc 签名 / 位置不固定导致注册失败，
/// 自动退回到 `~/Library/LaunchAgents` 方案（对未签名 App 更可靠）。
enum LaunchAtLogin {
    private static let label = "com.xuyaoshi.pgymenu"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            return true
        }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            // 1) 先试系统登录项
            if #available(macOS 13.0, *) {
                do {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                    removeAgent()
                    return
                } catch {
                    // 继续走 LaunchAgent 兜底
                }
            }
            try installAgent()
        } else {
            if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
            removeAgent()
        }
    }

    // MARK: - LaunchAgent 兜底

    private static func installAgent() throws {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            throw NSError(domain: "PGYMenu", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "只能从 .app 包里设置开机启动"])
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        let dir = agentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plist.write(to: agentURL, atomically: true, encoding: .utf8)

        // 已经加载过就先卸载，忽略错误
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        let result = runLaunchctl(["bootstrap", "gui/\(getuid())", agentURL.path])
        if let result, result.status != 0 {
            throw NSError(domain: "PGYMenu", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: "launchctl bootstrap 失败：\(result.output)"
            ])
        }
    }

    private static func removeAgent() {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: agentURL)
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return nil
        }
    }
}
