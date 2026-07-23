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

    init(text: String = "# New Document\n") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let savedText = text
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .markdownDocumentDidSave, object: nil, userInfo: ["text": savedText])
        }
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
