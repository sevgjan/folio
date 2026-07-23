import Foundation

/// FileDocument/DocumentGroup only reads the file once, on open — it has no built-in
/// awareness of the file changing on disk afterward. Editing the same file in another
/// app (VS Code, etc.) previously required closing and reopening the Folio window to
/// see the update. This registers as an NSFilePresenter so macOS notifies us whenever
/// the file is modified externally, and reloads it into the document automatically.
final class FileChangeMonitor: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onExternalChange: (String) -> Void

    init(fileURL: URL, onExternalChange: @escaping (String) -> Void) {
        self.presentedItemURL = fileURL
        self.onExternalChange = onExternalChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        let coordinator = NSFileCoordinator(filePresenter: self)
        var text: String?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { readURL in
            if let data = try? Data(contentsOf: readURL) {
                text = String(data: data, encoding: .utf8)
            }
        }
        guard let text else { return }
        onExternalChange(text)
    }
}

extension Notification.Name {
    static let markdownDocumentDidSave = Notification.Name("markdownDocumentDidSave")
}
