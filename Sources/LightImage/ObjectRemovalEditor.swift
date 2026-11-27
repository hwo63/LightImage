import SwiftUI
import LightImageCore

struct ObjectRemovalEditor: LocalizedView {
    @AppStorage(AppLanguage.defaultsKey) var language = AppLanguage.vietnamese
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let photo: PhotoRecord
    @State private var image: NSImage?
    @State private var strokes: [LocalMask.BrushStroke] = []
    @State private var points: [CGPoint] = []
    @State private var pointer: CGPoint?
    @State private var size = 2.0
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(tr("Xóa vật thể AI"), systemImage: "eraser").font(.headline)
                Spacer()
                Button("Xong") { dismiss() }.disabled(working).keyboardShortcut(.cancelAction)
            }
            Text(tr("Tô phủ vật thể và mép viền. LaMa sẽ tạo vùng thay thế dựa trên phần ảnh xung quanh."))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            GeometryReader { proxy in
                ZStack {
                    Theme.background
                    if let image {
                        let viewport = MaskViewport(viewport: proxy.size, image: image.size)
                        canvas(image, size: viewport.frame.size)
                            .position(x: viewport.frame.midX, y: viewport.frame.midY)
                    } else if message == nil {
                        ProgressView(tr("Đang mở ảnh…"))
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack(spacing: 14) {
                Text(tr("Cỡ cọ")).font(.system(size: 11))
                Slider(value: $size, in: 0.3...12).controlSize(.small).frame(width: 125)
                    .accessibilityLabel(tr("Cỡ cọ xóa vật thể"))
                Button(tr("Bỏ nét tô")) { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty)
                Button(tr("Bỏ lần xóa cuối")) {
                    model.change(tr("Bỏ lần xóa vật thể cuối")) {
                        if $0.objectRepairs?.isEmpty == false { $0.objectRepairs?.removeLast() }
                    }
                }.disabled(photo.adjustments.objectRepairs?.isEmpty != false)
                Spacer()
                Button(tr("Lấp vùng bằng AI")) { generate() }
                    .buttonStyle(AccentButtonStyle()).disabled(strokes.isEmpty || image == nil)
            }.disabled(working)
            if working {
                ProgressView(tr("Đang chuẩn bị mô hình hoặc tạo vùng thay thế…")).controlSize(.small)
            } else {
                Text(tr("Lần đầu cần tải mô hình LaMa khoảng 217 MB. Ảnh được xử lý trên máy Mac."))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .padding(20).frame(width: 900, height: 608)
        .background(Theme.panel).interactiveDismissDisabled(working)
        .task(id: photo.adjustments.objectRepairs) {
            do {
                let preview = try await model.objectRemovalPreview(for: photo)
                if !Task.isCancelled { image = preview }
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }

    private func canvas(_ image: NSImage, size display: CGSize) -> some View {
        let viewport = MaskViewport(viewport: display, image: image.size)
        let edge = max(display.width, display.height)
        let radius = size / 100
        return Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: display.width, height: display.height)
            .overlay {
                Canvas { context, _ in
                    context.opacity = 0.5
                    let allStrokes = strokes + [.init(points: points, radius: radius, erases: false)]
                    for stroke in allStrokes {
                        let points = stroke.points.map { CGPoint(x: $0.x * display.width, y: (1 - $0.y) * display.height) }
                        guard let first = points.first else { continue }
                        let width = stroke.radius * edge * 2
                        if points.count == 1 {
                            context.fill(Path(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2,
                                                                width: width, height: width)), with: .color(.pink))
                        } else {
                            var path = Path()
                            path.addLines(points)
                            context.stroke(path, with: .color(.pink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                        }
                    }
                }.allowsHitTesting(false)
                if let pointer, !working {
                    Circle().strokeBorder(.white, lineWidth: 1)
                        .frame(width: radius * edge * 2, height: radius * edge * 2)
                        .position(pointer).allowsHitTesting(false)
                }
            }.clipped().contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): pointer = point
                case .ended: pointer = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !working else { return }
                let point = viewport.normalizedPoint(value.location)
                if points.isEmpty { points.append(viewport.normalizedPoint(value.startLocation)) }
                if points.last != point { points.append(point) }
            }.onEnded { _ in
                if !working, !points.isEmpty { strokes.append(.init(points: points, radius: radius, erases: false)) }
                points.removeAll()
            })
            .accessibilityLabel(tr("Ảnh để tô vùng cần xóa"))
    }

    private func generate() {
        guard !working, !strokes.isEmpty else { return }
        working = true
        message = nil
        let selection = strokes
        Task {
            defer { working = false }
            do {
                try await model.removeObject(in: photo, strokes: selection)
                strokes.removeAll()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
