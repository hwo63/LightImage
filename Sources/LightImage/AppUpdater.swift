import AppKit
import OSLog

@MainActor final class AppUpdater: ObservableObject {
    @Published private(set) var readyVersion: String?

    private let logger = Logger(subsystem: "vn.hwo.LightImage", category: "updates")
    private var checkTask: Task<Void, Never>?
    private var update: DownloadedUpdate?
    private(set) var restartRequested = false

    func start() {
        guard checkTask == nil, let client = UpdateClient() else { return }
        checkTask = Task {
            while !Task.isCancelled {
                do {
                    if let next = try await client.downloadLatest(newerThan: update?.version) {
                        if Task.isCancelled || restartRequested {
                            try? FileManager.default.removeItem(at: next.directory)
                            return
                        }
                        if let update { try? FileManager.default.removeItem(at: update.directory) }
                        update = next
                        readyVersion = next.version.description
                    }
                } catch {
                    logger.notice("Không thể tải bản cập nhật: \(String(describing: error), privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func restartToUpdate(model: AppModel) {
        guard update != nil, !restartRequested, !model.isImporting, !model.isExporting else { return }
        let app = Bundle.main.bundleURL
        let parent = app.deletingLastPathComponent()
        guard app.pathExtension == "app", FileManager.default.isWritableFile(atPath: parent.path) else {
            model.error = "Hãy mở LightImage từ thư mục có quyền ghi, chẳng hạn Applications, rồi thử cập nhật lại."
            return
        }
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
               $0.bundleURL?.resolvingSymlinksInPath() == app.resolvingSymlinksInPath()
           }) {
            model.error = "Hãy đóng các phiên LightImage khác đang dùng cùng bản cài rồi thử cập nhật lại."
            return
        }
        restartRequested = true
        NSApp.terminate(nil)
    }

    func handOffInstallation() throws {
        guard let update, let installer = Bundle.main.url(forAuxiliaryExecutable: "LightImageInstaller") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = installer
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", Bundle.main.bundleURL.path, update.app.path]
        try process.run()
    }

    func cancelRestart() {
        restartRequested = false
    }

    func cancelBackgroundCheck() {
        checkTask?.cancel()
        if let update { try? FileManager.default.removeItem(at: update.directory) }
    }
}
