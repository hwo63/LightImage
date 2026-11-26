import AppKit
import Darwin
import Foundation

private func swap(_ first: URL, _ second: URL) throws {
    let result = first.withUnsafeFileSystemRepresentation { left in
        second.withUnsafeFileSystemRepresentation { right in
            renameatx_np(AT_FDCWD, left, AT_FDCWD, right, UInt32(RENAME_SWAP))
        }
    }
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

@MainActor private func launch(_ app: URL, arguments: [String] = []) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = arguments
    configuration.createsNewApplicationInstance = true
    _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
}

@main struct LightImageInstaller {
    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, let pid = pid_t(arguments[1]), pid > 1,
              getppid() == pid || getppid() == 1 else { return }

        let app = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let downloaded = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let downloadDirectory = downloaded.deletingLastPathComponent()
        guard app.pathExtension == "app", downloaded.lastPathComponent == "LightImage.app",
              downloadDirectory.lastPathComponent.hasPrefix("LightImage-update-"),
              app.appendingPathComponent("Contents/MacOS/LightImageInstaller").resolvingSymlinksInPath().path ==
                URL(fileURLWithPath: arguments[0]).resolvingSymlinksInPath().path
        else { return }

        let manager = FileManager.default
        defer { try? manager.removeItem(at: downloadDirectory) }

        // Do not touch the installed bundle until the app has saved and exited.
        for _ in 0..<300 {
            if getppid() != pid { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard getppid() != pid else { return }

        let stage = app.deletingLastPathComponent().appendingPathComponent(".LightImage-install-\(UUID().uuidString)", isDirectory: true)
        let replacement = stage.appendingPathComponent(app.lastPathComponent, isDirectory: true)
        var keepBackup = false
        defer { if !keepBackup { try? manager.removeItem(at: stage) } }

        do {
            try manager.createDirectory(at: stage, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            try manager.copyItem(at: downloaded, to: replacement)
            try swap(app, replacement)
            do {
                try await launch(app)
            } catch {
                keepBackup = true
                try swap(app, replacement)
                keepBackup = false
                throw error
            }
        } catch {
            NSLog("LightImage update installation failed: %@", String(describing: error))
            if !keepBackup { try? await launch(app, arguments: ["--update-failed"]) }
        }
    }
}
