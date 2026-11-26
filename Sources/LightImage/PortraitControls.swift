import SwiftUI
import LightImageCore

struct PortraitControls: View {
    @EnvironmentObject private var model: AppModel
    @State private var locatingWaist = false
    @State private var editingFaceControl = false

    private var selectedSubjects: [PortraitSubject] {
        guard let preview = model.portraitPreview else { return [] }
        guard let selected = model.edits.portraitFace else { return preview.subjects }
        return preview.subjects.filter { $0.matches(selected) }
    }

    var body: some View {
        if let preview = model.portraitPreview {
            if preview.subjects.isEmpty {
                Text(model.portraitAnalysisFailed ? "Không thể nhận diện khuôn mặt." : "Không tìm thấy khuôn mặt.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else {
                facePicker(preview)
            }

            Group {
                faceSlider("Làm trắng da", \.brighten)
                faceSlider("Làm mịn da", \.smoothing)
                faceSlider("Xóa mụn", \.blemishes)
                    .help("Xử lý đốm nhỏ, bảo vệ mắt và môi. Mặc định đi theo Làm mịn da, bạn có thể chỉnh hai mức riêng.")
                faceSlider("Thon mặt", \.slim)
            }.disabled(selectedSubjects.isEmpty)
            if let face = model.edits.portraitFace, model.edits.faceRetouch.hasOwnSettings(for: face), !selectedSubjects.isEmpty {
                Button("Dùng mức chung cho khuôn mặt này") {
                    model.change("Dùng mức chỉnh chân dung chung") { $0.useCommonFaceRetouch(for: face) }
                }
                .font(.system(size: 10)).foregroundStyle(Theme.accent)
            }
            AdjustmentSlider(title: "Thon eo", key: PortraitControl.waistSlim.key, range: 0...100)
                .disabled(model.edits.portraitWaist == nil && !selectedSubjects.contains { $0.waist != nil })
            waistControls
            AdjustmentSlider(title: "Thon tay", key: PortraitControl.armSlim.key, range: 0...100)
                .disabled(!selectedSubjects.contains(where: \.canSlimArms))
                .help("Vision cần nhận diện được các khớp tay của người đã chọn.")
            AdjustmentSlider(title: "Thon chân", key: PortraitControl.legSlim.key, range: 0...100)
                .disabled(!selectedSubjects.contains(where: \.canSlimLegs))
                .help("Vision cần nhận diện được các khớp chân của người đã chọn.")
            Button { model.editHair() } label: { Label("Chỉnh tóc…", systemImage: "paintbrush") }
                .font(.system(size: 11)).foregroundStyle(Theme.accent)
                .disabled(!model.canEditHair)
                .help("Tô vùng tóc để chỉnh riêng sắc màu, độ sáng và độ bão hòa.")
            Button("Đặt lại chỉnh sửa chân dung") {
                model.change("Đặt lại chỉnh sửa chân dung") {
                    $0.keepPortrait(from: Adjustments())
                    $0.localMasks?.removeAll { $0.purpose == .hair }
                }
            }
            .font(.system(size: 10)).foregroundStyle(Theme.muted)
            .disabled(!model.edits.hasPortraitEdits && model.edits.portraitFace == nil &&
                      model.edits.portraitWaist == nil && model.hairMask == nil)
            .sheet(isPresented: $locatingWaist) {
                WaistPicker(image: preview.source, initial: model.edits.portraitWaist) { model.setPortraitWaist($0) }
            }
        } else {
            ProgressView("Đang nhận diện chân dung…").controlSize(.small).font(.system(size: 11))
        }
    }

    private func faceSlider(_ title: String, _ key: WritableKeyPath<PortraitRetouch.Settings, Double>) -> some View {
        let retouch = model.edits.faceRetouch
        let face = model.edits.portraitFace
        let value = min(max(retouch.settings(for: face)[keyPath: key], 0), 100)
        let hasDifferentValues = face == nil && selectedSubjects.contains { retouch.settings(for: $0.face)[keyPath: key] != value }
        return VStack(spacing: 5) {
            HStack {
                Text(title).foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                if hasDifferentValues {
                    Text("Có mức riêng").foregroundStyle(Theme.muted)
                } else {
                    Text(value.formatted(.number.precision(.fractionLength(0))))
                        .monospacedDigit().foregroundStyle(value == 0 ? Theme.muted : Theme.accent)
                }
            }.font(.system(size: 10))
            Slider(value: Binding(get: { value }, set: { value in
                model.updateFaceRetouch(key, value, label: editingFaceControl ? nil : title)
            }), in: 0...100, step: 1, onEditingChanged: { editing in
                editingFaceControl = editing
                if !editing { model.endGesture(title) }
            })
            .controlSize(.mini).accessibilityLabel(title)
        }
    }

    private func facePicker(_ preview: PortraitPreview) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(preview.subjects.count) khuôn mặt").font(.system(size: 11))
                Spacer()
                Button("Tất cả khuôn mặt") { model.selectPortrait(nil) }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.edits.portraitFace == nil ? Theme.accent : Theme.muted)
                    .accessibilityAddTraits(model.edits.portraitFace == nil ? .isSelected : [])
                    .help("Mỗi thanh bạn chỉnh sẽ áp dụng cho mọi khuôn mặt trong ảnh.")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(preview.subjects.indices, id: \.self) { index in
                        let subject = preview.subjects[index]
                        let selected = model.edits.portraitFace.map { subject.matches($0) } ?? false
                        Button { model.selectPortrait(subject.face) } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5).fill(Theme.surface)
                                    if let face = preview.thumbnails[index] {
                                        Image(nsImage: face).resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "person.fill")
                                    }
                                }
                                .frame(width: 42, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                                Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(selected ? Theme.accent : Theme.muted)
                            }
                        }
                        .accessibilityLabel("Khuôn mặt \(index + 1)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.padding(2)
            }.scrollIndicators(.visible)
            if model.edits.portraitFace != nil && selectedSubjects.isEmpty {
                Text("Hãy chọn lại khuôn mặt cần chỉnh.").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var waistControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.edits.portraitWaist != nil {
                Text("Đang dùng vùng eo đã chọn.").foregroundStyle(Theme.muted)
            } else {
                let count = selectedSubjects.filter { $0.waist != nil }.count
                if count == 0 {
                    Text("Chưa thấy rõ eo. Bạn có thể đặt vùng chỉnh trên ảnh.").foregroundStyle(Theme.muted)
                } else {
                    Text("Tìm thấy \(count) vùng eo.").foregroundStyle(Theme.muted)
                }
            }
            HStack {
                Button { locatingWaist = true } label: { Label("Chọn vùng eo…", systemImage: "scope") }
                Spacer()
                if model.edits.portraitWaist != nil {
                    Button("Dùng tự động") { model.setPortraitWaist(nil) }
                }
            }.foregroundStyle(Theme.accent)
        }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 11))
    }
}

private struct WaistPicker: View {
    @Environment(\.dismiss) private var dismiss
    let image: NSImage
    let apply: (PortraitWaist) -> Void
    @State private var waist: PortraitWaist?

    init(image: NSImage, initial: PortraitWaist?, apply: @escaping (PortraitWaist) -> Void) {
        self.image = image
        self.apply = apply
        _waist = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chọn vùng eo").font(.headline)
            Text("Kéo ngang từ mép eo bên này sang mép bên kia.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            GeometryReader { proxy in
                let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                    .overlay {
                        if let waist {
                            let w = waist.width * size.width
                            Ellipse().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                .background(Theme.accent.opacity(0.14), in: Ellipse())
                                .frame(width: w, height: w * 0.60)
                                .position(x: waist.center.x * size.width, y: (1 - waist.center.y) * size.height)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                        let start = min(max(value.startLocation.x / size.width, 0), 1)
                        let end = min(max(value.location.x / size.width, 0), 1)
                        let midpoint = (start + end) / 2
                        let y = 1 - min(max(value.startLocation.y / size.height, 0), 1)
                        waist = PortraitWaist(center: CGPoint(x: midpoint, y: y),
                                              width: min(max(abs(start - end), 0.02), 0.8))
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Hủy") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Dùng vùng này") {
                    if let waist { apply(waist); dismiss() }
                }.buttonStyle(AccentButtonStyle()).disabled(waist == nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 650, height: 470)
        .background(Theme.panel)
    }
}
