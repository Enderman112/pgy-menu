import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject private var app: AppState

    private var s: DeviceStatus { app.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    signalCard
                    connectionCard
                }
                HStack(alignment: .top, spacing: 12) {
                    deviceCard
                    clientsCard
                }
                apnCard
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 信号

    private var signalCard: some View {
        Card(title: "信号质量") {
            HStack(spacing: 14) {
                SignalBarsView(bars: s.bars, height: 42, dimmed: !app.reachable)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.signalQualityText)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(s.bars)/5 格 · \(s.networkLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider().opacity(0.5)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    metric("RSRP", Fmt.dbm(s.rsrp))
                    metric("SINR", Fmt.db(s.sinr.map(Double.init)))
                }
                GridRow {
                    metric("RSRQ", Fmt.db(s.rsrq))
                    metric("CQI", s.cqi.map(String.init) ?? "--")
                }
                GridRow {
                    metric("频段", s.bandText)
                    metric("EARFCN", s.arfcn.map(String.init) ?? "--")
                }
                GridRow {
                    metric("PCI", s.pci.map(String.init) ?? "--")
                    metric("Cell ID", s.cellID.map(String.init) ?? "--")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .textSelection(.enabled)
        }
    }

    // MARK: 连接

    private var connectionCard: some View {
        Card(title: "连接状态") {
            HStack(spacing: 8) {
                StatusDot(active: s.connected, color: .green)
                Text(s.statusText)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if s.connected {
                    Text("已连 " + Fmt.duration(s.sessionSeconds))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Divider().opacity(0.5)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    label("运营商")
                    value(s.operatorName.isEmpty ? "--" : s.operatorName)
                }
                GridRow {
                    label("网络制式")
                    value(s.networkLabel)
                }
                GridRow {
                    label("网络模式")
                    value(app.networkMode.title)
                }
                GridRow {
                    label("SIM 卡")
                    value(simText)
                }
                GridRow {
                    label("漫游")
                    value(s.roaming ? "是" : "否")
                }
            }
            HStack(spacing: 8) {
                Button(s.connected ? "断开数据" : "拨号连接") {
                    app.setCellular(on: !s.connected)
                }
                .buttonStyle(.borderedProminent)
                .tint(s.connected ? .orange : .accentColor)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var simText: String {
        switch s.simCardState {
        case "READY": return "已就绪"
        case "": return "--"
        default: return s.simCardState
        }
    }

    // MARK: 设备

    private var deviceCard: some View {
        Card(title: "设备") {
            InfoRow(title: "IMEI", value: s.imei.isEmpty ? "--" : s.imei, mono: true)
            InfoRow(title: "本机号码", value: s.phoneNumber.isEmpty ? "--" : s.phoneNumber, mono: true)
            InfoRow(title: "ICCID", value: s.iccid.isEmpty ? "--" : s.iccid, mono: true)
            InfoRow(title: "固件版本", value: s.firmware.isEmpty ? "--" : s.firmware, mono: true)
            InfoRow(title: "硬件版本", value: s.hardware.isEmpty ? "--" : s.hardware, mono: true)
            InfoRow(title: "运行时长", value: Fmt.duration(s.uptime))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 客户端

    private var clientsCard: some View {
        Card(title: "已连接设备 (\(app.clients.count))") {
            if app.clients.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.secondary)
                    Text(app.status.wifiOn ? "暂时没有设备连接到此 WiFi" : "WiFi 当前已关闭")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(app.clients) { client in
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(client.hostName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)
                                Text("\(client.ipAddress)  \(client.macAddress)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
            Button {
                Task { await app.refreshSettings(silent: true) }
            } label: {
                Label("刷新列表", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: APN

    private var apnCard: some View {
        Card(title: "接入点 (APN)") {
            if app.apns.isEmpty {
                Text("--")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(app.apns) { apn in
                    HStack(spacing: 10) {
                        Image(systemName: apn.isCurrent ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(apn.isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(apn.profileName.isEmpty ? "(未命名)" : apn.profileName)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(apn.apn) · \(apn.pdpType) · \(apn.mode)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !apn.isCurrent {
                            Button("设为默认") {
                                app.setDefaultAPN(apn)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 62, alignment: .leading)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
    }
}
