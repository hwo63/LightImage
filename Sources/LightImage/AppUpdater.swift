import AppKit
import OSLog

@MainActor final class AppUpdater: ObservableObject {
    struct CheckResult {
        let detail: String
        var offersReleasePage = false
    }

    @Published private(set) var readyVersion: String?
    @Published private(set) var isChecking = false
    @Published private(set) var checkResult: CheckResult?

    private let logger = Logger(subsystem: "vn.hwo.LightImage", category: "updates")
    private let client: UpdateClient?
    private var automaticChecks: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var reportCheck = false
    private var update: DownloadedUpdate?
    private(set) var restartRequested = false

    init(client: UpdateClient? = UpdateClient()) { self.client = client }

    func start() {
        guard automaticChecks == nil, client != nil else { return }
        automaticChecks = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                await self?.checkTask?.value
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func checkManually() {
        guard !restartRequested else { return }
        guard client != nil else {
            checkResult = CheckResult(detail: "Bản cài này thiếu thông tin xác minh cập nhật. Bạn có thể tải bộ cài chính thức từ GitHub.",
                                      offersReleasePage: true)
            return
        }
        reportCheck = true
        check()
    }

    func dismissCheckResult() { checkResult = nil }

    private func check() {
        guard checkTask == nil, !restartRequested, let client else { return }
        isChecking = true
        checkTask = Task {
            defer {
                reportCheck = false
                checkTask = nil
                isChecking = false
            }
            do {
                let next = try await client.downloadLatest(newerThan: update?.version)
                guard !Task.isCancelled, !restartRequested else {
                    if let next { try? FileManager.default.removeItem(at: next.directory) }
                    return
                }
                if let next {
                    if let update { try? FileManager.default.removeItem(at: update.directory) }
                    update = next
                    readyVersion = next.version.description
                }
                if reportCheck {
                    if let readyVersion {
                        checkResult = CheckResult(detail: "LightImage \(readyVersion) đã tải xong. Bấm Restart to Update ở góc dưới bên phải để cài đặt.")
                    } else {
                        checkResult = CheckResult(detail: "Bạn đang dùng bản LightImage mới nhất (\(client.installedVersion)).")
                    }
                }
            } catch {
                guard !Task.isCancelled, !restartRequested else { return }
                logger.notice("Không thể tải bản cập nhật: \(String(describing: error), privacy: .public)")
                if reportCheck {
                    checkResult = CheckResult(detail: "Không thể kiểm tra hoặc tải bản cập nhật. \(error.localizedDescription)",
                                              offersReleasePage: true)
                }
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
        automaticChecks?.cancel()
        checkTask?.cancel()
        if let update { try? FileManager.default.removeItem(at: update.directory) }
        update = nil
        readyVersion = nil
    }
}
