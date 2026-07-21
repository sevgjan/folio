import SwiftUI

struct UpdateBannerView: View {
    @Bindable var store: UpdateStore

    var body: some View {
        switch store.state {
        case .none:
            EmptyView()
        case .available(let info):
            banner {
                SwiftUI.Text("Folio \(info.version) is available")
                Button("Download") { store.startDownload(info) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Dismiss") { store.dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let progress, let version):
            banner {
                SwiftUI.Text("Downloading Folio \(version)…")
                ProgressView(value: progress)
                    .frame(width: 100)
            }
        case .ready(_, let version):
            banner {
                SwiftUI.Text("Folio \(version) is ready to install")
                Button("Restart & Install") { store.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        case .failed(let message):
            banner {
                SwiftUI.Text("Update failed: \(message)")
                Button("Dismiss") { store.dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .fixedSize()
    }
}
