import SwiftUI

// MARK: - 信号柱

struct SignalBarsView: View {
    let bars: Int
    var height: CGFloat = 22
    var tint: Color = .accentColor
    var dimmed: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                let on = index < max(0, min(5, bars))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(on: on))
                    .frame(width: 4.5, height: height * (0.30 + CGFloat(index) * 0.175))
            }
        }
        .frame(height: height, alignment: .bottom)
        .opacity(dimmed ? 0.4 : 1)
        .animation(.easeOut(duration: 0.25), value: bars)
    }

    private func color(on: Bool) -> Color {
        guard on else { return Color.secondary.opacity(0.25) }
        switch bars {
        case 5, 4: return .green
        case 3: return .yellow
        case 2, 1: return .orange
        default: return .red
        }
    }
}

// MARK: - 指标块

struct MetricCell: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 信息行

struct InfoRow: View {
    let title: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 卡片

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - 状态点

struct StatusDot: View {
    let active: Bool
    var color: Color = .green

    var body: some View {
        Circle()
            .fill(active ? color : Color.secondary.opacity(0.35))
            .frame(width: 7, height: 7)
    }
}

// MARK: - 提示条

struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11.5))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
        )
        .padding(.horizontal, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
