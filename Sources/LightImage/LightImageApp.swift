import SwiftUI
import AppKit
import LightImageCore

enum LightImageVersion {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    static let build = Bundle.main.object(forInfoDictionaryKey: "LightImageBuildStamp") as? String

    static var displayName: String {
        guard let version else { return "LightImage" }
        if let build { return "LightImage \(version) (build \(build))" }
        return "LightImage \(version)"
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var pendingURLs: [URL] = []
    let updater = AppUpdater()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if updater.restartRequested {
            guard let model, !model.isExporting, !model.isImporting else {
                updater.cancelRestart()
                return .terminateCancel
            }
            model.save(flush: true)
            guard model.saved else {
                updater.cancelRestart()
                return .terminateCancel
            }
            do {
                try updater.handOffInstallation()
                return .terminateNow
            } catch {
                updater.cancelRestart()
                model.error = tr("Không thể mở trình cập nhật LightImage. Bản hiện tại vẫn đang chạy.")
                return .terminateCancel
            }
        }
        if model?.isExporting == true {
            let alert = NSAlert(); alert.messageText = tr("Ảnh đang được xuất"); alert.informativeText = tr("Đợi xuất ảnh xong trước khi đóng LightImage."); alert.runModal(); return .terminateCancel
        }
        model?.save(flush: true)
        updater.cancelBackgroundCheck()
        return .terminateNow
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.importURLs(urls) } else { pendingURLs.append(contentsOf: urls) }
    }
}

@main struct LightImageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.vietnamese
    var body: some Scene {
        WindowGroup("LightImage") {
            ContentView().environmentObject(model).environmentObject(delegate.updater)
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1120, minHeight: 740)
                .onAppear {
                    if delegate.model == nil, ProcessInfo.processInfo.arguments.contains("--update-failed") {
                        model.status = "Không cài được bản cập nhật. LightImage đã mở lại bản trước."
                    }
                    delegate.model = model
                    if !delegate.pendingURLs.isEmpty {
                        model.importURLs(delegate.pendingURLs)
                        delegate.pendingURLs = []
                    }
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    delegate.updater.setAutomaticChecks(UserDefaults.standard.object(forKey: AppSettings.checkAutomatically) as? Bool ?? true)
                    if ProcessInfo.processInfo.arguments.contains("--demo"), model.catalog.photos.isEmpty { model.loadDemo() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1460, height: 940)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("Giới thiệu LightImage")) { showAbout() }
                Button(tr("Kiểm tra cập nhật…")) { delegate.updater.checkManually() }
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text(tr("Cài đặt…")) }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(tr("Nhập ảnh…")) { model.importPhotos() }.keyboardShortcut("o")
                Button(tr("Nhập preset Lightroom…")) { model.importPresets() }.keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button(tr("Xuất ảnh…")) { model.exportSheet = true }.keyboardShortcut("e").disabled(model.selected == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(tr("Hoàn tác")) { model.undo() }.keyboardShortcut("z").disabled(!model.canUndo)
                Button(tr("Làm lại")) { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            }
            CommandMenu(tr("Ảnh")) {
                Button(tr("Sao chép chỉnh sửa")) { model.copyBuffer = model.edits }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(model.selected == nil)
                Button(tr("Dán chỉnh sửa")) { model.pasteEdits() }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(model.copyBuffer == nil || model.selected == nil)
                Button(tr("Khôi phục ảnh gốc")) { model.reset() }.disabled(model.selected == nil)
                Divider()
                Button(tr("So sánh trước / sau")) { model.compare.toggle(); model.splitCompare = false }.keyboardShortcut("\\", modifiers: []).disabled(model.selected == nil)
                Button(tr("So sánh kéo vạch")) { model.splitCompare.toggle(); model.compare = false }
                    .keyboardShortcut("y", modifiers: [.shift]).disabled(model.selected == nil)
                Button(tr("Chỉnh theo vùng…")) { model.maskSheet = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(model.selected == nil)
                Button(tr("Tạo bản sao ảo")) { if let id = model.selectedID { model.makeVirtualCopy(id) } }
                    .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(model.selected == nil)
                Button(tr("Đánh dấu ảnh")) { model.toggleFlag() }.keyboardShortcut("p", modifiers: []).disabled(model.selected == nil)
                Button(tr("Ảnh trước")) { model.moveSelection(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command])
                Button(tr("Ảnh tiếp")) { model.moveSelection(1) }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Divider()
                ForEach(0..<6) { rating in
                    Button(rating == 0 ? tr("Bỏ đánh giá") : tr("\(rating) sao")) { model.setRating(rating) }.keyboardShortcut(KeyEquivalent(Character(String(rating))), modifiers: [.control])
                }
            }
            CommandGroup(replacing: .help) {
                Button(tr("Về tương thích preset Lightroom")) {
                    model.notice = tr("LightImage nhập .xmp và .lrtemplate. Các thông số ánh sáng, cân bằng trắng, HSL, đường cong RGB, trắng đen, độ nét, giảm nhiễu và vignette được mô phỏng bằng Core Image.\n\nKhông dùng bộ xử lý Adobe: màu không thể bảo đảm giống hệt Lightroom. Đã bổ sung calibration RGB, split toning/color grading, parametric curves, AutoTone theo histogram, dehaze, giảm nhiễu màu, sharpen radius/detail/masking và transform scale/X/Y.\n\nProfile/LUT Adobe, mask, healing, AI denoise, sửa quang sai, lens correction, grain và các mục chưa hỗ trợ sẽ được liệt kê khi nhập.\n\nRAW phụ thuộc camera và phiên bản macOS. Xuất JPEG/PNG 8-bit hoặc TIFF 16-bit, sRGB; không sao chép EXIF/GPS. Chỉnh sửa và preset được lưu cục bộ; ảnh gốc không bị sửa.")
                }
                Button(tr("Mở thư mục dữ liệu LightImage")) { NSWorkspace.shared.open(model.dataDirectory) }
            }
        }
        Settings {
            SettingsView().environmentObject(model).environmentObject(delegate.updater)
                .environment(\.locale, language.locale)
        }
    }

    private func tr(_ message: InterfaceText) -> String { message.localized(language) }

    private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3

        let credits = NSMutableAttributedString(
            string: tr("Miễn phí và mã nguồn mở\n"),
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .paragraphStyle: paragraph]
        )
        let bodyStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph
        ]
        credits.append(NSAttributedString(
            string: tr("Giấy phép MIT · "), attributes: bodyStyle
        ))
        let repository = URL(string: "https://github.com/hwo63/LightImage")!
        credits.append(NSAttributedString(
            string: tr("Xem mã nguồn trên GitHub"),
            attributes: bodyStyle.merging([.link: repository]) { _, link in link }
        ))
        credits.append(NSAttributedString(
            string: tr("\n\nỨng dụng chỉnh ảnh cho macOS hỗ trợ nhập và áp dụng trực tiếp preset Adobe Lightroom (.xmp và .lrtemplate)."),
            attributes: bodyStyle
        ))
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        if let build = LightImageVersion.build {
            options[.version] = "build \(build)"
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
