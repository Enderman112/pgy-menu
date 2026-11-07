import SwiftUI

struct WiFiTab: View {
    @EnvironmentObject private var app: AppState

    @State private var enabled = false
    @State private var ssid = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var authMode = "WPAPSKWPA2PSK"
    @State private var hidden = false
    @State private var maxClients = 8
    @State private var sleepMinutes = -1
    @State private var loaded = false

    private let authModes: [(String, String)] = [
        ("WPAPSKWPA2PSK", "WPA/WPA2-PSK（推荐）"),
        ("WPA2PSK", "WPA2-PSK"),
        ("OPEN", "不加密（开放网络）")
    ]

    private let sleepOptions: [(Int, String)] = [
        (-1, "常开（不休眠）"),
        (5, "空闲 5 分钟后休眠"),
        (10, "空闲 10 分钟后休眠"),
        (20, "空闲 20 分钟后休眠"),
        (30, "空闲 30 分钟后休眠"),
        (60, "空闲 1 小时后休眠"),
        (120, "空闲 2 小时后休眠")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusCard
                basicCard
                clientsCard
            }
            .padding(.vertical, 4)
        }
        .onAppear { loadFromDevice() }
        .onChange(of: app.wifi) { _, _ in loadFromDevice() }
    }

    private func loadFromDevice() {
        let w = app.wifi
        guard w.ssid.isEmpty == false || loaded == false else { return }
        enabled = w.enabled
        ssid = w.ssid
        password = w.password
        authMode = w.authMode.isEmpty ? "WPAPSKWPA2PSK" : w.authMode
        hidden = w.hideSSID
        maxClients = w.maxClients
        sleepMinutes = w.sleepMinutes
        loaded = true
    }

    private var statusCard: some View {
        Card(title: "WiFi 热点") {
            HStack(spacing: 10) {
                Image(systemName: app.status.wifiOn ? "wifi" : "wifi.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(app.status.wifiOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.status.wifiOn ? "WiFi 已开启" : "WiFi 已关闭")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(app.clients.count) 台设备已连接")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.status.wifiOn },
                    set: { app.setWiFiEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var basicCard: some View {
        Card(title: "热点设置") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("名称 (SSID)")
                        .font(.system(size: 12))
                        .frame(width: 88, alignment: .leading)
                    TextField("WiFi 名称", text: $ssid)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                HStack(spacing: 10) {
                    Text("密码")
                        .font(.system(size: 12))
                        .frame(width: 88, alignment: .leading)
                    Group {
                        if showPassword {
                            TextField("WiFi 密码", text: $password)
                        } else {
                            SecureField("WiFi 密码", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                HStack(spacing: 10) {
                    Text("加密方式")
                        .font(.system(size: 12))
                        .frame(width: 88, alignment: .leading)
                    Picker("", selection: $authMode) {
                        ForEach(authModes, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
                HStack(spacing: 10) {
                    Text("最大连接")
                        .font(.system(size: 12))
                        .frame(width: 88, alignment: .leading)
                    Stepper(value: $maxClients, in: 1...32) {
                        Text("\(maxClients) 台设备")
                            .font(.system(size: 12))
                    }
                    .frame(width: 180)
                }
                HStack(spacing: 10) {
                    Text("隐藏网络")
                        .font(.system(size: 12))
                        .frame(width: 88, alignment: .leading)
                    Toggle("不广播 SSID", isOn: $hidden)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                HStack(spacing: 10) {
                    Text("WiFi 休眠")
                        .font(.system(size: 12))
                        .frame(width: 88, alignment: .leading)
                    Picker("", selection: $sleepMinutes) {
                        ForEach(sleepOptions, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .onChange(of: sleepMinutes) { _, newValue in
                        guard newValue != app.wifi.sleepMinutes else { return }
                        app.setWiFiSleep(minutes: newValue)
                    }
                }

                HStack(spacing: 10) {
                    Spacer().frame(width: 98)
                    Button("保存 WiFi 设置") {
                        app.saveWiFiSettings(
                            ssid: ssid.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password,
                            authMode: authMode,
                            hidden: hidden,
                            maxClients: maxClients
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(ssid.isEmpty || ((authMode != "OPEN") && password.count < 8))
                    Text(authMode == "OPEN" ? "" : (password.count < 8 ? "密码至少 8 位" : ""))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                Text("修改名称/密码后，已连接的设备会断开，需要用新密码重新连接。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var clientsCard: some View {
        Card(title: "已连接设备") {
            if app.clients.isEmpty {
                Text("暂无设备连接")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(app.clients) { client in
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .foregroundStyle(.secondary)
                        Text(client.hostName)
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(client.ipAddress)   \(client.macAddress)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
