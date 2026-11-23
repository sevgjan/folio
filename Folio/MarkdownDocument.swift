import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdown: UTType {
        UTType(importedAs: "net.daringfireball.markdown")
    }
}

struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]

    var text: String
    let revision: MarkdownDiskRevision

    init(text: String = "# New Document\n") {
        self.text = text
        revision = MarkdownDiskRevision()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        revision = MarkdownDiskRevision(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        try revision.prepareWrite(data, existing: configuration.existingFile?.regularFileContents)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// A document-scoped record shared between value copies held by DocumentGroup.
final class MarkdownDiskRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var baseline: Data?
    private var pendingWrites: [Data] = []
    private var conflict: Data?

    init(_ data: Data? = nil) { baseline = data }

    func knows(_ text: String) -> Bool {
        let data = Data(text.utf8)
        return lock.withLock { data == baseline || pendingWrites.contains(data) }
    }

    func accept(_ text: String) {
        let data = Data(text.utf8)
        lock.withLock {
            baseline = data
            conflict = nil
            if let index = pendingWrites.firstIndex(of: data) {
                pendingWrites.removeSubrange(...index)
            } else {
                pendingWrites.removeAll()
            }
        }
    }

    func recordConflict(_ text: String) {
        lock.withLock { conflict = Data(text.utf8) }
    }

    func prepareWrite(_ data: Data, existing: Data?) throws {
        try lock.withLock {
            if let existing {
                let unexpected = baseline != nil && existing != baseline && !pendingWrites.contains(existing)
                if conflict != nil || (unexpected && existing != data) {
                    throw CocoaError(.fileWriteUnknown, userInfo: [
                        NSLocalizedDescriptionKey: "The file changed on disk. Save a local copy or reload the disk version."
                    ])
                }
            }
            if !pendingWrites.contains(data) {
                pendingWrites.append(data)
                if pendingWrites.count > 8 { pendingWrites.removeFirst() }
            }
        }
    }
}
