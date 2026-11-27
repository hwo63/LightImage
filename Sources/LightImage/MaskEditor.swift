import SwiftUI
import LightImageCore

struct MaskEditor: LocalizedView {
    @AppStorage(AppLanguage.defaultsKey) var language = AppLanguage.vietnamese
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var showGuide = true
    @State private var erase = false
    @State private var radius = 4.0
    @State private var correctionRadius = 1.5
    @State private var paintBrush = BrushSettings()
    @State private var eraseBrush = BrushSettings()
    @State private var drag: [CGPoint] = []
    private enum CanvasMode {
        case edit, pan
    }

    private enum CanvasDrag {
        case edit(MaskViewport)
        case pan(MaskViewport)
        case ignored
    }

    @State private var canvasMode = CanvasMode.edit
    @State private var spaceHeld = false
    @State private var canvasDrag: CanvasDrag?
    @GestureState private var dragActive = false

    private var effectiveMode: CanvasMode { spaceHeld ? .pan : canvasMode }
    private var showsBrush: Bool {
        if case .edit = canvasDrag { return true }
        return canvasDrag == nil && effectiveMode == .edit
    }
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var pinchActive = false
    @State private var pinchStart: MaskViewport?
    @State private var pointer: CGPoint?
    @State private var draggingSlider = false
    @State private var adjustingEffect = false
    @State private var detecting: LocalMask.Kind?
    @State private var detectionMessage: String?
    @State private var detectionTask: Task<Void, Never>?
    @State private var automaticGuide: NSImage?
    @State private var guideRequest: GuideRequest?
    @State private var edgeTask: Task<Void, Never>?
    @State private var edgeMessage: String?
    @State private var guideRenderer = MaskGuideRenderer()
    @State private var hoverCoverage: HoverCoverage?
    @State private var hoverPreview: HoverResult?
    @State private var latestPreviewRequest: HoverRequest?
    @State private var previewTask: Task<Void, Never>?
    @State private var edgeDragID: UUID?

    private struct BrushSettings {
        var softness = 45.0
        var strength = 100.0
        var followsEdges = false
        var edgeSensitivity = 50.0
    }

    private struct GuideRequest: Equatable {
        let id: UUID
        let feather: Double
        let inverted: Bool
        let strokes: [LocalMask.BrushStroke]
    }

    private struct HoverCoverage {
        let key: HoverCoverageKey
        let source: NSImage
        let raster: CGImage
        let image: CGImage
    }

    private struct HoverCoverageKey: Equatable {
        let guide: GuideRequest
        let source: ObjectIdentifier
    }

    private struct HoverRequest: Equatable {
        let context: PreviewContext
        let stroke: LocalMask.BrushStroke
    }

    private struct PreviewContext: Equatable {
        let coverage: HoverCoverageKey
        let dragID: UUID?
        let sensitivity: Double
        let radius: Double
        let softness: Double
        let strength: Double
        let erases: Bool
    }

    private struct HoverResult {
        let request: HoverRequest
        let preview: EdgeBrushPreview
        let image: NSImage
    }

    private var requestedGuide: GuideRequest? {
        guard showGuide, let active, active.kind.isAutomatic else { return nil }
        return guide(for: active)
    }

    private func guide(for mask: LocalMask) -> GuideRequest {
        GuideRequest(id: mask.id, feather: mask.feather, inverted: mask.inverted, strokes: mask.strokes)
    }

    private var currentBrush: BrushSettings { erase ? eraseBrush : paintBrush }
    private var hoverGuide: GuideRequest? {
        guard let active, active.kind.isAutomatic, currentBrush.followsEdges else { return nil }
        return guide(for: active)
    }

    private var masks: [LocalMask] { model.edits.localMasks ?? [] }
    private var active: LocalMask? { masks.first { $0.id == selection } }
    private var canChangeStrokeHistory: Bool { edgeTask == nil && canvasDrag == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(tr("Chỉnh theo vùng"), systemImage: "circle.lefthalf.filled").font(.headline)
                Spacer()
                Toggle(tr("Hiện vùng chọn"), isOn: $showGuide).toggleStyle(.checkbox)
                    .help(tr("Tắt lớp phủ để xem màu ảnh sau khi chỉnh."))
                Button("Xong") { dismiss() }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(edgeTask != nil)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    if let image = model.maskPreview {
                        GeometryReader { proxy in
                            let viewport = MaskViewport(viewport: proxy.size, image: image.size, zoom: zoom, offset: offset)
                            canvas(image, viewport: viewport, size: proxy.size)
                        }
                        zoomControls
                    } else if model.maskPreviewError == nil {
                        ProgressView(tr("Đang mở ảnh…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let error = model.maskPreviewError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, maxHeight: model.maskPreview == nil ? .infinity : nil)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Menu {
                                Section(tr("Tự động")) {
                                    ForEach(LocalMask.Kind.allCases.filter(\.isAutomatic), id: \.self) { kind in
                                        Button(title(kind)) { add(kind) }
                                    }
                                }
                                Section(tr("Thủ công")) {
                                    ForEach(LocalMask.Kind.allCases.filter { !$0.isAutomatic }, id: \.self) { kind in
                                        Button(title(kind)) { add(kind) }
                                    }
                                }
                            } label: { Label(tr("Thêm mặt nạ"), systemImage: "plus") }
                            .menuStyle(.borderlessButton)
                            .disabled(masks.count >= LocalMask.maximumCount || detecting != nil || model.maskPreview == nil)
                            Spacer()
                        }
                        if let detecting {
                            ProgressView(tr("Đang nhận diện \(title(detecting).lowercased())…"))
                                .controlSize(.small).font(.system(size: 11))
                        }
                        if let detectionMessage {
                            Label(detectionMessage, systemImage: "info.circle")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let edgeMessage {
                            Text(edgeMessage).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        ForEach(Array(masks.enumerated()), id: \.element.id) { index, mask in
                            Button {
                                selection = mask.id; drag = []; erase = false
                            } label: {
                                HStack {
                                    Image(systemName: mask.enabled ? "circle.fill" : "circle")
                                        .font(.system(size: 7)).foregroundStyle(Theme.accent)
                                    Text("\(index + 1). \(mask.purpose == .hair ? tr("Tóc") : title(mask.kind))")
                                    Spacer()
                                    if selection == mask.id { Image(systemName: "checkmark") }
                                }
                                .padding(8)
                                .background(selection == mask.id ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        if let active { controls(active) }
                        else {
                            Text(tr("Chọn vùng tự động hoặc vẽ mặt nạ trên ảnh."))
                                .foregroundStyle(Theme.muted).font(.system(size: 11))
                        }
                    }.padding(.trailing, 5)
                }.frame(width: 222)
            }
            HStack(spacing: 12) {
                if hoverGuide != nil {
                    Label(erase ? tr("Cam: vùng sẽ tẩy") : tr("Xanh: vùng sẽ tô"),
                          systemImage: "circle.fill")
                        .foregroundStyle(erase ? .orange : .mint)
                        .help(tr("Rê cọ để xem vùng sẽ thay đổi tại vị trí hiện tại."))
                } else if let active {
                    Text(active.purpose == .hair ? tr("Tô lên tóc rồi dùng các thanh chỉnh màu bên phải.") : instruction(active.kind))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if active?.kind.supportsBrush == true {
                    Text(tr("Esc để hủy nét đang kéo")).fixedSize()
                }
                Label(spaceHeld ? tr("Đang kéo tạm") : tr("Giữ Space để kéo"), systemImage: "hand.draw")
                    .foregroundStyle(spaceHeld ? Theme.accent : Theme.muted)
                    .fixedSize()
            }.font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(20).frame(width: 940, height: 610)
        .background(Theme.panel)
        .background(MaskEditorKeys(spaceHeld: $spaceHeld, cancelBrushStroke: cancelBrushStroke,
                                   changeStrokeHistory: changeStrokeHistory)
            .frame(width: 0, height: 0))
        .onAppear { selection = model.preferredMaskID ?? masks.first?.id }
        .onChange(of: masks.map(\.id)) { _, ids in
            if selection.map({ !ids.contains($0) }) ?? true { selection = ids.last }
        }
        .task(id: requestedGuide) {
            guard let request = requestedGuide, let active else {
                automaticGuide = nil
                guideRequest = nil
                return
            }
            let image = await guideRenderer.overlay(active)
            guard !Task.isCancelled else { return }
            automaticGuide = image.map { NSImage(cgImage: $0, size: .zero) }
            guideRequest = request
        }
        .onDisappear {
            detectionTask?.cancel()
            edgeTask?.cancel()
            previewTask?.cancel()
            model.endGesture(tr("Chỉnh mặt nạ"))
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Picker(tr("Công cụ trên ảnh"), selection: $canvasMode) {
                Label(tr("Chỉnh vùng"), systemImage: "paintbrush").tag(CanvasMode.edit)
                Label(tr("Kéo ảnh"), systemImage: "hand.draw").tag(CanvasMode.pan)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .onChange(of: canvasMode) { _, _ in
                discardCanvasDrag()
            }

            Spacer()
            Button { zoomBy(1 / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= 1).accessibilityLabel(tr("Thu nhỏ"))
            Slider(value: Binding(get: { log2(zoom) }, set: { zoom = pow(2, $0) }), in: 0...3)
                .frame(width: 104).controlSize(.small)
                .accessibilityLabel(tr("Mức phóng to ảnh"))
                .accessibilityValue(tr("\(Int((zoom * 100).rounded()))% so với vừa khung"))
            Button { zoomBy(1.4) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom >= 8).accessibilityLabel(tr("Phóng to"))
            Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(width: 45, alignment: .trailing)
                .help(tr("Mức phóng so với vừa khung"))
            Button(tr("Vừa khung")) {
                zoom = 1
                offset = .zero
            }.disabled(zoom <= 1)
        }.font(.system(size: 11)).padding(.horizontal, 4)
    }

    private func zoomBy(_ factor: Double) {
        zoom = min(max(1, zoom * factor), 8)
    }

    private func canvas(_ image: NSImage, viewport: MaskViewport, size: CGSize) -> some View {
        let rect = viewport.frame
        let coverageKey = hoverGuide.map { HoverCoverageKey(guide: $0, source: ObjectIdentifier(image)) }
        let request = hoverRequest(coverageKey: coverageKey, viewport: viewport)
        return ZStack(alignment: .topLeading) {
            Theme.background
            Image(nsImage: image).resizable().interpolation(.high)
                .accessibilityLabel(tr("Ảnh xem trước khi chỉnh theo vùng"))
                .frame(width: rect.width, height: rect.height)
                .overlay { maskGuide(size: rect.size) }
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)

            if let request, let hoverPreview,
               hoverPreview.request == request ||
                (request.context.dragID != nil && hoverPreview.request.context == request.context) {
                let bounds = hoverPreview.preview.bounds
                Image(nsImage: hoverPreview.image).resizable().interpolation(.high)
                    .frame(width: bounds.width * rect.width, height: bounds.height * rect.height)
                    .position(x: rect.minX + bounds.midX * rect.width,
                              y: rect.minY + (1 - bounds.midY) * rect.height)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }

            if showsBrush, let active, active.kind.supportsBrush,
               let point = pointer, rect.contains(point) {
                let brushRadius = active.kind.isAutomatic ? correctionRadius : radius
                let diameter = brushRadius / 50 * max(rect.width, rect.height)
                Circle().strokeBorder(.black.opacity(0.8), lineWidth: 3)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                    .frame(width: diameter, height: diameter)
                    .position(point).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): pointer = point
            case .ended: pointer = nil
            }
        }
        .task(id: coverageKey) {
            guard let key = coverageKey else {
                hoverCoverage = nil
                hoverPreview = nil
                return
            }
            guard let active, hoverCoverage?.key != key,
                  let raster = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let coverage = try? await guideRenderer.coverage(active, imageSize: CGSize(width: raster.width, height: raster.height)),
                  !Task.isCancelled else { return }
            hoverCoverage = HoverCoverage(key: key, source: image, raster: raster, image: coverage)
        }
        .onChange(of: request, initial: true) { _, request in
            queuePreview(request)
        }
        .gesture(DragGesture(minimumDistance: 0)
            .updating($dragActive) { _, state, _ in state = true }
            .onChanged { event in
                guard !pinchActive else { return }
                // Keep the tool chosen at mouse-down until mouse-up. Releasing
                // Space during a pan must never turn its tail into a brush stroke.
                if canvasDrag == nil {
                    if effectiveMode == .pan { canvasDrag = .pan(viewport) }
                    else if edgeTask == nil, rect.contains(event.startLocation) {
                        canvasDrag = .edit(viewport)
                        if hoverGuide != nil { edgeDragID = UUID() }
                    }
                    else { canvasDrag = .ignored }
                }
                switch canvasDrag {
                case .pan(let start):
                    offset = start.panned(by: event.translation).offset
                case .edit(let start):
                    pointer = event.location
                    track(event, viewport: start)
                case .ignored, nil:
                    break
                }
            }
            .onEnded { event in
                defer { clearCanvasDrag() }
                if !pinchActive, case .edit(let start) = canvasDrag {
                    finish(event, viewport: start)
                }
            })
        .onChange(of: dragActive) { _, dragging in
            if !dragging { clearCanvasDrag() }
        }
        .simultaneousGesture(MagnifyGesture()
            .updating($pinchActive) { _, state, _ in state = true }
            .onChanged { event in
                discardCanvasDrag()
                if pinchStart == nil { pinchStart = viewport }
                guard let start = pinchStart else { return }
                let anchor = CGPoint(x: event.startAnchor.x * size.width, y: event.startAnchor.y * size.height)
                let result = start.magnified(to: start.zoom * event.magnification, around: anchor)
                zoom = result.zoom
                offset = result.offset
            }
            .onEnded { _ in pinchStart = nil })
        .onChange(of: pinchActive) { _, pinching in
            if !pinching { pinchStart = nil }
        }
        .onChange(of: zoom) {
            // When zooming out, commit the clamped position even if the
            // clipped image happens to be centered already.
            let bounded = MaskViewport(viewport: size, image: image.size, zoom: zoom, offset: offset).offset
            if offset != bounded { offset = bounded }
        }
    }

    private func hoverRequest(coverageKey: HoverCoverageKey?, viewport: MaskViewport) -> HoverRequest? {
        guard !pinchActive, edgeTask == nil, let active, let coverageKey, hoverCoverage?.key == coverageKey,
              active.strokes.count < 200, currentBrush.strength > 0 else { return nil }
        let points: [CGPoint]
        if case .edit = canvasDrag, edgeDragID != nil, !drag.isEmpty {
            points = drag
        } else {
            guard canvasDrag == nil, effectiveMode == .edit,
                  let pointer, viewport.frame.contains(pointer) else { return nil }
            points = [viewport.normalizedPoint(pointer)]
        }
        let stroke = brushStroke(points: points, mask: active)
        let context = PreviewContext(coverage: coverageKey, dragID: edgeDragID,
            sensitivity: currentBrush.edgeSensitivity, radius: stroke.radius,
            softness: currentBrush.softness, strength: currentBrush.strength, erases: stroke.erases)
        return HoverRequest(context: context, stroke: stroke)
    }

    private func queuePreview(_ request: HoverRequest?) {
        latestPreviewRequest = request
        guard request != nil else {
            hoverPreview = nil
            return
        }
        guard previewTask == nil else { return }
        previewTask = Task {
            defer { previewTask = nil }
            var rendered: HoverRequest?
            // Render at most one frame at a time. Mouse events that arrive
            // during that render collapse into the newest available path.
            while !Task.isCancelled, let next = latestPreviewRequest, next != rendered,
                  let coverage = hoverCoverage, coverage.key == next.context.coverage {
                rendered = next
                let preview = try? await guideRenderer.preview(source: coverage.raster, coverage: coverage.image,
                    stroke: next.stroke, sensitivity: next.context.sensitivity, inverted: coverage.key.guide.inverted)
                guard !Task.isCancelled else { return }
                if let preview, let latest = latestPreviewRequest,
                   latest == next || (next.context.dragID != nil && latest.context == next.context) {
                    hoverPreview = HoverResult(request: next, preview: preview,
                                               image: NSImage(cgImage: preview.image, size: .zero))
                }
                if next.context.dragID != nil {
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }
    }

    private func clearCanvasDrag() {
        canvasDrag = nil
        edgeDragID = nil
        drag = []
    }

    private func cancelBrushStroke() -> Bool {
        guard case .edit = canvasDrag, active?.kind.supportsBrush == true else { return false }
        discardCanvasDrag()
        return true
    }

    private func changeStrokeHistory(_ action: MaskEditorKeys.StrokeHistoryAction) {
        guard canChangeStrokeHistory, let active, active.kind.supportsBrush else { return }
        switch action {
        case .undo: model.undoMaskStroke(active.id)
        case .redo: model.redoMaskStroke(active.id)
        }
    }

    private func discardCanvasDrag() {
        // Keep the gesture captured so subsequent motion and mouse-up cannot start or commit a stroke.
        if canvasDrag != nil { canvasDrag = .ignored }
        edgeDragID = nil
        drag = []
        pointer = nil
        queuePreview(nil)
    }

    @ViewBuilder private func maskGuide(size: CGSize) -> some View {
        if showGuide, !adjustingEffect, let active {
            if active.kind.isAutomatic {
                if let automaticGuide, guideRequest?.id == active.id {
                    Image(nsImage: automaticGuide).resizable()
                        .frame(width: size.width, height: size.height)
                        .accessibilityHidden(true)
                }
            } else {
                guides(active, size: size)
            }
        }
    }

    private func controls(_ mask: LocalMask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Toggle(tr("Bật"), isOn: flag(mask, \.enabled, label: tr("Bật/tắt mặt nạ")))
                Toggle(tr("Đảo vùng"), isOn: flag(mask, \.inverted, label: tr("Đảo vùng mặt nạ")))
            }.toggleStyle(.checkbox)
            if mask.kind.supportsBrush {
                Picker(tr("Cọ"), selection: $erase) {
                    Text(tr("Tô")).tag(false)
                    Text(tr("Tẩy")).tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    Button(tr("Hoàn tác"), systemImage: "arrow.uturn.backward") { changeStrokeHistory(.undo) }
                        .disabled(mask.strokes.isEmpty)
                        .help(tr("Bỏ nét Tô hoặc Tẩy gần nhất trên mặt nạ này · ⌘Z"))
                    Button(tr("Làm lại"), systemImage: "arrow.uturn.forward") { changeStrokeHistory(.redo) }
                        .disabled(!model.canRedoMaskStroke(mask.id))
                        .help(tr("Khôi phục nét vừa hoàn tác trên mặt nạ này · ⇧⌘Z"))
                }
                .controlSize(.small)
                .disabled(!canChangeStrokeHistory)
                HStack {
                    Text(tr("Cỡ cọ"))
                    if mask.kind.isAutomatic {
                        Slider(value: $correctionRadius, in: 0.1...15, step: 0.1).accessibilityLabel(tr("Cỡ cọ"))
                    } else {
                        Slider(value: $radius, in: 1...15, step: 1).accessibilityLabel(tr("Cỡ cọ"))
                    }
                }
                if mask.kind.isAutomatic {
                    let brush = erase ? $eraseBrush : $paintBrush
                    brushSlider(tr("Độ mềm cọ"), value: brush.softness)
                        .help(tr("Làm dịu mép của nét cọ mới."))
                    brushSlider(tr("Độ đậm cọ"), value: brush.strength)
                        .help(tr("Mức thêm hoặc xóa vùng chọn trong mỗi nét."))
                    Toggle(tr("Bám viền"), isOn: brush.followsEdges)
                        .toggleStyle(.checkbox)
                        .help(tr("Giữ tâm cọ trên tóc hoặc nền cần sửa. Cọ hạn chế lan qua chỗ đổi màu rõ."))
                    if brush.wrappedValue.followsEdges {
                        brushSlider(tr("Độ nhạy bám viền"), value: brush.edgeSensitivity)
                            .help(tr("Mức cao giúp cọ dừng ở ranh giới có chênh lệch màu nhẹ."))
                    }
                    if edgeTask != nil { ProgressView(tr("Đang bám viền…")).controlSize(.small) }
                }
                let reset = mask.kind.isAutomatic ? tr("Đặt lại nét sửa") : tr("Xóa nét cọ")
                Button(reset) { model.modifyMask(mask.id, label: reset) { $0.strokes = [] } }
                    .foregroundStyle(Theme.muted).disabled(mask.strokes.isEmpty)
            }
            if mask.kind != .linear { slider(mask.kind.isAutomatic ? tr("Độ mềm mặt nạ") : tr("Độ mềm"), mask, \.feather, 0...100) }
            slider(mask.kind.isAutomatic ? tr("Cường độ mặt nạ") : tr("Cường độ"), mask, \.opacity, 0...100)
            if mask.purpose == .hair { slider(tr("Sắc màu tóc"), mask, \.hueRotation, -180...180) }
            slider(tr("Phơi sáng"), mask, \.exposure, -3...3, step: 0.05)
            slider(tr("Tương phản"), mask, \.contrast, -100...100)
            slider(tr("Độ bão hòa"), mask, \.saturation, -100...100)
            slider(tr("Nhiệt độ màu"), mask, \.temperature, -100...100)
            Button(role: .destructive) {
                model.change(tr("Xóa mặt nạ")) { $0.localMasks?.removeAll { $0.id == mask.id } }
            } label: { Label(tr("Xóa mặt nạ"), systemImage: "trash").foregroundStyle(.red.opacity(0.85)) }
        }.font(.system(size: 11))
    }

    private func brushSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title); Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .monospacedDigit().foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: 0...100, step: 1)
                .controlSize(.mini).accessibilityLabel(title)
        }
    }

    private func flag(_ mask: LocalMask, _ key: WritableKeyPath<LocalMask, Bool>, label: String) -> Binding<Bool> {
        Binding(get: { mask[keyPath: key] },
                set: { value in model.modifyMask(mask.id, label: label) { $0[keyPath: key] = value } })
    }

    private func slider(_ title: String, _ mask: LocalMask, _ key: WritableKeyPath<LocalMask, Double>,
                        _ range: ClosedRange<Double>, step: Double = 1) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title); Spacer()
                Text(mask[keyPath: key].formatted(.number.precision(.fractionLength(0...2))))
                    .monospacedDigit().foregroundStyle(Theme.accent)
            }
            Slider(value: Binding(get: { mask[keyPath: key] }, set: { value in
                model.modifyMask(mask.id, label: draggingSlider ? nil : title + tr(" • Mặt nạ")) { $0[keyPath: key] = value }
            }), in: range, step: step, onEditingChanged: { editing in
                draggingSlider = editing
                adjustingEffect = editing && key != \.feather
                if !editing { model.endGesture(title + tr(" • Mặt nạ")) }
            }).controlSize(.mini).accessibilityLabel(title)
        }
    }

    private func add(_ kind: LocalMask.Kind) {
        detectionMessage = nil
        guard kind.isAutomatic else {
            insert(LocalMask(kind: kind))
            return
        }
        guard let photo = model.selected, detecting == nil else { return }
        detecting = kind
        detectionTask = Task {
            defer { detecting = nil }
            do {
                let data = try await model.detectMask(kind, for: photo)
                guard !Task.isCancelled, model.selectedID == photo.id,
                      model.selected?.path == photo.path, masks.count < LocalMask.maximumCount else { return }
                var mask = LocalMask(kind: kind)
                mask.automaticPNG = data
                mask.feather = 15
                insert(mask)
            } catch {
                guard !Task.isCancelled else { return }
                detectionMessage = error.localizedDescription
            }
        }
    }

    private func insert(_ mask: LocalMask) {
        model.change(tr("Thêm mặt nạ ") + title(mask.kind).lowercased()) { edits in
            edits.localMasks = (edits.localMasks ?? []) + [mask]
        }
        selection = mask.id
        erase = false
        drag = []
    }

    private func track(_ event: DragGesture.Value, viewport: MaskViewport) {
        guard let active else { return }
        let point = viewport.normalizedPoint(event.location)
        switch active.kind {
        case .brush, .sky, .subject, .background:
            if drag.isEmpty { drag.append(viewport.normalizedPoint(event.startLocation)) }
            guard drag.count < 1500 else { return }
            let size = viewport.frame.size
            if let last = drag.last, hypot((last.x - point.x) * size.width, (last.y - point.y) * size.height) < 1 { return }
            drag.append(point)
        case .radial, .linear:
            drag = [viewport.normalizedPoint(event.startLocation), point]
        }
    }

    private func finish(_ event: DragGesture.Value, viewport: MaskViewport) {
        defer { drag = [] }
        guard let active else { return }
        let end = viewport.normalizedPoint(event.location)
        if active.kind.supportsBrush {
            let points = (drag.isEmpty ? [end] : drag + [end])
            let brush = currentBrush
            guard !active.kind.isAutomatic || brush.strength > 0 else { return }
            let stroke = brushStroke(points: points, mask: active)
            guard active.strokes.count < 200 else { return }
            let label = erase ? tr("Tẩy mặt nạ") : tr("Tô mặt nạ")
            if active.kind.isAutomatic && brush.followsEdges {
                addEdgeStroke(stroke, to: active, sensitivity: brush.edgeSensitivity, label: label)
            } else {
                model.modifyMask(active.id, label: label) { $0.strokes.append(stroke) }
            }
        } else {
            let start = viewport.normalizedPoint(event.startLocation)
            guard hypot(start.x - end.x, start.y - end.y) > 0.012 else { return }
            model.modifyMask(active.id, label: tr("Đặt vùng gradient")) { $0.start = start; $0.end = end }
        }
    }

    private func brushStroke(points: [CGPoint], mask: LocalMask) -> LocalMask.BrushStroke {
        let automatic = mask.kind.isAutomatic
        return LocalMask.BrushStroke(points: points, radius: (automatic ? correctionRadius : radius) / 100,
            erases: erase != (automatic && mask.inverted),
            softness: automatic ? currentBrush.softness : nil, strength: automatic ? currentBrush.strength : nil)
    }

    private func addEdgeStroke(_ stroke: LocalMask.BrushStroke, to mask: LocalMask,
                               sensitivity: Double, label: String) {
        guard edgeTask == nil, let photo = model.selected else { return }
        edgeMessage = nil
        edgeTask = Task {
            defer { edgeTask = nil }
            do {
                var refined = stroke
                refined.edgeSelection = try await model.selectBrushEdges(stroke, sensitivity: sensitivity)
                guard !Task.isCancelled, model.selectedID == photo.id, model.selected?.path == photo.path,
                      let current = masks.first(where: { $0.id == mask.id }),
                      current.strokes == mask.strokes, current.inverted == mask.inverted else { return }
                model.modifyMask(mask.id, label: label) { $0.strokes.append(refined) }
            } catch {
                if !Task.isCancelled { edgeMessage = tr("Không thể bám viền cho nét này. Hãy thử lại hoặc bỏ chọn Bám viền.") }
            }
        }
    }

    private func guides(_ mask: LocalMask, size: CGSize) -> some View {
        Canvas { context, _ in
            func display(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height) }
            if mask.kind == .brush {
                // Replay the brush and eraser into one translucent overlay.
                context.opacity = 0.37
                context.drawLayer { layer in
                    func draw(_ points: [CGPoint], radius: Double, erases: Bool) {
                        guard let first = points.first else { return }
                        layer.blendMode = erases ? .destinationOut : .normal
                        let diameter = 2 * radius * max(size.width, size.height)
                        let center = display(first)
                        if points.count == 1 || first == points.last && points.count == 2 {
                            layer.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                             width: diameter, height: diameter)), with: .color(Theme.accent))
                        } else {
                            var path = Path()
                            path.move(to: center)
                            for point in points.dropFirst() { path.addLine(to: display(point)) }
                            layer.stroke(path, with: .color(Theme.accent),
                                         style: StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))
                        }
                    }
                    for stroke in mask.strokes { draw(stroke.points, radius: stroke.radius, erases: stroke.erases) }
                    draw(drag, radius: radius / 100, erases: erase)
                }
                return
            }
            let start = display(drag.first ?? mask.start), end = display(drag.last ?? mask.end)
            let dx = end.x - start.x, dy = end.y - start.y
            let distance = hypot(dx, dy)
            guard distance > 0.1 else { return }
            var path = Path()
            path.move(to: start); path.addLine(to: end)
            if mask.kind == .radial {
                path.addEllipse(in: CGRect(x: start.x - distance, y: start.y - distance,
                                          width: distance * 2, height: distance * 2))
            } else {
                let length = max(size.width, size.height) / distance
                for p in [start, end] {
                    path.move(to: CGPoint(x: p.x - dy * length, y: p.y + dx * length))
                    path.addLine(to: CGPoint(x: p.x + dy * length, y: p.y - dx * length))
                }
            }
            context.stroke(path, with: .color(.black.opacity(0.65)), lineWidth: 3)
            context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            for p in [start, end] {
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(Theme.accent))
            }
        }.clipped().allowsHitTesting(false)
    }

    private func title(_ kind: LocalMask.Kind) -> String {
        switch kind {
        case .sky: return tr("Bầu trời")
        case .subject: return tr("Chủ thể")
        case .background: return tr("Hậu cảnh")
        case .linear: return tr("Gradient thẳng")
        case .radial: return tr("Gradient tròn")
        case .brush: return tr("Cọ")
        }
    }

    private func instruction(_ kind: LocalMask.Kind) -> String {
        switch kind {
        case .sky, .subject, .background: return tr("Tô để thêm vùng bị thiếu, Tẩy để bớt vùng bị lấn. Lớp phủ hồng hiển thị vùng chọn.")
        case .linear: return tr("Kéo từ vùng chỉnh mạnh nhất đến nơi hiệu ứng kết thúc.")
        case .radial: return tr("Kéo từ tâm vùng chỉnh đến rìa. Điều chỉnh độ mềm để hòa vào nền.")
        case .brush: return tr("Kéo để tô vùng cần chỉnh. Chọn Tẩy để bỏ bớt vùng đã tô.")
        }
    }
}
