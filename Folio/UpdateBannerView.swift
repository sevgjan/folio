import SwiftUI

struct UpdateBannerView: View {
    @Bindable var store: UpdateStore

    var body: some View {
        switch store.state {
        case .none:
            EmptyView()
        case .available(let info):
            banner {
                SwiftUI.Text("Folio \(info.version) is available.")
                Spacer()
                Button("Download") { store.startDownload(info) }
                Button("Dismiss") { store.dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let progress, let version):
            banner {
                SwiftUI.Text("Downloading Folio \(version)…")
                ProgressView(value: progress)
                    .frame(width: 120)
                Spacer()
            }
        case .ready(_, let version):
            banner {
                SwiftUI.Text("Folio \(version) is ready to install.")
                Spacer()
                Button("Restart & Install") { store.installAndRelaunch() }
            }
        case .failed(let message):
            banner {
                SwiftUI.Text("Update failed: \(message)")
                Spacer()
                Button("Dismiss") { store.dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}
