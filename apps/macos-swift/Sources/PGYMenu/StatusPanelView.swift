import SwiftUI

struct StatusPanelView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 8) {
                signalCard
                trafficCard
                wifiCard
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            Divider()
            footer
        }
        .frame(width: 342)
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(message: toast, isError: app.toastIsError)
                    .padding(.bottom, 44)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .onAppear {
            Task { await app.refreshSettings(silent: true) }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    StatusDot(active: app.reachable,
                              color: app.status.connected ? .green : .orange)
                    Text(app.status.operatorName.isEmpty ? "随身 WiFi" : app.status.operatorName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text(subtitleLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            SignalBarsView(bars: app.status.bars, height: 24, dimmed: !app.reachable)
            if app.status.bars > 0 {
                Text("\(app.status.bars)/5")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var subtitleLine: String {
        if !app.reachable { return app.lastError ?? "未连接设备" }
        let st = app.status
        var parts: [String] = [st.statusText]
        if st.networkLabel != "--" { parts.append(st.networkLabel) }
        if st.connected, st.sessionSeconds > 0 { parts.append("已连 " + Fmt.duration(st.sessionSeconds)) }
        return parts.joined(separator: " · ")
    }

    // MARK: - 信号

    private var signalCard: some View {
        Card(title: "信号") {
            HStack(spacing: 10) {
                MetricCell(title: "RSRP", value: Fmt.dbm(app.status.rsrp),
                           subtitle: app.status.signalQualityText,
                           valueColor: signalColor)
                MetricCell(title: "SINR", value: Fmt.db(app.status.sinr.map(Double.init)),
                           subtitle: "信噪比")
                MetricCell(title: "RSRQ", value: Fmt.db(app.status.rsrq),
                           subtitle: "质量")
            }
            HStack(spacing: 10) {
                MetricCell(title: "频段", value: app.status.bandText,
                           subtitle: app.status.arfcn.map { "EARFCN \($0)" } ?? "")
                MetricCell(title: "PCI", value: app.status.pci.map(String.init) ?? "--",
                           subtitle: app.status.cellID.map { "Cell \($0)" } ?? "")
                MetricCell(title: "网络", value: app.status.networkLabel,
                           subtitle: app.status.roaming ? "漫游中" : "非漫游")
            }
        }
    }

    private var signalColor: Color {
        guard let rsrp = app.status.rsrp else { return .primary }
        if rsrp >= -85 { return .green }
        if rsrp >= -100 { return .yellow }
        if rsrp >= -110 { return .orange }
        return .red
    }

    // MARK: - 流量

    private var trafficCard: some View {
        Card(title: "流量") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("实时速度")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label(Fmt.speed(app.status.rxSpeed), systemImage: "arrow.down")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                        Label(Fmt.speed(app.status.txSpeed), systemImage: "arrow.up")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
                Spacer()
                Button {
                    copySummary()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("复制流量信息")
            }
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                MetricCell(title: "本次连接", value: Fmt.bytes(app.status.sessionRx),
                           subtitle: "↑ \(Fmt.bytes(app.status.sessionTx))")
                MetricCell(title: "本月已用", value: Fmt.bytes(app.status.monthlyRx + app.status.monthlyTx),
                           subtitle: "↓ \(Fmt.bytes(app.status.monthlyRx)) · ↑ \(Fmt.bytes(app.status.monthlyTx))")
            }
            if app.status.dataLimitOn {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("限额已开启：\(app.status.dataLimitSize) • 提醒 \(app.status.dataLimitPercent)%")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copySummary() {
        let s = app.status
        let text = """
        \(s.operatorName) \(s.networkLabel) 信号\(s.bars)/5
        RSRP \(Fmt.dbm(s.rsrp))  SINR \(Fmt.db(s.sinr.map(Double.init)))  RSRQ \(Fmt.db(s.rsrq))
        频段 \(s.bandText)  PCI \(s.pci.map(String.init) ?? "--")
        本月 ↓\(Fmt.bytes(s.monthlyRx)) ↑\(Fmt.bytes(s.monthlyTx))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.showToast("已复制状态")
    }

    // MARK: - WiFi

    private var wifiCard: some View {
        Card(title: "WiFi") {
            HStack {
                Image(systemName: app.status.wifiOn ? "wifi" : "wifi.slash")
                    .foregroundStyle(app.status.wifiOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.status.wifiOn ? (app.wifi.ssid.isEmpty ? "WiFi 已开启" : app.wifi.ssid) : "WiFi 已关闭")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(app.clients.isEmpty ? "无已连接设备" : "\(app.clients.count) 台设备已连接")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.status.wifiOn },
                    set: { app.setWiFiEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        }
    }

    // MARK: - 设备

    private var deviceCard: some View {
        VStack(spacing: 3) {
            HStack {
                Text(app.baseURL?.host ?? "未连接")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if !app.status.firmware.isEmpty {
                    Text(app.status.firmware)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                app.openWebUI()
            } label: {
                Label("网页", systemImage: "safari")
            }

            Spacer()

            if app.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Button {
                app.retryDiscovery()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新检测设备")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出 PGY 随身 WiFi")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openSettings() {
        openWindow(id: "settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
