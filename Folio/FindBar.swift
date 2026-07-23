import SwiftUI

struct FindBar: View {
    @Bindable var state: FindState
    var onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in document", text: $state.query)
                .textFieldStyle(.plain)
                .frame(width: 220)
                .focused($isFocused)

            if !state.matches.isEmpty {
                Text(state.matchDescription)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .monospacedDigit()
            }

            HStack(spacing: 0) {
                Button(action: { state.previous() }) {
                    Image(systemName: "chevron.up")
                        .contentShape(Rectangle())
                        .padding(6)
                }
                .buttonStyle(.borderless)

                Button(action: { state.next() }) {
                    Image(systemName: "chevron.down")
                        .contentShape(Rectangle())
                        .padding(6)
                }
                .buttonStyle(.borderless)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .contentShape(Rectangle())
                    .padding(6)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .padding(12)
        .onAppear { isFocused = true }
        // onKeyPress used instead of onSubmit, which didn't fire reliably here.
        .onKeyPress { press in
            switch press.key {
            case .return:
                if press.modifiers.contains(.shift) {
                    state.previous()
                } else {
                    state.next()
                }
                return .handled
            case .escape:
                onClose()
                return .handled
            default:
                return .ignored
            }
        }
    }
}
