import SwiftUI

private enum MaintenanceAction: String, Identifiable {
    case reboot, powerOff, factoryReset
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reboot: return "重启设备"
        case .powerOff: return "关闭设备"
        case .factoryReset: return "恢复出厂设置"
        }
    }
    var message: String {
        switch self {
        case .reboot: return "设备将重启，网络会中断约 30 秒。确定要继续吗？"
        case .powerOff: return "设备将关机，需要重新插拔/长按电源键才能开机。确定吗？"
        case .factoryReset: return "将清除所有设置（WiFi 名称/密码、APN、管理密码等），且不可撤销！确定吗？"
        }
    }
}

struct DeviceTab: View {
    @EnvironmentObject private var app: AppState

    @State private var pendingAction: MaintenanceAction?
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var host = ""
    @State private var refreshSeconds: Double = 2
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    infoCard
                    maintenanceCard
                }
                HStack(alignment: .top, spacing: 12) {
                    passwordCard
                    preferencesCard
                }
                aboutCard
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            host = app.preferredHost
            refreshSeconds = app.refreshSeconds
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text("确定")) {
                    switch action {
                    case .reboot: app.rebootDevice()
                    case .powerOff: app.powerOffDevice()
                    case .factoryReset: app.factoryReset()
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var infoCard: some View {
        Card(title: "设备信息") {
            InfoRow(title: "管理地址", value: app.baseURL?.absoluteString ?? "未连接")
            InfoRow(title: "IMEI", value: empty(app.status.imei), mono: true)
            InfoRow(title: "IMSI", value: empty(app.status.imsi), mono: true)
            InfoRow(title: "本机号码", value: empty(app.status.phoneNumber), mono: true)
            InfoRow(title: "ICCID", value: empty(app.status.iccid), mono: true)
            InfoRow(title: "固件版本", value: empty(app.status.firmware), mono: true)
            InfoRow(title: "硬件版本", value: empty(app.status.hardware), mono: true)
            InfoRow(title: "Web 版本", value: empty(app.status.webVersion), mono: true)
            InfoRow(title: "运行时长", value: Fmt.duration(app.status.uptime))
            if let battery = app.status.batteryPercent {
                InfoRow(title: "电量", value: "\(battery)%")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var maintenanceCard: some View {
        Card(title: "维护") {
            Button {
                pendingAction = .reboot
            } label: {
                Label("重启设备", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                pendingAction = .powerOff
            } label: {
                Label("关闭设备", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                pendingAction = .factoryReset
            } label: {
                Label("恢复出厂设置", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Divider().opacity(0.5)

            Button {
                app.openWebUI()
            } label: {
                Label("打开设备网页管理", systemImage: "safari")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Text("网页管理里还有短信中心、LAN/DHCP、端口映射等高级功能。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var passwordCard: some View {
        Card(title: "管理密码") {
            SecureField("当前密码（默认 admin）", text: $oldPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("新密码", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("确认新密码", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button("用此密码登录并保存") {
                    app.adminPassword = oldPassword
                    app.showToast("已保存登录密码，正在重新登录…")
                    Task { await app.refreshSettings() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(oldPassword.isEmpty)
                Button("修改密码") {
                    app.changeAdminPassword(old: oldPassword, new: newPassword)
                    oldPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newPassword.count < 6 || newPassword != confirmPassword)
                if !newPassword.isEmpty && newPassword != confirmPassword {
                    Text("两次输入不一致")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
            }
            Text("密码保存在 macOS 钥匙串中，仅本机可见。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var preferencesCard: some View {
        Card(title: "连接与显示") {
            HStack(spacing: 8) {
                Text("管理地址")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("自动检测（留空）", text: $host)
                    .textFieldStyle(.roundedBorder)
                Button("应用") {
                    app.preferredHost = host.trimmingCharacters(in: .whitespaces)
                    app.retryDiscovery()
                }
                .controlSize(.small)
            }
            HStack(spacing: 8) {
                Text("刷新间隔")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Picker("", selection: $refreshSeconds) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: refreshSeconds) { _, newValue in
                    app.refreshSeconds = newValue
                    app.start()
                }
            }
            Toggle("在菜单栏显示网络类型文字", isOn: Binding(
                get: { app.showTextInMenuBar },
                set: { app.showTextInMenuBar = $0; app.retryDiscovery() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("开机自动启动", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    } catch {
                        app.showToast("开机启动设置失败：\(error.localizedDescription)", isError: true)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var aboutCard: some View {
        Card(title: "关于") {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wifi.router.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PGY 随身 WiFi")
                        .font(.system(size: 13, weight: .semibold))
                    Text("菜单栏实时信号 · 设备设置面板 · 短信 · 流量统计")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("适用于 X4U / PGY 系列随身 WiFi（Unisoc 方案，管理页 http://10.168.1.1）")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("退出 App") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
    }

    private func empty(_ value: String) -> String {
        value.isEmpty ? "--" : value
    }
}
