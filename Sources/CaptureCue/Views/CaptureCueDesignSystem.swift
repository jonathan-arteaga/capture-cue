import SwiftUI

enum CaptureCueTheme {
    static let ink = Color(red: 0.035, green: 0.055, blue: 0.12)
    static let midnight = Color(red: 0.075, green: 0.095, blue: 0.16)
    static let panel = Color(red: 0.965, green: 0.972, blue: 0.98)
    static let paper = Color(red: 0.992, green: 0.992, blue: 0.988)
    static let line = Color.black.opacity(0.08)
    static let aqua = Color(red: 0.05, green: 0.68, blue: 0.78)
    static let mint = Color(red: 0.38, green: 0.86, blue: 0.74)
    static let coral = Color(red: 1.0, green: 0.44, blue: 0.34)
    static let amber = Color(red: 0.98, green: 0.58, blue: 0.18)

    static var appBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.985, blue: 0.99),
                Color(red: 0.925, green: 0.955, blue: 0.965),
                Color(red: 0.985, green: 0.98, blue: 0.965)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var stageBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.075, blue: 0.12),
                Color(red: 0.11, green: 0.16, blue: 0.20),
                Color(red: 0.06, green: 0.13, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandWash: some ShapeStyle {
        LinearGradient(
            colors: [
                CaptureCueTheme.aqua.opacity(0.28),
                Color(red: 0.52, green: 0.70, blue: 0.95).opacity(0.18),
                CaptureCueTheme.mint.opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 8
    var strokeOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
            }
            .shadow(color: CaptureCueTheme.ink.opacity(0.10), radius: 22, y: 14)
    }
}

struct SoftPanel: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(CaptureCueTheme.paper.opacity(0.82), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CaptureCueTheme.line, lineWidth: 1)
            }
            .shadow(color: CaptureCueTheme.ink.opacity(0.06), radius: 16, y: 8)
    }
}

struct CaptureCueIconButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? .white : CaptureCueTheme.ink.opacity(0.74))
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(CaptureCueTheme.ink) : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.72)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? CaptureCueTheme.aqua.opacity(0.55) : CaptureCueTheme.line, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct CaptureCuePrimaryButtonStyle: ButtonStyle {
    var color: Color = CaptureCueTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(color.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: color.opacity(0.20), radius: 10, y: 5)
    }
}

struct CaptureCueSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CaptureCueTheme.ink.opacity(0.78))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.white.opacity(configuration.isPressed ? 0.48 : 0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CaptureCueTheme.line, lineWidth: 1)
            }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 8, strokeOpacity: Double = 0.12) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }

    func softPanel(cornerRadius: CGFloat = 8) -> some View {
        modifier(SoftPanel(cornerRadius: cornerRadius))
    }
}
