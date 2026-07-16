import SwiftUI

@main
struct FolioApp: App {
    @State private var updateStore = UpdateStore()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .environment(updateStore)
                .task {
                    await updateStore.checkForUpdatesOnce()
                }
        }
        .defaultSize(width: 900, height: 988)
    }
}
