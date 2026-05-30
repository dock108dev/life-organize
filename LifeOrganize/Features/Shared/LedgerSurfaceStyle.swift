import SwiftUI

struct LedgerColorValue: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    func blended(over base: LedgerColorValue, opacity: Double) -> LedgerColorValue {
        LedgerColorValue(
            red: red * opacity + base.red * (1 - opacity),
            green: green * opacity + base.green * (1 - opacity),
            blue: blue * opacity + base.blue * (1 - opacity)
        )
    }

    func contrastRatio(against other: LedgerColorValue) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.03928
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    static let white = LedgerColorValue(red: 1, green: 1, blue: 1)
}

enum LedgerPalette {
    static let accentValue = LedgerColorValue(red: 0.145, green: 0.365, blue: 0.690)
    static let tealValue = LedgerColorValue(red: 0.025, green: 0.390, blue: 0.370)
    static let plumValue = LedgerColorValue(red: 0.520, green: 0.300, blue: 0.620)
    static let amberValue = LedgerColorValue(red: 0.610, green: 0.330, blue: 0.055)
    static let coralValue = LedgerColorValue(red: 0.660, green: 0.170, blue: 0.150)
    static let greenValue = LedgerColorValue(red: 0.090, green: 0.410, blue: 0.210)

    static let canvasTop = Color(red: 0.965, green: 0.982, blue: 0.980)
    static let canvasBottom = Color(red: 0.985, green: 0.966, blue: 0.930)
    static let surface = Color(.secondarySystemBackground).opacity(0.82)
    static let surfaceStrong = Color(.systemBackground).opacity(0.92)
    static let hairline = Color(red: 0.190, green: 0.210, blue: 0.230).opacity(0.10)
    static let accent = accentValue.color
    static let teal = tealValue.color
    static let plum = plumValue.color
    static let amber = amberValue.color
    static let coral = coralValue.color
    static let green = greenValue.color
}

enum LedgerSurfaceContract {
    static let cardCornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 10
    static let contentPadding: CGFloat = 14
    static let minimumInteractiveTarget: CGFloat = 44
    static let toolbarIconFrame: CGFloat = 36
    static let borderLineWidth: CGFloat = 1
    static let shadowOpacity: Double = 0.035
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
}

enum LedgerSemanticColorRole: Equatable, CaseIterable {
    case neutral
    case muted
    case interactive
    case success
    case attention
    case temporal
    case annotation
    case critical

    var foreground: Color {
        switch self {
        case .neutral, .muted:
            return .secondary
        case .interactive:
            return LedgerPalette.accent
        case .success:
            return LedgerPalette.green
        case .attention:
            return LedgerPalette.amber
        case .temporal:
            return LedgerPalette.teal
        case .annotation:
            return LedgerPalette.plum
        case .critical:
            return LedgerPalette.coral
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            return .secondary.opacity(backgroundOpacity)
        case .muted:
            return Color(.quaternarySystemFill)
        case .interactive:
            return LedgerPalette.accent.opacity(backgroundOpacity)
        case .success:
            return LedgerPalette.green.opacity(backgroundOpacity)
        case .attention:
            return LedgerPalette.amber.opacity(backgroundOpacity)
        case .temporal:
            return LedgerPalette.teal.opacity(backgroundOpacity)
        case .annotation:
            return LedgerPalette.plum.opacity(backgroundOpacity)
        case .critical:
            return LedgerPalette.coral.opacity(backgroundOpacity)
        }
    }

    var backgroundOpacity: Double {
        switch self {
        case .neutral, .interactive, .success, .annotation:
            return 0.08
        case .muted:
            return 1
        case .attention, .critical:
            return 0.10
        case .temporal:
            return 0.09
        }
    }

    var contrastColorValue: LedgerColorValue? {
        switch self {
        case .neutral, .muted:
            return nil
        case .interactive:
            return LedgerPalette.accentValue
        case .success:
            return LedgerPalette.greenValue
        case .attention:
            return LedgerPalette.amberValue
        case .temporal:
            return LedgerPalette.tealValue
        case .annotation:
            return LedgerPalette.plumValue
        case .critical:
            return LedgerPalette.coralValue
        }
    }
}

struct LedgerScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [LedgerPalette.canvasTop, LedgerPalette.canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LedgerSurfaceBackground: ViewModifier {
    var cornerRadius: CGFloat = LedgerSurfaceContract.cardCornerRadius
    var tint: LedgerTone?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LedgerPalette.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: LedgerSurfaceContract.borderLineWidth)
            }
            .shadow(
                color: Color.black.opacity(LedgerSurfaceContract.shadowOpacity),
                radius: LedgerSurfaceContract.shadowRadius,
                x: 0,
                y: LedgerSurfaceContract.shadowY
            )
    }

    private var borderColor: Color {
        tint?.foreground.opacity(0.18) ?? LedgerPalette.hairline
    }
}

extension View {
    func ledgerSurface(
        cornerRadius: CGFloat = LedgerSurfaceContract.cardCornerRadius,
        tint: LedgerTone? = nil
    ) -> some View {
        modifier(LedgerSurfaceBackground(cornerRadius: cornerRadius, tint: tint))
    }
}
