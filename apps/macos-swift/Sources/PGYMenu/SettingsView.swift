import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("pgy.settingsTab") private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $tab) {
                OverviewTab()
                    .tabItem { Label("概览", systemImage: "gauge.with.dots.needle.67percent") }
                    .tag(0)
                NetworkTab()
                    .tabItem { Label("网络", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(1)
                WiFiTab()
                    .tabItem { Label("WiFi", systemImage: "wifi") }
                    .tag(2)
                TrafficTab()
                    .tabItem { Label("流量", systemImage: "chart.bar.fill") }
                    .tag(3)
                RouterTab()
                    .tabItem { Label("路由", systemImage: "network") }
                    .tag(4)
                DeviceTab()
                    .tabItem { Label("设备", systemImage: "gearshape.2.fill") }
                    .tag(5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .frame(minWidth: 900, minHeight: 660)
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(message: toast, isError: app.toastIsError)
                    .padding(.bottom, 14)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            Task { await app.refreshSettings(silent: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.router.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("PGY 随身 WiFi")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    StatusDot(active: app.reachable, color: app.status.connected ? .green : .orange)
                    Text(app.reachable ? "\(app.baseURL?.host ?? "") · \(app.status.operatorName.isEmpty ? "设备已连接" : app.status.operatorName)" : (app.lastError ?? "未连接"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if app.isBusy {
                ProgressView().controlSize(.small)
            }
            Button {
                Task {
                    await app.refreshSettings()
                    await app.poll()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(!app.reachable)

            Button {
                app.openWebUI()
            } label: {
                Label("网页管理", systemImage: "safari")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
