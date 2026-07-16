import AppKit
import Observation

enum UpdateState: Equatable {
    case none
    case available(UpdateInfo)
    case downloading(progress: Double, version: String)
    case ready(mountPoint: URL, version: String)
    case failed(String)
}

@MainActor
@Observable
final class UpdateStore {
    var state: UpdateState = .none
    private var hasChecked = false
    private var updater: Updater?

    func checkForUpdatesOnce() async {
        guard !hasChecked else { return }
        hasChecked = true
        guard let info = try? await UpdateChecker.checkForUpdates() else { return }
        state = .available(info)
    }

    func startDownload(_ info: UpdateInfo) {
        guard let dmgURL = info.downloadURL else {
            NSWorkspace.shared.open(info.releasePageURL)
            return
        }
        let u = Updater()
        updater = u
        state = .downloading(progress: 0, version: info.version)
        Task {
            await u.download(url: dmgURL) { [weak self] progress in
                self?.state = .downloading(progress: progress, version: info.version)
            } onComplete: { [weak self] mountPoint in
                self?.state = .ready(mountPoint: mountPoint, version: info.version)
            } onError: { [weak self] message in
                self?.state = .failed(message)
            }
        }
    }

    func installAndRelaunch() {
        guard case let .ready(mountPoint, _) = state else { return }
        updater?.install(mountPoint: mountPoint)
        NSApp.terminate(nil)
    }

    func dismiss() {
        state = .none
    }
}
