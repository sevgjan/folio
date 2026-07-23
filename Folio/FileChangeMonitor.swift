import Foundation

// Watches the open file for external edits (e.g. from VS Code) and reloads it into the document.
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
