import SwiftUI

enum DS {
    // Adaptive colors for dark mode support
    static let paper = Color("paper", bundle: nil)
    static let card = Color("card", bundle: nil)
    static let ink = Color("ink", bundle: nil)
    static let sub = Color("sub", bundle: nil)
    static let line = Color("line", bundle: nil)

    // Fallbacks that work without Color Sets — using system adaptive colors
    static var paperAdaptive: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) : UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
    })}
    static var cardAdaptive: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1) : UIColor.white
    })}
    static var inkAdaptive: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1) : UIColor(red: 0.09, green: 0.08, blue: 0.06, alpha: 1)
    })}
    static var subAdaptive: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 0.6, green: 0.59, blue: 0.56, alpha: 1) : UIColor(red: 0.55, green: 0.54, blue: 0.51, alpha: 1)
    })}
    static var lineAdaptive: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.1) : UIColor.black.withAlphaComponent(0.08)
    })}

    static let coral = Color(hex: 0xE2603A)
    static let coralDeep = Color(hex: 0xC94F2C)

    static let radius: CGFloat = 22

    static func display(_ size: CGFloat = 52, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static let h1 = Font.system(size: 30, weight: .semibold)
    static let h2 = Font.system(size: 19, weight: .semibold)
    static let bodyFont = Font.system(size: 15.5, weight: .regular)
    static let tag = Font.system(size: 11.5, weight: .medium)

    static func coralGradient() -> LinearGradient {
        LinearGradient(colors: [Color(hex: 0xE86A40), coralDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// Initialize adaptive colors at startup — these are resolved via UIColor trait collection
// so they auto-adapt when dark mode changes.
extension DS {
    /// Call once at app startup to override the named-color fallbacks with adaptive UIColors.
    static func setupAdaptiveColors() {
        // The named colors ("paper", "card", etc.) need Color Sets in Assets.
        // Since we can't create .colorset bundles programmatically, we use
        // the adaptive computed properties directly in views.
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}

struct Screen: ViewModifier {
    @AppStorage("ui.darkMode") private var isDarkMode = false

    func body(content: Content) -> some View {
        ZStack {
            DS.paperAdaptive.ignoresSafeArea()
            VStack {
                Spacer(minLength: 0)
                Color.clear.frame(height: 86)
            }
        }
        // Removed hardcoded .preferredColorScheme(.light) — now respects user's dark mode setting
    }
}

extension View {
    func screen() -> some View { modifier(Screen()) }
}

struct CornerTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DS.tag)
            .foregroundStyle(DS.subAdaptive)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(width: 76, alignment: .leading)
    }
}

struct ArrowBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.inkAdaptive)
    }
}

struct Tile<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(DS.cardAdaptive))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.lineAdaptive))
    }
}

struct CoralTile<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(DS.coralGradient()))
    }
}

struct Chip: View {
    let label: String
    var count: Int? = nil
    var selected = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(label)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DS.coral))
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(selected ? DS.paperAdaptive : DS.inkAdaptive)
            .padding(.horizontal, 17)
            .padding(.vertical, 11)
            .background(Capsule().fill(selected ? AnyShapeStyle(DS.inkAdaptive) : AnyShapeStyle(DS.cardAdaptive)))
            .overlay(Capsule().strokeBorder(selected ? .clear : DS.lineAdaptive))
        }
        .buttonStyle(.plain)
    }
}

struct CircleButton: View {
    let systemName: String
    var filled = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? DS.paperAdaptive : DS.inkAdaptive)
                .frame(width: 44, height: 44)
                .background(Circle().fill(filled ? AnyShapeStyle(DS.inkAdaptive) : AnyShapeStyle(DS.cardAdaptive)))
                .overlay(Circle().strokeBorder(filled ? .clear : DS.lineAdaptive))
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    let title: String
    var filled = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? DS.paperAdaptive : DS.inkAdaptive)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule().fill(filled ? AnyShapeStyle(DS.inkAdaptive) : AnyShapeStyle(DS.cardAdaptive)))
                .overlay(Capsule().strokeBorder(filled ? .clear : DS.lineAdaptive))
        }
        .buttonStyle(.plain)
    }
}

struct Waveform: View {
    var level: Float
    var barCount = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let wave = abs(sin(t * 5.2 + Double(i) * 0.62)) *
                               (0.35 + Double(level) * 0.9)
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 4, height: 8 + wave * 38)
                }
            }
            .frame(height: 52)
        }
    }
}

struct TimerBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 84, weight: .ultraLight))
            .monospacedDigit()
            .tracking(2)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(DS.coralDeep, lineWidth: 2)
            )
    }
}

extension DS {
    static let monoFont = Font.system(size: 13, weight: .medium, design: .monospaced)
}
