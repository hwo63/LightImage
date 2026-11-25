import SwiftUI
import LightImageCore
import UniformTypeIdentifiers

enum Theme {
    static let background = Color(red: 0.067, green: 0.075, blue: 0.078)
    static let panel = Color(red: 0.092, green: 0.102, blue: 0.106)
    static let surface = Color(red: 0.13, green: 0.145, blue: 0.15)
    static let line = Color.white.opacity(0.075)
    static let muted = Color(red: 0.52, green: 0.56, blue: 0.56)
    static let accent = Color(red: 0.77, green: 0.88, blue: 0.56)
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false
    var body: some View {
        VStack(spacing: 0) {
            topbar
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 0) {
                SidebarView().frame(width: 222)
                Rectangle().fill(Theme.line).frame(width: 1)
                VStack(spacing: 0) {
                    if model.libraryMode { LibraryView() } else { PhotoCanvas() }
                    if !model.catalog.photos.isEmpty { FilmstripView() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Theme.line).frame(width: 1)
                InspectorView().frame(width: 306)
            }
            statusbar
        }
        .background(Theme.background)
        .tint(Theme.accent)
        .foregroundStyle(Color.white.opacity(0.9))
        .buttonStyle(.plain)
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 3).padding(5).allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in model.importURLs(urls); return true } isTargeted: { dropTargeted = $0 }
        .alert("LightImage", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Đóng") { model.error = nil }
            if model.selected != nil { Button("Chọn lại ảnh gốc…") { model.error = nil; model.relink() } }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Thông tin từ LightImage", systemImage: "info.circle").font(.title3.weight(.semibold))
                ScrollView { Text(model.notice ?? "").textSelection(.enabled).font(.system(size: 13)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 360)
                HStack { Spacer(); Button("Đã hiểu") { model.notice = nil }.buttonStyle(AccentButtonStyle()) }.keyboardShortcut(.defaultAction)
            }.padding(28).frame(width: 550).background(Theme.panel)
        }
        .sheet(isPresented: $model.exportSheet) { ExportView() }
        .sheet(isPresented: $model.maskSheet) { MaskEditor() }
    }
    private var topbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "camera.aperture").font(.system(size: 25, weight: .light)).foregroundStyle(Theme.accent)
                Text("lightimage").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.6)
            }.frame(width: 222)
            HStack(spacing: 6) {
                tab("Thư viện", icon: "square.grid.2x2", selected: model.libraryMode) { model.libraryMode = true }
                tab("Chỉnh ảnh", icon: "slider.horizontal.3", selected: !model.libraryMode) { model.libraryMode = false }
            }.padding(.leading, 24)
            Spacer()
            if model.selected != nil {
                HStack(spacing: 14) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Hoàn tác · ⌘Z")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Làm lại · ⇧⌘Z")
                }.font(.system(size: 13)).padding(.trailing, 28)
            }
            Button { model.importPhotos() } label: { Label("Nhập ảnh", systemImage: "plus").font(.system(size: 12, weight: .medium)) }.buttonStyle(QuietButtonStyle())
            Button { model.exportSheet = true } label: { Label("Xuất ảnh", systemImage: "square.and.arrow.up").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(AccentButtonStyle()).disabled(model.selected == nil || model.isExporting).padding(.leading, 10).padding(.trailing, 20)
        }.frame(height: 68).background(Theme.panel)
    }
    private func tab(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: icon).font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 9).background(selected ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(selected ? .white : Theme.muted) }
    }
    private var statusbar: some View {
        HStack(spacing: 8) {
            Circle().fill(model.saved ? Theme.accent : Color.orange).frame(width: 5, height: 5)
            Text(model.status).lineLimit(1)
            Spacer()
            if model.isRendering || model.isExporting || model.isImporting { ProgressView().controlSize(.mini) }
            Text(model.saved ? "Đã lưu trên máy" : "Đang lưu…")
            Text("·").padding(.horizontal, 5)
            Text(LightImageVersion.displayName).foregroundStyle(Theme.muted)
        }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 20).frame(height: 28).background(Theme.panel)
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @State private var showHistory = false
    @State private var savePreset = false
    @State private var presetName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            caption("KHÔNG GIAN CỦA BẠN").padding(.top, 26).padding(.bottom, 15)
            navigationRow("Tất cả ảnh", icon: "photo.on.rectangle.angled", key: "all", count: model.catalog.photos.count)
            navigationRow("Đã đánh dấu", icon: "flag", key: "flagged", count: model.catalog.photos.filter(\.flagged).count)
            navigationRow("Ảnh nổi bật", icon: "star", key: "rated", count: model.catalog.photos.filter { $0.rating >= 4 }.count)
            navigationRow("Đã chỉnh sửa", icon: "slider.horizontal.3", key: "edited", count: model.catalog.photos.filter { $0.adjustments.isEdited }.count)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 24).padding(.horizontal, 18)
            HStack {
                Button("Preset") { showHistory = false }.foregroundStyle(showHistory ? Theme.muted : .white)
                Button("Lịch sử") { showHistory = true }.foregroundStyle(showHistory ? .white : Theme.muted).padding(.leading, 12)
                Spacer()
                Menu { Button("Nhập preset Lightroom…") { model.importPresets() }; Button("Lưu chỉnh sửa thành preset…") { savePreset = true }.disabled(model.selected == nil) } label: { Image(systemName: "plus").foregroundStyle(Theme.muted) }.menuStyle(.borderlessButton).frame(width: 20)
            }.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 20)
            if showHistory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.currentHistory.reversed()) { step in
                            Label(step.label, systemImage: "circle.dotted").font(.system(size: 11)).lineLimit(2)
                        }
                        Label("Ảnh gốc", systemImage: "photo").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Text("Lịch sử hoàn tác lưu trong phiên này. Chỉnh sửa cuối cùng được lưu khi đóng ứng dụng.").font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(3)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
            } else {
                HStack(spacing: 6) { Image(systemName: "magnifyingglass"); TextField("Tìm preset…", text: $model.presetQuery).textFieldStyle(.plain) }
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(9).background(Theme.background, in: RoundedRectangle(cornerRadius: 5)).padding(.horizontal, 16).padding(.top, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(Set(model.visiblePresets.map(\.group))).sorted(), id: \.self) { group in
                            Text(group.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 19).padding(.bottom, 7).padding(.leading, 8)
                            ForEach(model.visiblePresets.filter { $0.group == group }) { preset in
                                presetRow(preset)
                            }
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 16)
                }
                if model.activePreset != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text("Cường độ preset"); Spacer(); Text("\(Int(model.presetStrength))%") }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                        Slider(value: Binding(get: { model.presetStrength }, set: { model.updatePresetStrength($0) }), in: 0...100, onEditingChanged: { if !$0 { model.endGesture("Cường độ preset") } }).controlSize(.mini)
                    }.padding(18)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "slider.horizontal.2.square"); Text("Mang màu sắc của bạn vào") }.font(.system(size: 11, weight: .medium))
                    Text("Nhập preset Lightroom\n.xmp và .lrtemplate").font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(4)
                    Button { model.importPresets() } label: { HStack { Text("Nhập preset"); Spacer(); Image(systemName: "arrow.down.to.line") }.font(.system(size: 11, weight: .medium)) }.buttonStyle(QuietButtonStyle())
                }.padding(14).background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)).padding(14)
            }
        }.frame(maxHeight: .infinity, alignment: .top).background(Theme.panel)
            .alert("Lưu preset", isPresented: $savePreset) {
                TextField("Tên preset", text: $presetName)
                Button("Hủy", role: .cancel) {}
                Button("Lưu") { model.savePreset(name: presetName); presetName = "" }
            } message: { Text("Lưu các thông số màu hiện tại để dùng cho ảnh khác. Xoay và cắt không nằm trong preset.") }
    }
    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.muted).padding(.horizontal, 20) }
    private func navigationRow(_ text: String, icon: String, key: String, count: Int) -> some View {
        Button { model.filter = key; model.libraryMode = true } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 16)
                Text(text)
                Spacer()
                Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
            }.font(.system(size: 12)).foregroundStyle(model.filter == key ? Theme.accent : Color.white.opacity(0.65)).padding(.horizontal, 13).padding(.vertical, 10).background(model.filter == key ? Theme.accent.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.padding(.horizontal, 10)
    }
    private func presetRow(_ preset: PhotoPreset) -> some View {
        Button { model.apply(preset) } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3).fill(preset.monochrome == true ? AnyShapeStyle(LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(LinearGradient(colors: [Theme.accent.opacity(0.65), Color(red: 0.25, green: 0.4, blue: 0.38), Color(red: 0.69, green: 0.48, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))).frame(width: 28, height: 28)
                Text(preset.name).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
                if !preset.unsupported.isEmpty { Image(systemName: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange) }
                if model.selectedPreset == preset.id { Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(Theme.accent) }
            }.padding(7).background(model.selectedPreset == preset.id ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.disabled(model.selected == nil).help(preset.source + (preset.unsupported.isEmpty ? "" : " · Có thông số chưa hỗ trợ"))
            .contextMenu {
                Button("Xem thông tin") { model.notice = "\(preset.name)\nNguồn: \(preset.source)\n\(preset.supportedCount) mục được hỗ trợ.\n\nChưa hỗ trợ: \(preset.unsupported.isEmpty ? "Không có mục được phát hiện" : preset.unsupported.joined(separator: ", "))\n\nMàu được mô phỏng bằng LightImage." }
                if preset.source != "LightImage" || preset.group == "Preset của tôi" { Button("Xóa preset", role: .destructive) { model.deletePreset(preset.id) } }
            }
    }
}

struct PhotoCanvas: View {
    @EnvironmentObject var model: AppModel
    @State private var zoom = Zoom.fit
    @State private var center = CGPoint(x: 0.5, y: 0.5)

    private enum Zoom: Equatable {
        case fit, pixels, custom(Double)
    }

    private let canvasInset: CGFloat = 28
    private let toolbarHeight: CGFloat = 46

    var body: some View {
        VStack(spacing: 0) {
            if let selected = model.selected {
                HStack(spacing: 9) {
                    Text(selected.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(selected.path.hasSuffix("Alpine morning.jpg") ? "ẢNH MINH HỌA" : URL(fileURLWithPath: selected.path).pathExtension.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.vertical, 3).background(Theme.surface, in: RoundedRectangle(cornerRadius: 3))
                    Spacer()
                    Text(model.sourceSize).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                }.padding(.horizontal, 26).frame(height: 47)
                GeometryReader { geometry in
                    let canvasHeight = max(0, geometry.size.height - toolbarHeight)
                    let area = CGSize(width: max(0, geometry.size.width - 2 * canvasInset),
                                      height: max(0, canvasHeight - 2 * canvasInset))
                    VStack(spacing: 0) {
                        canvas(area: area)
                            .frame(width: geometry.size.width, height: canvasHeight)
                            .clipped()
                        toolbar(rating: selected.rating)
                    }
                }
            } else { WelcomeView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.selectedID) { resetZoom() }
    }

    @ViewBuilder private func canvas(area: CGSize) -> some View {
        if let preview = model.preview {
            let original = model.original ?? preview
            if model.compare {
                sideBySide(before: original, after: preview, area: area)
            } else {
                let viewport = photoViewport(area: area, image: preview.size)
                let input = photoInput(area: area, image: preview.size)
                if model.splitCompare {
                    SplitComparison(before: original, after: preview, area: area, viewport: viewport, input: input)
                } else {
                    photoPanel(preview, rect: viewport.frame, area: area, input: input)
                }
            }
        } else if model.isRendering {
            ProgressView("Đang mở ảnh…").font(.system(size: 11)).tint(Theme.accent)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                Text("Không đọc được ảnh gốc")
                Button("Chọn lại tệp…") { model.relink() }.buttonStyle(QuietButtonStyle())
            }.foregroundStyle(Theme.muted)
        }
    }

    private func sideBySide(before: NSImage, after: NSImage, area: CGSize) -> some View {
        let spacing: CGFloat = 16
        let panelSize = CGSize(width: max(0, (area.width - spacing) / 2), height: max(0, area.height - 26))
        let rect = photoViewport(area: panelSize, image: after.size).frame
        let input = photoInput(area: panelSize, image: after.size)
        return HStack(spacing: spacing) {
            comparisonPanel(before, label: "TRƯỚC", rect: rect, area: panelSize, input: input)
            comparisonPanel(after, label: "SAU", rect: rect, area: panelSize, input: input)
        }
    }

    private func comparisonPanel(_ image: NSImage, label: String, rect: CGRect, area: CGSize,
                                 input: PhotoPreviewInput) -> some View {
        VStack(spacing: 12) {
            photoPanel(image, rect: rect, area: area, input: input)
            Text(label).font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(Theme.muted)
        }
    }

    private func photoPanel(_ image: NSImage, rect: CGRect, area: CGSize, input: PhotoPreviewInput) -> some View {
        ZStack {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 9)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: area.width, height: area.height)
        .clipped()
        .overlay { input }
    }

    private func photoInput(area: CGSize, image: CGSize) -> PhotoPreviewInput {
        PhotoPreviewInput { factor, point in
            let current = photoViewport(area: area, image: image)
            let next = current.magnified(to: current.zoom * factor, around: point)
            guard next.zoom != current.zoom else { return }
            zoom = next.zoom == 1 ? .fit : .custom(next.zoom)
            center = next.normalizedCenter
        } pan: { delta in
            let current = photoViewport(area: area, image: image)
            guard current.zoom > 1 else { return }
            center = current.panned(by: delta).normalizedCenter
        }
    }

    private func photoViewport(area: CGSize, image: CGSize) -> MaskViewport {
        let factor: Double
        switch zoom {
        case .fit: factor = 1
        case .pixels:
            let fitted = MaskViewport(viewport: area, image: image, fitScaleLimit: 1)
            factor = fitted.frame.width > 0 ? image.width / fitted.frame.width : 1
        case .custom(let value): factor = value
        }
        return MaskViewport(viewport: area, image: image, zoom: factor, fitScaleLimit: 1).centered(on: center)
    }

    private func resetZoom() {
        zoom = .fit
        center = CGPoint(x: 0.5, y: 0.5)
    }

    private func toolbar(rating: Int) -> some View {
        HStack(spacing: 20) {
            HStack(spacing: 10) {
                Button { resetZoom() } label: {
                    Text("Vừa khung").foregroundStyle(zoom == .fit ? Theme.accent : Theme.muted)
                }.help("Cuộn chuột trên ảnh để phóng to hoặc thu nhỏ. Kéo ảnh khi đã phóng to.")
                Button {
                    zoom = .pixels
                    center = CGPoint(x: 0.5, y: 0.5)
                    model.compare = false
                    model.splitCompare = false
                } label: {
                    Text("100% xem trước").foregroundStyle(zoom == .pixels ? Theme.accent : Theme.muted)
                }.help("Xem pixel bản xem trước, cạnh dài tối đa 2400 px. Xuất ảnh vẫn dùng độ phân giải gốc.")
                if case .custom(let factor) = zoom {
                    Text("\(Int((factor * 100).rounded()))%").monospacedDigit().foregroundStyle(Theme.accent)
                        .accessibilityLabel("Mức zoom so với vừa khung")
                        .accessibilityValue("\(Int((factor * 100).rounded()))%")
                        .help("Mức zoom so với vừa khung")
                }
            }
            Spacer()
            RatingView(rating: rating) { model.setRating($0) }
            Button { model.toggleFlag() } label: {
                Image(systemName: "flag.fill").foregroundStyle(model.selected?.flagged == true ? Theme.accent : Theme.muted)
            }.help("Đánh dấu · P")
            Spacer()
            Button { model.compare.toggle(); model.splitCompare = false } label: {
                Label("Trước / Sau", systemImage: "rectangle.split.2x1").foregroundStyle(model.compare ? Theme.accent : Theme.muted)
            }.help("So sánh · \\")
            Button { model.splitCompare.toggle(); model.compare = false } label: {
                Label("Kéo vạch", systemImage: "rectangle.split.2x1.fill").foregroundStyle(model.splitCompare ? Theme.accent : Theme.muted)
            }.help("Cuộn để zoom. Kéo vạch để so sánh hoặc kéo ngoài vạch để di chuyển ảnh đã phóng to.")
        }.font(.system(size: 10)).padding(.horizontal, 26).frame(height: toolbarHeight)
    }

}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.07), lineWidth: 1).frame(width: 180, height: 180)
                Circle().stroke(Theme.accent.opacity(0.14), lineWidth: 1).frame(width: 136, height: 136)
                Image(systemName: "camera.aperture").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(Theme.accent)
            }.padding(.bottom, 26)
            Text("Ánh sáng. Màu sắc. Câu chuyện.").font(.system(size: 28, weight: .light, design: .serif)).multilineTextAlignment(.center)
            Text("Không gian riêng cho những khung hình của bạn.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 14)
            Button { model.importPhotos() } label: { Label("Mở những bức ảnh đầu tiên", systemImage: "plus").font(.system(size: 12, weight: .semibold)) }.buttonStyle(AccentButtonStyle()).padding(.top, 30)
            Text("Kéo ảnh hoặc thư mục vào đây · RAW, JPEG, HEIC, PNG, TIFF").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 16)
            Button("Khám phá với ảnh minh họa  ↗") { model.loadDemo() }.font(.system(size: 11)).foregroundStyle(Theme.accent.opacity(0.8)).padding(.top, 32)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FilmstripView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Text("\(model.photos.count) ẢNH").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                Spacer()
                Button { model.moveSelection(-1) } label: { Image(systemName: "chevron.left") }
                Button { model.moveSelection(1) } label: { Image(systemName: "chevron.right") }.padding(.leading, 12)
            }.foregroundStyle(Theme.muted).padding(.horizontal, 22).frame(height: 29)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.photos) { photo in
                            Button { model.select(photo.id); model.libraryMode = false } label: {
                                VStack(spacing: 5) {
                                    Thumbnail(photo: photo).frame(width: 102, height: 66).clipped().padding(3).background(model.selectedID == photo.id ? Theme.accent.opacity(0.1) : Theme.surface).clipShape(RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).stroke(model.selectedID == photo.id ? Theme.accent : .clear, lineWidth: 1))
                                    Text(photo.name).font(.system(size: 8)).foregroundStyle(model.selectedID == photo.id ? Theme.accent : Theme.muted).lineLimit(1).frame(width: 104)
                                }
                            }.id(photo.id)
                        }
                    }.padding(.horizontal, 22).padding(.bottom, 10)
                }.scrollIndicators(.hidden).onChange(of: model.selectedID) { _, id in if let id { withAnimation { proxy.scrollTo(id) } } }
            }
        }.frame(height: 128).background(Theme.panel.opacity(0.6))
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("Những khung hình của bạn").font(.system(size: 22, weight: .light, design: .serif)); Text("\(model.photos.count) ảnh trong chế độ lọc hiện tại").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Spacer()
                HStack { Image(systemName: "magnifyingglass"); TextField("Tìm tên ảnh", text: $model.query).textFieldStyle(.plain) }.font(.system(size: 11)).foregroundStyle(Theme.muted).padding(9).frame(width: 170).background(Theme.surface, in: RoundedRectangle(cornerRadius: 5))
            }
            if model.catalog.photos.isEmpty { WelcomeView() }
            else if model.photos.isEmpty { ContentUnavailableView("Không tìm thấy ảnh", systemImage: "photo.on.rectangle", description: Text("Đổi bộ lọc hoặc từ khóa tìm kiếm.")) }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 18)], spacing: 20) {
                        ForEach(model.photos) { photo in
                            VStack(alignment: .leading, spacing: 9) {
                                Thumbnail(photo: photo).frame(height: 148).frame(maxWidth: .infinity).background(Theme.panel).clipped().clipShape(RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(model.selectedID == photo.id ? Theme.accent : .clear))
                                    .onTapGesture(count: 2) { model.select(photo.id); model.libraryMode = false }
                                    .onTapGesture { model.select(photo.id) }
                                HStack { Text(photo.name).lineLimit(1); Spacer(); if photo.flagged { Image(systemName: "flag.fill").foregroundStyle(Theme.accent) } }.font(.system(size: 10))
                                HStack(spacing: 3) { ForEach(0..<5) { i in Image(systemName: i < photo.rating ? "star.fill" : "star").font(.system(size: 8)).foregroundStyle(i < photo.rating ? Theme.accent : Theme.muted.opacity(0.5)) }; Spacer(); if photo.adjustments.isEdited { Text("Đã chỉnh").font(.system(size: 9)).foregroundStyle(Theme.accent) } }
                            }.contextMenu {
                                Button("Chỉnh ảnh") { model.select(photo.id); model.libraryMode = false }
                                Button("Tạo bản sao ảo") { model.makeVirtualCopy(photo.id) }
                                Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: photo.path)]) }
                                Button("Bỏ khỏi thư viện", role: .destructive) { model.select(photo.id); model.removeSelected() }
                            }
                        }
                    }
                }
            }
        }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Thumbnail: View {
    @EnvironmentObject var model: AppModel
    let photo: PhotoRecord
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbnail = model.thumbnails[photo.id] { Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { Rectangle().fill(Theme.surface).overlay(Image(systemName: "photo").foregroundStyle(Theme.muted)) }
            if photo.flagged { Image(systemName: "flag.fill").font(.system(size: 9)).padding(5).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3)).padding(3) }
        }
    }
}

struct RatingView: View {
    let rating: Int
    let set: (Int) -> Void
    var body: some View {
        HStack(spacing: 5) { ForEach(1...5, id: \.self) { i in Button { set(rating == i ? 0 : i) } label: { Image(systemName: i <= rating ? "star.fill" : "star").font(.system(size: 10)).foregroundStyle(i <= rating ? Theme.accent : Theme.muted.opacity(0.7)) }.help("\(i) sao · ⌃\(i)") } }
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 15).padding(.vertical, 9).foregroundStyle(Theme.background).background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 5))
    }
}
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 9).background(configuration.isPressed ? Theme.surface : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
    }
}
