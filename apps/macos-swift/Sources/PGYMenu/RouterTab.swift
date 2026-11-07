import SwiftUI

struct RouterTab: View {
    @EnvironmentObject private var app: AppState

    // LAN / DHCP
    @State private var lanIP = "10.168.1.1"
    @State private var lanMask = "255.255.255.0"
    @State private var dhcpEnabled = true
    @State private var dhcpStart = "10.168.1.100"
    @State private var dhcpEnd = "10.168.1.200"
    @State private var dhcpLease = 24

    // DMZ
    @State private var dmzEnabled = false
    @State private var dmzIP = ""

    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    lanCard
                    VStack(spacing: 12) {
                        upnpCard
                        dmzCard
                    }
                }
                tipCard
            }
            .padding(.vertical, 4)
        }
        .onAppear { load() }
        .onChange(of: app.lan) { _, _ in load() }
        .onChange(of: app.dmz) { _, _ in load() }
    }

    private func load() {
        let l = app.lan
        lanIP = l.ipAddress
        lanMask = l.subnetMask
        dhcpEnabled = l.dhcpEnabled
        dhcpStart = l.dhcpStart
        dhcpEnd = l.dhcpEnd
        dhcpLease = l.dhcpLease
        dmzEnabled = app.dmz.enabled
        dmzIP = app.dmz.ipAddress
        loaded = true
    }

    // MARK: - 局域网

    private var lanCard: some View {
        Card(title: "局域网 (LAN / DHCP)") {
            HStack(spacing: 10) {
                Text("管理地址")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                TextField("192.168.0.1", text: $lanIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
            }
            HStack(spacing: 10) {
                Text("子网掩码")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                TextField("255.255.255.0", text: $lanMask)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
            }
            HStack(spacing: 10) {
                Text("DHCP 服务")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                Toggle("", isOn: $dhcpEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text(dhcpEnabled ? "开启（给接入设备自动分配 IP）" : "关闭（需手动设置 IP）")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            if dhcpEnabled {
                HStack(spacing: 10) {
                    Text("IP 池")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    TextField("起始", text: $dhcpStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("~")
                        .foregroundStyle(.secondary)
                    TextField("结束", text: $dhcpEnd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                HStack(spacing: 10) {
                    Text("租期")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    Picker("", selection: $dhcpLease) {
                        ForEach([2, 4, 8, 12, 24], id: \.self) { hours in
                            Text("\(hours) 小时").tag(hours)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            Button("保存局域网设置") {
                app.saveLAN(ip: lanIP.trimmingCharacters(in: .whitespaces),
                            mask: lanMask.trimmingCharacters(in: .whitespaces),
                            dhcpEnabled: dhcpEnabled,
                            start: dhcpStart.trimmingCharacters(in: .whitespaces),
                            end: dhcpEnd.trimmingCharacters(in: .whitespaces),
                            lease: dhcpLease)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!validLAN)

            Text("修改管理地址或 DHCP 后设备会重启网络，当前网页/管理连接会短暂断开。")
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity)
    }

    private var validLAN: Bool {
        !lanIP.isEmpty && !lanMask.isEmpty
            && (!dhcpEnabled || (!dhcpStart.isEmpty && !dhcpEnd.isEmpty))
    }

    // MARK: - UPnP

    private var upnpCard: some View {
        Card(title: "UPnP") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.upnpEnabled ? "已开启" : "已关闭")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("让下载、游戏等应用自动申请端口映射")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.upnpEnabled },
                    set: { app.setUpnp($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        }
    }

    // MARK: - DMZ

    private var dmzCard: some View {
        Card(title: "DMZ 主机") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dmzEnabled ? "已开启" : "已关闭")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("把所有外网端口转发到内网某一台主机，慎用")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $dmzEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                Text("目标 IP")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("例如 10.168.1.123", text: $dmzIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .disabled(!dmzEnabled)
                Button("保存 DMZ") {
                    app.saveDMZ(enabled: dmzEnabled, ip: dmzIP.trimmingCharacters(in: .whitespaces))
                }
                .controlSize(.small)
                .disabled(dmzEnabled && dmzIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var tipCard: some View {
        Card(title: "说明") {
            Text("· 局域网设置改的是这台随身 WiFi 自身的网段和 DHCP，不是 Mac 的网络配置。\n· 关闭 DHCP 后，接入设备需要手动设置同网段 IP 才能上网。\n· DMZ 与 UPnP 只在设备拨号上网（ppp_connected）时才有意义。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
