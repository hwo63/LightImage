import AppKit
import LightImageCore
import SwiftUI

protocol LocalizedView: View {
    var language: AppLanguage { get }
}

extension LocalizedView {
    func tr(_ message: InterfaceText) -> String { message.localized(language) }
}

enum AppSettings {
    static let checkAutomatically = "checkAutomatically"
    static let exportFormat = "exportFormat"
    static let exportQuality = "exportQuality"
    static let exportLongEdge = "exportLongEdge"
    static let revealExports = "revealExports"
}

struct SettingsView: LocalizedView {
    @AppStorage(AppLanguage.defaultsKey) var language = AppLanguage.vietnamese
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: AppUpdater
    @AppStorage(AppSettings.checkAutomatically) private var checkAutomatically = true
    @AppStorage(AppSettings.exportFormat) private var format = "jpg"
    @AppStorage(AppSettings.exportQuality) private var quality = 0.95
    @AppStorage(AppSettings.exportLongEdge) private var size = 0.0
    @AppStorage(AppSettings.revealExports) private var revealExports = true

    var body: some View {
        Form {
            Section(tr("Giao diện")) {
                Picker(tr("Ngôn ngữ"), selection: $language) {
                    Text(verbatim: "Tiếng Việt").tag(AppLanguage.vietnamese)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
            }
            Section(tr("Cập nhật")) {
                LabeledContent(tr("Phiên bản đang dùng"), value: LightImageVersion.displayName)
                Toggle(tr("Tự động kiểm tra cập nhật"), isOn: $checkAutomatically)
                    .help(tr("Kiểm tra khi mở LightImage và định kỳ trong lúc sử dụng. Bạn chọn lúc cài bản đã tải."))
                HStack(spacing: 10) {
                    Button(tr("Kiểm tra cập nhật…")) { updater.checkManually(showAlert: false) }
                        .disabled(updater.isChecking)
                    if updater.isChecking {
                        ProgressView().controlSize(.small).accessibilityLabel(tr("Đang kiểm tra cập nhật…"))
                    }
                }
                if let version = updater.readyVersion {
                    LabeledContent(tr("Đã tải bản \(version)")) {
                        Button("Restart to Update") { updater.restartToUpdate(model: model) }
                            .disabled(model.isExporting || model.isImporting)
                    }
                }
                if let result = updater.checkResult {
                    Text(result.detail.localized(language)).font(.callout).foregroundStyle(.secondary)
                    if result.offersReleasePage {
                        Link(tr("Mở GitHub Releases"), destination: UpdateClient.latest)
                    }
                }
            }
            Section(tr("Xuất ảnh mặc định")) {
                ExportOptions(format: $format, quality: $quality, size: $size)
                Toggle(tr("Hiện ảnh đã xuất trong Finder"), isOn: $revealExports)
            }
        }
        .formStyle(.grouped)
        .frame(width: 530, height: 490)
        .onChange(of: checkAutomatically) { _, enabled in updater.setAutomaticChecks(enabled) }
    }
}

struct ExportOptions: LocalizedView {
    @AppStorage(AppLanguage.defaultsKey) var language = AppLanguage.vietnamese
    @Binding var format: String
    @Binding var quality: Double
    @Binding var size: Double

    var body: some View {
        Picker(tr("Định dạng"), selection: $format) {
            Text("JPEG · 8-bit").tag("jpg")
            Text("PNG · 8-bit").tag("png")
            Text("TIFF · 16-bit").tag("tiff")
        }
        if format == "jpg" {
            LabeledContent(tr("Chất lượng")) {
                Slider(value: $quality, in: 0.1...1, step: 0.01)
                    .accessibilityLabel(tr("Chất lượng"))
                Text("\(Int((quality * 100).rounded()))%").monospacedDigit().frame(width: 40)
            }
        }
        Picker(tr("Cạnh dài tối đa"), selection: $size) {
            Text(tr("Độ phân giải gốc")).tag(0.0)
            Text("3840 px").tag(3840.0)
            Text("2560 px").tag(2560.0)
            Text("2048 px").tag(2048.0)
            Text("1080 px").tag(1080.0)
        }
    }
}
