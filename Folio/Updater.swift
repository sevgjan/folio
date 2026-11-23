import Foundation
import AppKit
import Security

@MainActor
final class Updater: NSObject {
    private var downloadTask: URLSessionDownloadTask?
    private var onProgress: ((Double) -> Void)?
    private var onComplete: ((URL) -> Void)?
    private var onError: ((String) -> Void)?

    func download(
        url: URL,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (URL) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        downloadTask = task
        task.resume()
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    func install(mountPoint: URL) throws {
        let installed = Bundle.main.bundleURL
        let candidate = mountPoint.appendingPathComponent("Folio.app", isDirectory: true)
        try verify(candidate)
        let manager = FileManager.default
        let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                      appropriateFor: installed, create: true)
        let staged = staging.appendingPathComponent("Folio.app", isDirectory: true)
        do {
            try manager.copyItem(at: candidate, to: staged)
            try verify(staged)
            let script = #"""
            set -eu
            for tick in {1..60}; do
              if ! kill -0 "$1" 2>/dev/null; then break; fi
              sleep 1
            done
            if kill -0 "$1" 2>/dev/null; then exit 1; fi
            backup="$4/Previous Folio.app"
            /bin/mv "$2" "$backup"
            if /bin/mv "$3" "$2"; then
              if /usr/bin/open "$2"; then
                /bin/rm -rf "$backup"
              else
                /bin/mv "$2" "$3"
                /bin/mv "$backup" "$2"
                /usr/bin/open "$2" || true
              fi
            else
              /bin/mv "$backup" "$2"
              /usr/bin/open "$2" || true
            fi
            /usr/bin/hdiutil detach "$5" -quiet 2>/dev/null || true
            /bin/rmdir "$4" 2>/dev/null || true
            """#
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script, "folio-update", String(ProcessInfo.processInfo.processIdentifier),
                                 installed.path, staged.path, staging.path, mountPoint.path]
            try process.run()
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private func verify(_ app: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let condition = #"anchor apple generic and identifier "com.rr.folio" and certificate leaf[subject.OU] = "Q4FVJUH2ZJ" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(condition as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess
        else {
            throw NSError(domain: "FolioUpdate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The update does not have a valid Rolling Rabbits signature."])
        }
    }

}

extension Updater: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.onProgress?(progress)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FolioUpdate-" + UUID().uuidString)
        let dmgPath = directory.appendingPathComponent("Folio.dmg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: dmgPath)
        } catch {
            Task { @MainActor in self.onError?("Failed to save download: \(error.localizedDescription)") }
            return
        }

        let mountPoint = directory.appendingPathComponent("Mounted").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-readonly", dmgPath.path, "-nobrowse", "-quiet", "-mountpoint", mountPoint]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Task { @MainActor in self.onError?("Failed to mount update: \(error.localizedDescription)") }
            return
        }

        guard process.terminationStatus == 0 else {
            Task { @MainActor in self.onError?("Failed to mount disk image.") }
            return
        }

        let mountURL = URL(fileURLWithPath: mountPoint)
        Task { @MainActor in self.onComplete?(mountURL) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in self.onError?(error.localizedDescription) }
    }
}
