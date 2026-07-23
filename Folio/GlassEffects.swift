import SwiftUI

// Liquid Glass on macOS 26+, falling back to the old translucent material below that.
extension View {
    @ViewBuilder
    func glassPanel<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
