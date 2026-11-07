import SwiftUI

struct TrafficTab: View {
    @EnvironmentObject private var app: AppState

    @State private var limitEnabled = false
    @State private var unit: DataLimitUnit = .data
    @State private var size = ""
    @State private var alertPercent = "90"
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                usageCard
                limitCard
            }
            .padding(.vertical, 4)
        }
        .onAppear { load() }
        .onChange(of: app.status.dataLimitOn) { _, _ in load() }
    }

    private func load() {
        let s = app.status
        limitEnabled = s.dataLimitOn
        unit = s.dataLimitUnit == "time" ? .time : .data
        size = s.dataLimitSize
        alertPercent = s.dataLimitPercent.isEmpty ? "90" : s.dataLimitPercent
        loaded = true
    }

    private var usageCard: some View {
        Card(title: "流量统计") {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本月已用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Fmt.bytes(app.status.monthlyRx + app.status.monthlyTx))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                Divider().frame(height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("本次连接")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Fmt.bytes(app.status.sessionRx + app.status.sessionTx))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                Spacer()
            }
            Divider().opacity(0.5)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    small("本月下行", Fmt.bytes(app.status.monthlyRx))
                    small("本月上行", Fmt.bytes(app.status.monthlyTx))
                }
                GridRow {
                    small("本次下行", Fmt.bytes(app.status.sessionRx))
                    small("本次上行", Fmt.bytes(app.status.sessionTx))
                }
                GridRow {
                    small("本月在线", Fmt.duration(app.status.monthlySeconds))
                    small("本次在线", Fmt.duration(app.status.sessionSeconds))
                }
                GridRow {
                    small("实时下载", Fmt.speed(app.status.rxSpeed))
                    small("实时上传", Fmt.speed(app.status.txSpeed))
                }
            }
        }
    }

    private func small(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
        }
    }

    private var limitCard: some View {
        Card(title: "流量限额提醒") {
            Toggle("开启流量限额", isOn: $limitEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
            if limitEnabled {
                HStack(spacing: 12) {
                    Text("限额类型")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $unit) {
                        ForEach(DataLimitUnit.allCases) { u in
                            Text(u.title).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                HStack(spacing: 12) {
                    Text(unit == .data ? "每月流量上限" : "每月时长上限")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    TextField(unit == .data ? "例如 20（单位 MB）" : "例如 100（单位小时）", text: $size)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Text(unit == .data ? "MB" : "小时")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text("提醒阈值")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    TextField("90", text: $alertPercent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Button("保存限额设置") {
                app.setDataLimit(enabled: limitEnabled, unit: unit,
                                 size: size, alertPercent: alertPercent)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
