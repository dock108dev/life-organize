import SwiftUI

enum LedgerPalette {
    static let canvasTop = Color(red: 0.965, green: 0.982, blue: 0.980)
    static let canvasBottom = Color(red: 0.985, green: 0.966, blue: 0.930)
    static let surface = Color(.secondarySystemBackground).opacity(0.82)
    static let surfaceStrong = Color(.systemBackground).opacity(0.92)
    static let hairline = Color(red: 0.190, green: 0.210, blue: 0.230).opacity(0.10)
    static let accent = Color(red: 0.145, green: 0.365, blue: 0.690)
    static let teal = Color(red: 0.070, green: 0.530, blue: 0.500)
    static let plum = Color(red: 0.520, green: 0.300, blue: 0.620)
    static let amber = Color(red: 0.820, green: 0.470, blue: 0.120)
    static let coral = Color(red: 0.800, green: 0.260, blue: 0.240)
    static let green = Color(red: 0.180, green: 0.520, blue: 0.300)
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
    var cornerRadius: CGFloat = 12
    var tint: LedgerTone?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LedgerPalette.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 4)
    }

    private var borderColor: Color {
        tint?.foreground.opacity(0.18) ?? LedgerPalette.hairline
    }
}

extension View {
    func ledgerSurface(cornerRadius: CGFloat = 12, tint: LedgerTone? = nil) -> some View {
        modifier(LedgerSurfaceBackground(cornerRadius: cornerRadius, tint: tint))
    }
}
