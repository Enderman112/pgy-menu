import SwiftUI

struct NetworkTab: View {
    @EnvironmentObject private var app: AppState
    @State private var mode: NetworkMode = .auto
    @State private var simMode: SIMMode = .external
    @State private var confirmSIMSwitch = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if app.simSwitchAvailable { simCard }
                dataCard
                modeCard
                apnCard
                bandCard
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            mode = app.networkMode
            simMode = app.simMode
        }
        .onChange(of: app.networkMode) { _, newValue in mode = newValue }
        .onChange(of: app.simMode) { _, newValue in simMode = newValue }
        .alert("切换 SIM 卡", isPresented: $confirmSIMSwitch) {
            Button("取消", role: .cancel) {}
            Button("确定切换") { app.setSIMMode(simMode) }
        } message: {
            Text("将切换为「\(simMode.shortTitle)」。设备会重启，网络中断约 1 分钟，期间管理页面也会暂时打不开。")
        }
    }


    // MARK: - SIM 切换

    private var simCard: some View {
        Card(title: "SIM 切换") {
            HStack(spacing: 10) {
                Image(systemName: "simcard.2")
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前使用：\(app.simMode.shortTitle)")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("内置 eSIM 与外置实体卡二选一")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker("", selection: $simMode) {
                ForEach(SIMMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 10) {
                Button("切换 SIM") {
                    confirmSIMSwitch = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(simMode == app.simMode)
                Text("切换后设备重启约 1 分钟，网络会中断。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var dataCard: some View {
        Card(title: "移动数据") {
            HStack(spacing: 10) {
                Image(systemName: app.status.connected ? "network" : "network.slash")
                    .foregroundStyle(app.status.connected ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.status.statusText)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(app.status.operatorName) · \(app.status.networkLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(app.status.connected ? "断开" : "连接") {
                    app.setCellular(on: !app.status.connected)
                }
                .buttonStyle(.borderedProminent)
                .tint(app.status.connected ? .orange : .accentColor)
                .controlSize(.small)
            }
        }
    }

    private var modeCard: some View {
        Card(title: "网络模式") {
            Picker("", selection: $mode) {
                ForEach(NetworkMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, newValue in
                guard newValue != app.networkMode else { return }
                app.setNetworkMode(newValue)
            }
            Text("切换后设备会重新注册网络，信号可能短暂中断（约 10~30 秒）。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private var apnCard: some View {
        Card(title: "接入点 (APN)") {
            if app.apns.isEmpty {
                Text("暂未读取到 APN 配置")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(app.apns) { apn in
                    HStack(spacing: 10) {
                        Image(systemName: apn.isCurrent ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(apn.isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(apn.profileName.isEmpty ? "(未命名)" : apn.profileName)
                                .font(.system(size: 12, weight: .medium))
                            Text("APN: \(apn.apn)   协议: \(apn.pdpType)   鉴权: \(apn.auth)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !apn.isCurrent {
                            Button("设为默认") { app.setDefaultAPN(apn) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        } else {
                            Text("当前使用")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var bandCard: some View {
        Card(title: "频段") {
            HStack {
                Text("当前工作频段")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(app.status.bandText)  (EARFCN \(app.status.arfcn.map(String.init) ?? "--"))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            HStack {
                Text("频段锁定")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(app.bandLocked ? "已锁定" : "未锁定（自动选择）")
                    .font(.system(size: 11.5, weight: .medium))
            }
            Text("频段锁定可以提升弱信号下的稳定性，但锁错频段会导致无服务。本版本仅展示状态，未开放修改。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}
