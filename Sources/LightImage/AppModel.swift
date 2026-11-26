import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreImage
import ImageIO
import LightImageCore

actor MaskGuideRenderer {
    private let engine = ImageEngine()

    func overlay(_ mask: LocalMask) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return try? engine.automaticMaskOverlay(mask)
    }

    func coverage(_ mask: LocalMask, imageSize: CGSize) throws -> CGImage {
        try Task.checkCancellation()
        return try engine.edgeBrushCoverage(mask, imageSize: imageSize)
    }

    func preview(source: CGImage, coverage: CGImage, stroke: LocalMask.BrushStroke,
                 sensitivity: Double, inverted: Bool) throws -> EdgeBrushPreview {
        try Task.checkCancellation()
        return try engine.edgeBrushPreview(in: source, coverage: coverage, stroke: stroke,
                                           sensitivity: sensitivity, inverted: inverted)
    }
}

struct EditStep: Identifiable {
    let id = UUID()
    let label: String
    let before: Adjustments
    let after: Adjustments
}

private final class PreviewCache: @unchecked Sendable {
    var path: String?
    var source: CIImage?
    var portraits: PortraitPreview?
    var analysisFailed = false
}

struct PortraitPreview {
    let source: NSImage
    let subjects: [PortraitSubject]
    let thumbnails: [NSImage?]
}

private struct MaskPreviewRequest: Sendable {
    let path: String
    let adjustments: Adjustments
    let session: UUID
}

@MainActor final class AppModel: ObservableObject {
    @Published var catalog = Catalog()
    @Published var selectedID: UUID?
    @Published var edits = Adjustments()
    @Published var preview: NSImage?
    @Published var original: NSImage?
    @Published var thumbnails: [UUID: NSImage] = [:]
    @Published var histogram: [[Double]] = []
    @Published var isRendering = false
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var status = "Sẵn sàng sáng tạo"
    @Published var error: String?
    @Published var notice: String?
    @Published var query = ""
    @Published var presetQuery = ""
    @Published var filter = "all"
    @Published var libraryMode = false
    @Published var compare = false
    @Published var splitCompare = false
    @Published private(set) var maskPreview: NSImage?
    @Published private(set) var maskPreviewError: String?
    private(set) var preferredMaskID: UUID?
    @Published var maskSheet = false {
        didSet {
            guard maskSheet != oldValue else { return }
            if maskSheet {
                renderWork?.cancel()
                generation = UUID()
                isRendering = false
            } else {
                preferredMaskID = nil
                resetMaskPreview()
            }
            scheduleRender(immediate: true)
        }
    }
    @Published var exportSheet = false
    @Published var selectedPreset: UUID?
    @Published var history: [UUID: [EditStep]] = [:]
    @Published var redoHistory: [UUID: [EditStep]] = [:]
    @Published private var maskStrokeRedo: [UUID: [UUID: [LocalMask.BrushStroke]]] = [:]
    @Published var sourceSize = ""
    @Published var saved = true
    @Published var presetStrength = 100.0
    @Published var copyBuffer: Adjustments?
    @Published private(set) var portraitInspectorOpen = false
    @Published private(set) var portraitPreview: PortraitPreview?
    @Published private(set) var portraitAnalysisFailed = false
    private var presetBase: Adjustments?
    private let essentials = PhotoPreset.builtins
    private let renderQueue = DispatchQueue(label: "vn.hwo.lightimage.render", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "vn.hwo.lightimage.io", qos: .userInitiated)
    private let maskQueue = DispatchQueue(label: "vn.hwo.lightimage.mask", qos: .userInitiated)
    private var renderWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var generation = UUID()
    private var maskPreviewSession = UUID()
    private var maskPreviewSource: CIImage?
    private var pendingMaskPreview: MaskPreviewRequest?
    private var isRenderingMaskPreview = false
    private var gestureStart: Adjustments?
    private let cache = PreviewCache()
    private let engine = ImageEngine()
    let dataDirectory: URL
    private var persistenceAvailable = true

    var selected: PhotoRecord? { catalog.photos.first { $0.id == selectedID } }
    var presets: [PhotoPreset] { essentials + catalog.presets }
    var visiblePresets: [PhotoPreset] { presets.filter { presetQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(presetQuery) } }
    var photos: [PhotoRecord] {
        catalog.photos.filter { photo in
            (query.isEmpty || photo.name.localizedCaseInsensitiveContains(query)) &&
            (filter != "flagged" || photo.flagged) && (filter != "rated" || photo.rating >= 4) && (filter != "edited" || photo.adjustments.isEdited)
        }
    }
    var currentHistory: [EditStep] { selectedID.flatMap { history[$0] } ?? [] }
    var canUndo: Bool { !currentHistory.isEmpty }
    var canRedo: Bool { !(selectedID.flatMap { redoHistory[$0] } ?? []).isEmpty }
    var activePreset: PhotoPreset? { presets.first { $0.id == selectedPreset } }
    var hairMask: LocalMask? { edits.localMasks?.first { $0.purpose == .hair } }
    var canEditHair: Bool {
        selectedID != nil && (hairMask != nil || (edits.localMasks?.count ?? 0) < LocalMask.maximumCount)
    }

    init(dataDirectory: URL? = nil) {
        if let dataDirectory {
            self.dataDirectory = dataDirectory
        } else if let override = ProcessInfo.processInfo.environment["LIGHTIMAGE_DATA_DIR"] {
            self.dataDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HWO.LightImage", isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(at: self.dataDirectory, withIntermediateDirectories: true)
            let file = self.dataDirectory.appendingPathComponent("catalog.json")
            if FileManager.default.fileExists(atPath: file.path) {
                catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: file))
                guard catalog.version == 1 else { throw LightImageError.exportFailed("Phiên bản thư viện không tương thích.") }
            }
        } catch {
            persistenceAvailable = false
            self.error = "Không mở được thư viện đã lưu. Tệp hiện tại được giữ nguyên; phiên này chưa thể tự lưu.\n\(error.localizedDescription)"
        }
        // Retain original preset data so future parser upgrades can recover newly supported controls.
        var upgraded = false
        for i in catalog.presets.indices {
            let previous = catalog.presets[i]
            if previous.parserVersion != PresetParser.version, let data = previous.sourceData,
               var preset = try? PresetParser.parse(data: data, filename: previous.source) {
                preset.id = previous.id; preset.sourcePath = previous.sourcePath
                catalog.presets[i] = preset; upgraded = true
            }
        }
        if upgraded { save() }
        if let first = catalog.photos.first { select(first.id) }
        createThumbnails(catalog.photos)
    }
    func select(_ id: UUID) {
        endGesture("Điều chỉnh")
        guard let photo = catalog.photos.first(where: { $0.id == id }) else { return }
        selectedID = id; edits = photo.adjustments; selectedPreset = nil; presetBase = nil
        preview = nil; original = nil; histogram = []; sourceSize = ""; compare = false; splitCompare = false
        resetMaskPreview()
        portraitPreview = nil; portraitAnalysisFailed = false
        scheduleRender(immediate: true)
    }

    func showPortraitInspector(_ open: Bool) {
        portraitInspectorOpen = open
        if open && portraitPreview == nil { scheduleRender(immediate: true) }
    }

    func selectPortrait(_ face: CGRect?) {
        guard edits.portraitFace != face else { return }
        change("Chọn người chỉnh chân dung") {
            $0.portraitFace = face
            $0.portraitWaist = nil
        }
    }

    func setPortraitWaist(_ waist: PortraitWaist?) {
        change(waist == nil ? "Dùng vị trí eo tự động" : "Đặt vị trí eo") {
            $0.portraitWaist = waist
        }
    }

    func editHair() {
        guard canEditHair else { return }
        if let hairMask {
            preferredMaskID = hairMask.id
        } else {
            var mask = LocalMask(kind: .brush)
            mask.purpose = .hair
            change("Thêm mặt nạ tóc") { $0.localMasks = ($0.localMasks ?? []) + [mask] }
            preferredMaskID = mask.id
        }
        maskSheet = true
    }

    func moveSelection(_ delta: Int) {
        guard !photos.isEmpty else { return }
        let index = photos.firstIndex { $0.id == selectedID } ?? 0
        select(photos[min(max(index + delta, 0), photos.count - 1)].id)
    }
    func importPhotos() {
        let panel = NSOpenPanel()
        panel.title = "Nhập ảnh hoặc thư mục ảnh"
        panel.prompt = "Nhập ảnh"
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder] + ImageEngine.rawExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        let presetURLs = urls.filter { ["xmp", "lrtemplate"].contains($0.pathExtension.lowercased()) }
        if !presetURLs.isEmpty { importPresetURLs(presetURLs) }
        let photoURLs = urls.filter { !presetURLs.contains($0) }
        guard !photoURLs.isEmpty else { return }
        isImporting = true; status = "Đang quét ảnh…"
        let existing = Set(catalog.photos.map(\.path))
        ioQueue.async { [weak self] in
            var files: [URL] = []
            for url in photoURLs {
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                    if let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let file as URL in contents where ImageEngine.extensions.contains(file.pathExtension.lowercased()) { files.append(file) }
                    }
                } else if ImageEngine.extensions.contains(url.pathExtension.lowercased()) { files.append(url) }
            }
            var seen = existing
            let new = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { url -> PhotoRecord? in
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard seen.insert(path).inserted else { return nil }; return PhotoRecord(path: path)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.catalog.photos.append(contentsOf: new)
                self.isImporting = false; self.status = "Đã nhập \(new.count) ảnh · giữ nguyên tệp gốc"
                if let first = new.first { self.filter = "all"; self.query = ""; self.select(first.id) }
                self.createThumbnails(new); self.save()
                if new.isEmpty { self.notice = "Không có ảnh mới để nhập. Ảnh trùng sẽ được bỏ qua; hỗ trợ JPEG, PNG, HEIC, TIFF và các tệp RAW do macOS giải mã." }
            }
        }
    }
    func importPresets() {
        let panel = NSOpenPanel(); panel.title = "Nhập preset Lightroom"; panel.prompt = "Nhập preset"
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "xmp") ?? .data, UTType(filenameExtension: "lrtemplate") ?? .data, .folder]
        panel.begin { [weak self] response in
            if response == .OK { self?.importPresetURLs(panel.urls) }
        }
    }
    func importPresetURLs(_ urls: [URL]) {
        ioQueue.async { [weak self] in
            var files: [URL] = []
            for url in urls {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for case let file as URL in enumerator where ["xmp", "lrtemplate"].contains(file.pathExtension.lowercased()) { files.append(file) }
                    }
                } else { files.append(url) }
            }
            var imported: [PhotoPreset] = [], failures: [String] = []
            for file in files {
                do { imported.append(try PresetParser.parse(url: file)) }
                catch { failures.append("\(file.lastPathComponent): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                var count = 0, updated = 0
                for preset in imported {
                    if self.catalog.mergePreset(preset) { count += 1 } else { updated += 1 }
                }
                self.save(); self.status = "Preset: \(count) mới · \(updated) cập nhật"
                let warnings = imported.filter { !$0.unsupported.isEmpty }.map { "• \($0.name): \($0.unsupported.joined(separator: ", "))" }
                var report = "Đã nhập \(count) preset mới và cập nhật \(updated) preset đã có.\n\nThông số được chuyển sang bộ xử lý LightImage, màu có thể khác Adobe Lightroom."
                if !warnings.isEmpty { report += "\n\nChưa hỗ trợ các mục sau:\n" + warnings.prefix(15).joined(separator: "\n") }
                if !failures.isEmpty { report += "\n\nTệp không đọc được:\n" + failures.prefix(10).joined(separator: "\n") }
                self.notice = report
            }
        }
    }
    func beginGesture() { if gestureStart == nil { gestureStart = edits } }
    func update(_ key: String, _ value: Double) {
        beginGesture(); edits[key] = value; commitCurrent(); scheduleRender()
    }
    func updateGeometry(_ keyPath: WritableKeyPath<Adjustments, Double>, _ value: Double) {
        beginGesture(); edits[keyPath: keyPath] = value; commitCurrent(); scheduleRender()
    }
    func modifyMask(_ id: UUID, label: String? = nil, _ update: (inout LocalMask) -> Void) {
        guard let index = edits.localMasks?.firstIndex(where: { $0.id == id }) else { return }
        if let label {
            change(label) { edits in
                if var mask = edits.localMasks?[index] {
                    update(&mask)
                    edits.localMasks?[index] = mask
                }
            }
        } else {
            beginGesture()
            if var mask = edits.localMasks?[index] {
                update(&mask)
                edits.localMasks?[index] = mask
            }
            commitCurrent()
            scheduleRender()
        }
    }

    func canRedoMaskStroke(_ maskID: UUID) -> Bool {
        guard let photoID = selectedID else { return false }
        return maskStrokeRedo[photoID]?[maskID]?.isEmpty == false
    }

    func undoMaskStroke(_ maskID: UUID) {
        guard let photoID = selectedID,
              let stroke = edits.localMasks?.first(where: { $0.id == maskID })?.strokes.last else { return }
        var pending = maskStrokeRedo[photoID]?[maskID] ?? []
        pending.append(stroke)
        modifyMask(maskID, label: "Hoàn tác nét cọ") { $0.strokes.removeLast() }
        maskStrokeRedo[photoID, default: [:]][maskID] = pending
    }

    func redoMaskStroke(_ maskID: UUID) {
        guard let photoID = selectedID, var pending = maskStrokeRedo[photoID]?[maskID],
              let stroke = pending.popLast() else { return }
        modifyMask(maskID, label: "Làm lại nét cọ") { $0.strokes.append(stroke) }
        if !pending.isEmpty { maskStrokeRedo[photoID, default: [:]][maskID] = pending }
    }

    private func invalidateMaskStrokeRedo(for photoID: UUID, from before: Adjustments, to after: Adjustments) {
        guard let pending = maskStrokeRedo[photoID], !pending.isEmpty else { return }
        for maskID in pending.keys {
            let previous = before.localMasks?.first { $0.id == maskID }
            let current = after.localMasks?.first { $0.id == maskID }
            if previous?.strokes != current?.strokes { maskStrokeRedo[photoID]?.removeValue(forKey: maskID) }
        }
    }

    func detectMask(_ kind: LocalMask.Kind, for photo: PhotoRecord) async throws -> Data {
        // Subject and background share the same foreground bitmap.
        if kind != .sky, let data = edits.localMasks?.first(where: {
            $0.kind == .subject || $0.kind == .background
        })?.automaticPNG { return data }
        let previewSource = selectedID == photo.id && selected?.path == photo.path ? maskPreviewSource : nil
        return try await withCheckedThrowingContinuation { continuation in
            maskQueue.async { [engine] in
                continuation.resume(with: Result {
                    let source = try previewSource ?? engine.load(url: URL(fileURLWithPath: photo.path), maxDimension: 1200)
                    return try engine.detectMask(kind, in: source)
                })
            }
        }
    }
    func selectBrushEdges(_ stroke: LocalMask.BrushStroke, sensitivity: Double) async throws -> BrushEdgeSelection {
        guard let image = maskPreview?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw LightImageError.exportFailed("Thiếu ảnh xem trước để bám viền.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            maskQueue.async {
                continuation.resume(with: Result {
                    try BrushEdgeSelection.detect(in: image, stroke: stroke, sensitivity: sensitivity)
                })
            }
        }
    }
    func endGesture(_ label: String) {
        if let before = gestureStart { record(label, before: before) }; gestureStart = nil
    }
    func change(_ label: String, _ block: (inout Adjustments) -> Void) {
        endGesture("Điều chỉnh")
        let before = edits; block(&edits); record(label, before: before); commitCurrent(); scheduleRender()
    }
    func record(_ label: String, before: Adjustments) {
        guard let id = selectedID, before != edits else { return }
        invalidateMaskStrokeRedo(for: id, from: before, to: edits)
        history[id, default: []].append(EditStep(label: label, before: before, after: edits))
        if history[id, default: []].count > 100 { history[id]?.removeFirst() }
        redoHistory[id] = []
    }
    func commitCurrent() {
        guard let i = catalog.photos.firstIndex(where: { $0.id == selectedID }) else { return }
        catalog.photos[i].adjustments = edits; save()
    }
    func apply(_ preset: PhotoPreset) {
        guard selected != nil else { return }
        guard preset.supportedCount > 0 else {
            status = "Không áp dụng được \(preset.name) · Không có thông số được hỗ trợ"
            return
        }
        presetBase = edits; presetStrength = 100; selectedPreset = preset.id
        change(preset.name) { $0.apply(preset) }
        status = "Đã áp dụng \(preset.name)"
    }
    func updatePresetStrength(_ value: Double) {
        guard let preset = activePreset, let base = presetBase else { return }
        beginGesture(); presetStrength = value
        let current = edits
        edits = base; edits.apply(preset, amount: value / 100)
        edits.keepPortrait(from: current)
        edits.localMasks = current.localMasks
        edits.flipHorizontal = current.flipHorizontal
        edits.flipVertical = current.flipVertical
        edits.values["LightImageStraighten"] = current.values["LightImageStraighten"]
        commitCurrent(); scheduleRender()
    }
    func reset() { change("Khôi phục ảnh gốc") { $0 = Adjustments() }; selectedPreset = nil; presetBase = nil }
    func undo() {
        endGesture("Điều chỉnh")
        guard let id = selectedID, let step = history[id]?.popLast() else { return }
        invalidateMaskStrokeRedo(for: id, from: edits, to: step.before)
        redoHistory[id, default: []].append(step); edits = step.before; selectedPreset = nil; commitCurrent(); scheduleRender()
    }
    func redo() {
        guard let id = selectedID, let step = redoHistory[id]?.popLast() else { return }
        invalidateMaskStrokeRedo(for: id, from: edits, to: step.after)
        history[id, default: []].append(step); edits = step.after; selectedPreset = nil; commitCurrent(); scheduleRender()
    }
    func setRating(_ value: Int) {
        guard let index = catalog.photos.firstIndex(where: { $0.id == selectedID }) else { return }
        catalog.photos[index].rating = value; save()
    }
    func toggleFlag() {
        guard let index = catalog.photos.firstIndex(where: { $0.id == selectedID }) else { return }
        catalog.photos[index].flagged.toggle(); save()
    }
    func pasteEdits() {
        if let copyBuffer {
            change("Dán chỉnh sửa") {
                let current = $0
                $0 = copyBuffer
                $0.keepPortrait(from: current)
                $0.localMasks = current.localMasks
            }
        }
    }
    func syncVisible() {
        let snapshot = edits
        for photo in photos where photo.id != selectedID {
            if let i = catalog.photos.firstIndex(where: { $0.id == photo.id }) {
                let before = catalog.photos[i].adjustments
                var after = snapshot
                after.keepPortrait(from: before)
                after.localMasks = before.localMasks
                catalog.photos[i].adjustments = after
                history[photo.id, default: []].append(EditStep(label: "Đồng bộ chỉnh sửa", before: before, after: after))
                redoHistory[photo.id] = []
            }
        }
        createThumbnails(photos)
        save(); status = "Đã đồng bộ chỉnh sửa cho \(photos.count) ảnh đang lọc"
    }
    func savePreset(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var settings = edits
        settings.keepPortrait(from: Adjustments())
        settings.localMasks = nil
        settings.values.removeValue(forKey: "LightImageStraighten")
        catalog.presets.append(PhotoPreset(name: name, group: "Preset của tôi", settings: settings, monochrome: edits.monochrome))
        save(); status = "Đã lưu preset \(name)"
    }
    func makeVirtualCopy(_ id: UUID) {
        endGesture("Điều chỉnh")
        guard let index = catalog.photos.firstIndex(where: { $0.id == id }) else { return }
        let source = catalog.photos[index]
        let number = (catalog.photos.filter { $0.path == source.path }.compactMap(\.copyNumber).max() ?? 0) + 1
        var copy = PhotoRecord(path: source.path)
        copy.copyNumber = number
        copy.adjustments = source.adjustments
        copy.rating = source.rating
        copy.flagged = source.flagged
        catalog.photos.insert(copy, at: index + 1)
        thumbnails[copy.id] = thumbnails[id]
        select(copy.id)
        save()
        status = "Đã tạo bản sao ảo"
    }
    func deletePreset(_ id: UUID) { catalog.presets.removeAll { $0.id == id }; save() }
    func removeSelected() {
        guard let selectedID else { return }
        catalog.photos.removeAll { $0.id == selectedID }; thumbnails[selectedID] = nil
        self.selectedID = nil; preview = nil; original = nil; edits = Adjustments(); generation = UUID()
        resetMaskPreview()
        portraitPreview = nil; portraitAnalysisFailed = false
        isRendering = false; histogram = []; sourceSize = ""; history[selectedID] = nil; redoHistory[selectedID] = nil
        maskStrokeRedo[selectedID] = nil
        if let first = photos.first { select(first.id) }; save()
    }
    func relink() {
        guard let selectedID else { return }
        let panel = NSOpenPanel(); panel.title = "Chọn lại vị trí ảnh gốc"
        if panel.runModal() == .OK, let url = panel.url, let i = catalog.photos.firstIndex(where: { $0.id == selectedID }) {
            let oldPath = catalog.photos[i].path
            for index in catalog.photos.indices where catalog.photos[index].path == oldPath {
                catalog.photos[index].path = url.path
            }
            save(); select(selectedID); createThumbnails(catalog.photos.filter { $0.path == url.path })
        }
    }
    func save(flush: Bool = false) {
        guard persistenceAvailable else { return }
        saved = false; saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONEncoder().encode(self.catalog)
                try data.write(to: self.dataDirectory.appendingPathComponent("catalog.json"), options: .atomic)
                self.saved = true
            } catch { self.error = "Không lưu được thư viện: \(error.localizedDescription)" }
        }
        saveWork = work
        if flush { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work) }
    }
    func scheduleRender(immediate: Bool = false) {
        guard let selected else { return }
        if maskSheet {
            pendingMaskPreview = MaskPreviewRequest(path: selected.path, adjustments: edits, session: maskPreviewSession)
            renderNextMaskPreview()
            return
        }
        renderWork?.cancel(); let ticket = UUID(); generation = ticket
        let path = selected.path, snapshot = edits, showPortraits = portraitInspectorOpen
        isRendering = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let source = try self.previewSource(at: path)
                if showPortraits, self.cache.portraits == nil {
                    let analysis = try? self.engine.analyzePortrait(source)
                    let subjects = analysis?.subjects ?? []
                    self.cache.analysisFailed = analysis == nil
                    let cg = try self.engine.cgImage(source)
                    let thumbnails = subjects.map { subject -> NSImage? in
                        let rect = subject.face
                        let pixels = CGRect(x: rect.minX * CGFloat(cg.width), y: (1 - rect.maxY) * CGFloat(cg.height),
                                            width: rect.width * CGFloat(cg.width), height: rect.height * CGFloat(cg.height)).integral
                        guard let face = cg.cropping(to: pixels) else { return nil }
                        return NSImage(cgImage: face, size: .zero)
                    }
                    self.cache.portraits = PortraitPreview(source: NSImage(cgImage: cg, size: .zero),
                                                          subjects: subjects, thumbnails: thumbnails)
                }
                let portraits = self.cache.portraits
                let analysisFailed = self.cache.analysisFailed
                let rendered = try self.engine.render(source, adjustments: snapshot)
                let cg = try self.engine.cgImage(rendered)
                let thumbnail = try self.engine.cgImage(self.engine.resized(rendered, maxDimension: 280))
                let before = try self.engine.cgImage(self.engine.geometry(source, adjustments: snapshot))
                let histogram = self.engine.histogram(cg)
                var dimensions = "\(Int(source.extent.width)) × \(Int(source.extent.height))"
                if let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
                   let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int { dimensions = "\(w) × \(h)" }
                DispatchQueue.main.async {
                    guard self.generation == ticket else { return }
                    self.preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    self.original = NSImage(cgImage: before, size: NSSize(width: before.width, height: before.height))
                    self.histogram = histogram; self.sourceSize = dimensions; self.isRendering = false
                    if showPortraits {
                        self.portraitPreview = portraits
                        self.portraitAnalysisFailed = analysisFailed
                    }
                    self.thumbnails[selected.id] = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == ticket else { return }
                    self.isRendering = false; self.error = error.localizedDescription
                }
            }
        }
        renderWork = work
        renderQueue.asyncAfter(deadline: .now() + (immediate ? 0 : 0.12), execute: work)
    }

    private func resetMaskPreview() {
        maskPreviewSession = UUID()
        pendingMaskPreview = nil
        maskPreviewSource = nil
        maskPreview = nil
        maskPreviewError = nil
    }

    private func renderNextMaskPreview() {
        guard !isRenderingMaskPreview, let request = pendingMaskPreview else { return }
        pendingMaskPreview = nil
        isRenderingMaskPreview = true
        renderQueue.async { [weak self] in
            guard let self else { return }
            let result = Result {
                let source = try self.previewSource(at: request.path)
                let image = try self.engine.render(source, adjustments: request.adjustments, unframed: true)
                return (source, try self.engine.cgImage(image))
            }
            DispatchQueue.main.async {
                self.isRenderingMaskPreview = false
                if self.maskPreviewSession == request.session {
                    // Publish completed frames during a drag while keeping only the latest queued edit.
                    switch result {
                    case let .success((source, image)):
                        self.maskPreviewSource = source
                        self.maskPreview = NSImage(cgImage: image, size: .zero)
                        self.maskPreviewError = nil
                    case let .failure(error):
                        self.maskPreviewError = error.localizedDescription
                    }
                }
                self.renderNextMaskPreview()
            }
        }
    }

    // Accessed on renderQueue by both preview paths.
    private nonisolated func previewSource(at path: String) throws -> CIImage {
        if cache.path == path, let source = cache.source { return source }
        let source = try engine.load(url: URL(fileURLWithPath: path), maxDimension: 2400)
        cache.source = source
        cache.path = path
        cache.portraits = nil
        cache.analysisFailed = false
        return source
    }

    private func createThumbnails(_ photos: [PhotoRecord]) {
        ioQueue.async { [weak self] in
            let renderer = ImageEngine()
            for photo in photos {
                autoreleasepool {
                    let size: CGFloat = photo.adjustments.hasPortraitEdits ? 2400 : 280
                    guard let image = try? renderer.load(url: URL(fileURLWithPath: photo.path), maxDimension: size),
                          let rendered = try? renderer.render(image, adjustments: photo.adjustments),
                          let cg = try? renderer.cgImage(renderer.resized(rendered, maxDimension: 280)) else { return }
                    DispatchQueue.main.async {
                        guard let self, self.catalog.photos.first(where: { $0.id == photo.id })?.adjustments == photo.adjustments else { return }
                        self.thumbnails[photo.id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    }
                }
            }
        }
    }
    func export(format: String, quality: Double, maxDimension: Double, all: Bool) {
        let targets = all ? photos : selected.map { [$0] } ?? []
        guard !targets.isEmpty else { return }
        var jobs: [(PhotoRecord, URL)] = []
        if all {
            let panel = NSOpenPanel(); panel.title = "Chọn thư mục xuất \(targets.count) ảnh"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            var reserved = Set<String>()
            for photo in targets {
                let stem = (photo.name as NSString).deletingPathExtension + "-edited"
                var destination = directory.appendingPathComponent(stem).appendingPathExtension(format), suffix = 1
                while FileManager.default.fileExists(atPath: destination.path) || reserved.contains(destination.path) {
                    destination = directory.appendingPathComponent("\(stem)-\(suffix)").appendingPathExtension(format); suffix += 1
                }
                reserved.insert(destination.path); jobs.append((photo, destination))
            }
        } else {
            let panel = NSSavePanel(); panel.title = "Xuất ảnh"; panel.nameFieldStringValue = (targets[0].name as NSString).deletingPathExtension + "-edited.\(format)"
            panel.allowedContentTypes = [format == "png" ? .png : format == "tiff" ? .tiff : .jpeg]; panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            if catalog.photos.contains(where: { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath() == destination.resolvingSymlinksInPath() }) {
                error = "Hãy chọn tên tệp khác để giữ nguyên ảnh gốc trong thư viện."; return
            }
            jobs = [(targets[0], destination)]
        }
        exportSheet = false; isExporting = true
        let exportJobs = jobs
        ioQueue.async { [weak self] in
            let renderer = ImageEngine(); var failures: [String] = []; var succeeded: [URL] = []
            for (index, job) in exportJobs.enumerated() {
                DispatchQueue.main.async { self?.status = "Đang xuất \(index + 1)/\(exportJobs.count)…" }
                autoreleasepool {
                    do {
                        try renderer.export(url: URL(fileURLWithPath: job.0.path), adjustments: job.0.adjustments, destination: job.1, format: format, quality: quality, maxDimension: maxDimension > 0 ? maxDimension : nil)
                        succeeded.append(job.1)
                    } catch { failures.append("\(job.0.name): \(error.localizedDescription)") }
                }
            }
            let exported = succeeded, errors = failures
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExporting = false; self.status = "Đã xuất \(exported.count) ảnh"
                if !errors.isEmpty { self.error = errors.joined(separator: "\n") }
                if !exported.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(exported) }
            }
        }
    }
    func loadDemo() {
        do {
            let url = dataDirectory.appendingPathComponent("LightImage - Alpine morning.jpg")
            if !FileManager.default.fileExists(atPath: url.path) { try DemoImage.write(to: url) }
            if let photo = catalog.photos.first(where: { $0.path == url.path }) { select(photo.id) }
            else { importURLs([url]) }
        } catch { self.error = error.localizedDescription }
    }
}
