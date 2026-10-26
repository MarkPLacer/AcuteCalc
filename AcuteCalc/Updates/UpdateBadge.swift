import SwiftUI

extension View {
    /// A small red dot on the button that leads to Settings while a newer build is available,
    /// so a postponed update stays visible without asking again.
    func updateBadge() -> some View { modifier(UpdateBadge()) }
}

private struct UpdateBadge: ViewModifier {
    @Environment(UpdateChecker.self) private var updates

    func body(content: Content) -> some View {
        let available = updates.update != nil
        content
            .overlay(alignment: .topTrailing) {
                if available {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5) }
                        .offset(x: -2, y: 2)
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.snappy, value: available)
            .accessibilityValue(available ? "Na voljo je posodobitev" : "")
    }
}
