import SwiftUI

// MARK: - Containers

/// A white card with a hairline border, as used for every group in the menu.
struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    var spacing: CGFloat = 11
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.label)
                    Spacer(minLength: 8)
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line))
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.label)
            Spacer(minLength: 10)
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.title).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
    }
}

struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.chipText)
            .background(Capsule().fill(Theme.chip))
    }
}

struct NoteText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.label)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MessageBox: View {
    enum Tone { case danger, warning }
    let text: String
    var tone: Tone = .danger

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(2)
            .foregroundStyle(tone == .danger ? Theme.dangerText : Theme.warningText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tone == .danger ? Theme.dangerBackground : Theme.warningBackground))
    }
}

// MARK: - Meters

struct MeterBar: View {
    let percent: Double?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if let percent {
                    Capsule()
                        .fill(Theme.meterColor(percent))
                        .frame(width: max(geo.size.width * min(max(percent, 0), 100) / 100, percent > 0 ? height : 0))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// One limit: name, percent, bar, reset, and pace for long windows.
struct MeterView: View {
    let window: UsageWindow
    var loading = false
    var thin = false
    var showPace = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).foregroundStyle(Theme.title)
                Spacer(minLength: 10)
                Text(valueText)
                    .fontWeight(.semibold)
                    .foregroundStyle(window.usedPercent == nil ? Theme.label : Theme.title)
            }
            .font(.system(size: 13))
            MeterBar(percent: window.notStarted ? 0 : window.usedPercent, height: thin ? 4 : 6)
            if let sub = subline {
                HStack {
                    Text(sub.left)
                    Spacer(minLength: 8)
                    if let right = sub.right { Text(right) }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.label)
            }
            if showPace, let pace = Pace.of(window) {
                PaceLine(pace: pace)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: String {
        if window.notStarted { return "Not started" }
        if let used = window.usedPercent { return "\(Int(used.rounded()))% used" }
        return loading ? "Checking…" : "—"
    }

    private var subline: (left: String, right: String?)? {
        if window.notStarted { return ("Starts with your next request", nil) }
        if let reset = window.resetsAt {
            let interval = reset.timeIntervalSince(Clock.now)
            if interval <= 0 { return ("Resetting now", nil) }
            if interval < 24 * 3600 {
                return ("Resets in \(DateCalculator.durationLabel(interval))", DateCalculator.timeLabel(for: reset))
            }
            return ("Resets \(DateCalculator.dayLabel(for: reset))", DateCalculator.timeLabel(for: reset))
        }
        if let text = window.resetText { return ("Resets \(text)", nil) }
        return nil
    }
}

struct PaceLine: View {
    let pace: Pace

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(pace.text)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(color)
    }

    private var icon: String {
        switch pace.tone {
        case .good: return "checkmark"
        case .warning: return "exclamationmark"
        case .danger: return "xmark"
        }
    }

    private var color: Color {
        switch pace.tone {
        case .good: return Theme.goodText
        case .warning: return Theme.warningText
        case .danger: return Theme.dangerText
        }
    }
}

// MARK: - Buttons

struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var fullWidth = true
    var corners: RectangleCornerRadii = .init(topLeading: 9, bottomLeading: 9, bottomTrailing: 9, topTrailing: 9)
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 14)
            .background(UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
                .fill(configuration.isPressed ? Theme.accentPressed : Theme.accent))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.title)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 12)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(configuration.isPressed ? Theme.hover : Theme.chip))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// A plain row in the footer or a list: icon, title, shortcut hint.
struct MenuRowButton: View {
    let icon: String
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.label)
                    .frame(width: 16)
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.title)
                Spacer(minLength: 4)
                if let shortcut {
                    Text(shortcut).font(.system(size: 12)).foregroundStyle(Theme.label)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Spinner: View {
    var color: Color = Theme.brand
    var size: CGFloat = 12
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 1)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
            .accessibilityLabel("Working")
    }
}

/// A two-option or three-option pill switcher drawn in SwiftUI.
struct PillSegment<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(selection == value ? Theme.title : Theme.label)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selection == value ? Theme.tabOn : .clear)
                            .shadow(color: .black.opacity(selection == value ? 0.1 : 0), radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.chip))
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}
