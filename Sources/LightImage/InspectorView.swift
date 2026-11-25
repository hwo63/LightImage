import SwiftUI
import LightImageCore

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var lightExpanded = true
    @State private var colorExpanded = true
    @State private var curveExpanded = false
    @State private var mixerExpanded = false
    @State private var detailExpanded = false
    @State private var effectsExpanded = false
    @State private var cropExpanded = false
    @State private var gradingExpanded = false
    @State private var calibrationExpanded = false
    @State private var selectedColor = "Red"
    @State private var confirmSync = false
    private let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PHÒNG CHỈNH ẢNH").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.system(size: 12))
            }.foregroundStyle(Theme.muted).padding(.horizontal, 20).frame(height: 48)
            HistogramView(bins: model.histogram).frame(height: 83).padding(.horizontal, 20)
            HStack { Text("RGB"); Spacer(); Text("sRGB · Xem trước") }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 18)
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Màu sắc").font(.system(size: 11))
                        Spacer()
                        Button("Màu") { model.change("Chế độ màu") { $0.monochrome = false } }.foregroundStyle(model.edits.monochrome ? Theme.muted : Theme.accent)
                        Text("/").foregroundStyle(Theme.muted)
                        Button("Đen trắng") { model.change("Đen trắng") { $0.monochrome = true } }.foregroundStyle(model.edits.monochrome ? Theme.accent : Theme.muted)
                    }.font(.system(size: 10)).padding(20)
                    Button { model.maskSheet = true } label: {
                        HStack {
                            Image(systemName: "circle.lefthalf.filled").frame(width: 16)
                            Text("Chỉnh theo vùng")
                            Spacer()
                            let count = model.edits.localMasks?.count ?? 0
                            if count > 0 { Text("\(count)").foregroundStyle(Theme.muted).monospacedDigit() }
                            Image(systemName: "arrow.up.right").font(.system(size: 9))
                        }.foregroundStyle(Theme.accent).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 20).frame(height: 32)
                    }.padding(.bottom, 8)
                    section("Chân dung", icon: "person.crop.rectangle", expanded: Binding(
                        get: { model.portraitInspectorOpen },
                        set: { model.showPortraitInspector($0) }
                    )) {
                        PortraitControls()
                    }
                    section("Ánh sáng", icon: "sun.max", expanded: $lightExpanded) {
                        Toggle("Tự cân sáng · LightImage", isOn: Binding(get: { model.edits["AutoTone"] > 0 }, set: { enabled in model.change("Tự cân sáng") { $0["AutoTone"] = enabled ? 1 : 0 } }))
                            .font(.system(size: 10)).toggleStyle(.switch).controlSize(.mini)
                            .help("Tự cân sáng theo histogram; kết quả có thể khác AutoTone của Adobe.")
                        AdjustmentSlider(title: "Phơi sáng", key: "Exposure2012", range: -5...5, decimals: 2)
                        AdjustmentSlider(title: "Tương phản", key: "Contrast2012")
                        AdjustmentSlider(title: "Vùng sáng", key: "Highlights2012")
                        AdjustmentSlider(title: "Vùng tối", key: "Shadows2012")
                        AdjustmentSlider(title: "Điểm trắng", key: "Whites2012")
                        AdjustmentSlider(title: "Điểm đen", key: "Blacks2012")
                    }
                    section("Cân bằng trắng & Màu", icon: "thermometer.medium", expanded: $colorExpanded) {
                        if model.edits["Temperature"] > 0 {
                            AdjustmentSlider(title: "Nhiệt độ preset · K", key: "Temperature", range: 2000...50000)
                            Button("Trở về cân bằng trắng ảnh gốc") { model.change("Cân bằng trắng gốc") { $0.values.removeValue(forKey: "Temperature"); $0.values.removeValue(forKey: "Tint") } }.font(.system(size: 9)).foregroundStyle(Theme.accent)
                            AdjustmentSlider(title: "Tint preset", key: "Tint", range: -150...150)
                        }
                        AdjustmentSlider(title: "Nhiệt độ tương đối", key: "IncrementalTemperature", gradient: [.blue, .orange])
                        AdjustmentSlider(title: "Sắc xanh / hồng", key: "IncrementalTint", gradient: [.green, .pink])
                        AdjustmentSlider(title: "Độ rực màu", key: "Vibrance")
                        AdjustmentSlider(title: "Độ bão hòa", key: "Saturation")
                    }
                    section("Đường cong", icon: "point.topleft.down.to.point.bottomright.curvepath", expanded: $curveExpanded) {
                        CurveEditor()
                        AdjustmentSlider(title: "Parametric · Shadows", key: "ParametricShadows")
                        AdjustmentSlider(title: "Parametric · Darks", key: "ParametricDarks")
                        AdjustmentSlider(title: "Parametric · Lights", key: "ParametricLights")
                        AdjustmentSlider(title: "Parametric · Highlights", key: "ParametricHighlights")
                        AdjustmentSlider(title: "Ranh giới tối", key: "ParametricShadowSplit", range: 0...100)
                        AdjustmentSlider(title: "Ranh giới trung gian", key: "ParametricMidtoneSplit", range: 0...100)
                        AdjustmentSlider(title: "Ranh giới sáng", key: "ParametricHighlightSplit", range: 0...100)
                    }
                    section("Bộ trộn màu · HSL", icon: "circle.lefthalf.filled", expanded: $mixerExpanded) {
                        HStack(spacing: 10) {
                            ForEach(Array(PresetParser.colorNames.enumerated()), id: \.element) { index, name in
                                Button { selectedColor = name } label: { Circle().fill(colors[index]).frame(width: 17, height: 17).padding(3).overlay(Circle().stroke(selectedColor == name ? .white : .clear, lineWidth: 1)) }.help(name)
                            }
                        }.padding(.bottom, 8)
                        if model.edits.monochrome { AdjustmentSlider(title: "Độ sáng trắng đen", key: "GrayMixer" + selectedColor) }
                        else {
                            AdjustmentSlider(title: "Sắc độ", key: "HueAdjustment" + selectedColor)
                            AdjustmentSlider(title: "Độ bão hòa", key: "SaturationAdjustment" + selectedColor)
                            AdjustmentSlider(title: "Độ sáng", key: "LuminanceAdjustment" + selectedColor)
                        }
                    }
                    section("Color Grading", icon: "circle.hexagongrid", expanded: $gradingExpanded) { GradingControls() }
                    section("Calibration RGB", icon: "slider.horizontal.3", expanded: $calibrationExpanded) {
                        ForEach(["Red", "Green", "Blue"], id: \.self) { channel in
                            AdjustmentSlider(title: channel + " · Hue", key: channel + "Hue")
                            AdjustmentSlider(title: channel + " · Saturation", key: channel + "Saturation")
                        }
                        AdjustmentSlider(title: "Sắc độ vùng tối", key: "ShadowTint")
                    }
                    section("Chi tiết", icon: "triangle", expanded: $detailExpanded) {
                        AdjustmentSlider(title: "Kết cấu", key: "Texture")
                        AdjustmentSlider(title: "Độ rõ", key: "Clarity2012")
                        AdjustmentSlider(title: "Độ sắc nét", key: "Sharpness", range: 0...150)
                        AdjustmentSlider(title: "Sharpen · Radius", key: "SharpenRadius", range: 0.5...3, decimals: 2)
                        AdjustmentSlider(title: "Sharpen · Detail", key: "SharpenDetail", range: 0...100)
                        AdjustmentSlider(title: "Sharpen · Masking", key: "SharpenEdgeMasking", range: 0...100)
                        AdjustmentSlider(title: "Giảm nhiễu sáng", key: "LuminanceSmoothing", range: 0...100)
                        AdjustmentSlider(title: "Nhiễu sáng · Chi tiết", key: "LuminanceNoiseReductionDetail", range: 0...100)
                        AdjustmentSlider(title: "Nhiễu sáng · Tương phản", key: "LuminanceNoiseReductionContrast", range: 0...100)
                        AdjustmentSlider(title: "Giảm nhiễu màu", key: "ColorNoiseReduction", range: 0...100)
                        AdjustmentSlider(title: "Nhiễu màu · Chi tiết", key: "ColorNoiseReductionDetail", range: 0...100)
                        AdjustmentSlider(title: "Nhiễu màu · Độ mượt", key: "ColorNoiseReductionSmoothness", range: 0...100)
                    }
                    section("Hiệu ứng", icon: "camera.filters", expanded: $effectsExpanded) {
                        AdjustmentSlider(title: "Khử sương · Dehaze", key: "Dehaze")
                        AdjustmentSlider(title: "Tối / sáng góc", key: "PostCropVignetteAmount")
                        if (model.edits.values["PostCropVignetteAmount"] ?? model.edits["VignetteAmount"]) != 0 {
                            AdjustmentSlider(title: "Tâm vùng tối góc", key: "PostCropVignetteMidpoint", range: 0...100)
                            AdjustmentSlider(title: "Độ mềm tối góc", key: "PostCropVignetteFeather", range: 0...100)
                            AdjustmentSlider(title: "Độ tròn tối góc", key: "PostCropVignetteRoundness")
                            AdjustmentSlider(title: "Giữ vùng sáng", key: "PostCropVignetteHighlightContrast", range: 0...100)
                        }
                        AdjustmentSlider(title: "Hạt film", key: "GrainAmount", range: 0...100)
                        if model.edits["GrainAmount"] > 0 {
                            AdjustmentSlider(title: "Kích thước hạt", key: "GrainSize", range: 0...100)
                            AdjustmentSlider(title: "Độ thô hạt", key: "GrainFrequency", range: 0...100)
                        }
                    }
                    section("Cắt & Xoay", icon: "crop.rotate", expanded: $cropExpanded) {
                        HStack {
                            Button { model.change("Xoay trái") { $0.rotation -= 1 } } label: { Label("Trái", systemImage: "rotate.left") }
                            Spacer()
                            Button { model.change("Xoay phải") { $0.rotation += 1 } } label: { Label("Phải", systemImage: "rotate.right") }
                        }.font(.system(size: 11)).foregroundStyle(Theme.accent).padding(.bottom, 10)
                        HStack {
                            Button("Lật ngang") { model.change("Lật ngang") { $0.flipHorizontal = $0.flipHorizontal != true } }
                                .foregroundStyle(model.edits.flipHorizontal == true ? Theme.accent : Theme.muted)
                            Spacer()
                            Button("Lật dọc") { model.change("Lật dọc") { $0.flipVertical = $0.flipVertical != true } }
                                .foregroundStyle(model.edits.flipVertical == true ? Theme.accent : Theme.muted)
                        }.font(.system(size: 11))
                        AdjustmentSlider(title: "Cân thẳng · °", key: "LightImageStraighten", range: -45...45, decimals: 2)
                        Picker("Tỷ lệ", selection: Binding(get: { model.edits.cropAspect }, set: { v in model.change("Tỷ lệ cắt") { $0.cropAspect = v } })) {
                            Text("Ảnh gốc").tag(0.0); Text("1:1").tag(1.0); Text("3:2").tag(1.5); Text("4:3").tag(4.0 / 3); Text("16:9").tag(16.0 / 9); Text("4:5").tag(0.8); Text("9:16").tag(9.0 / 16)
                        }.font(.system(size: 11))
                        AdjustmentSlider(title: "Transform · Scale", key: "PerspectiveScale", range: 50...150)
                        AdjustmentSlider(title: "Transform · X", key: "PerspectiveX")
                        AdjustmentSlider(title: "Transform · Y", key: "PerspectiveY")
                        geometrySlider("Vùng giữ lại", key: \.cropScale, range: 0.2...1)
                        geometrySlider("Vị trí ngang", key: \.cropX, range: 0...1)
                        geometrySlider("Vị trí dọc", key: \.cropY, range: 0...1)
                        Button("Khôi phục khung hình") {
                            model.change("Khôi phục khung") {
                                $0.rotation = 0; $0.cropAspect = 0; $0.cropScale = 1; $0.cropX = 0.5; $0.cropY = 0.5
                                $0.flipHorizontal = nil; $0.flipVertical = nil
                                for key in ["PerspectiveScale", "PerspectiveX", "PerspectiveY", "LightImageStraighten"] {
                                    $0.values.removeValue(forKey: key)
                                }
                            }
                        }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
            }.scrollIndicators(.hidden).disabled(model.selected == nil)
            VStack(spacing: 12) {
                HStack {
                    Button("Khôi phục") { model.reset() }.foregroundStyle(Theme.muted)
                    Spacer()
                    Menu {
                        Button("Sao chép chỉnh sửa") { model.copyBuffer = model.edits }
                        Button("Dán chỉnh sửa") { model.pasteEdits() }.disabled(model.copyBuffer == nil)
                        Button("Đồng bộ cho \(model.photos.count) ảnh đang lọc…") { confirmSync = true }.disabled(model.photos.count < 2)
                    } label: { Label("Đồng bộ", systemImage: "square.on.square") }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(Theme.muted)
                }.font(.system(size: 11))
            }.padding(20).background(Theme.panel).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }.disabled(model.selected == nil)
        }.background(Theme.panel)
            .alert("Đồng bộ chỉnh sửa?", isPresented: $confirmSync) {
                Button("Hủy", role: .cancel) {}
                Button("Đồng bộ") { model.syncVisible() }
            } message: { Text("Đồng bộ màu và khung hình cho \(model.photos.count) ảnh trong bộ lọc. Mặt nạ và chỉnh sửa chân dung được lưu riêng cho từng ảnh. Có thể hoàn tác từng ảnh trong phiên này.") }
    }
    private func section<Content: View>(_ title: String, icon: String, expanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Button { withAnimation(.easeInOut(duration: 0.16)) { expanded.wrappedValue.toggle() } } label: {
                HStack(spacing: 10) { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 16); Text(title).font(.system(size: 12, weight: .medium)); Spacer(); Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.muted) }.padding(.horizontal, 20).frame(height: 44)
            }
            if expanded.wrappedValue { VStack(spacing: 14) { content() }.padding(.horizontal, 20).padding(.bottom, 20) }
        }
    }
    private func geometrySlider(_ name: String, key: WritableKeyPath<Adjustments, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 5) {
            HStack { Text(name); Spacer(); Text("\(Int(model.edits[keyPath: key] * 100))%") }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            Slider(value: Binding(get: { model.edits[keyPath: key] }, set: { model.updateGeometry(key, $0) }), in: range, onEditingChanged: { if !$0 { model.endGesture(name) } }).controlSize(.mini)
        }
    }
}

struct AdjustmentSlider: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let key: String
    var range: ClosedRange<Double> = -100...100
    var decimals = 0
    var gradient: [Color]? = nil
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                Text(model.edits[key] == 0 ? "0" : String(format: decimals == 2 ? "%+.2f" : "%+.0f", model.edits[key]))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(PresetParameters.isNeutral(key, value: model.edits[key], in: model.edits) ? Theme.muted : Theme.accent)
                    .onTapGesture(count: 2) { model.change("Đặt lại \(title)") { $0.values.removeValue(forKey: key) } }
                    .help("Nhấp đúp để đặt lại")
            }.font(.system(size: 10))
            Slider(value: Binding(get: { min(max(model.edits[key], range.lowerBound), range.upperBound) }, set: { model.update(key, $0) }), in: range, onEditingChanged: { if $0 { model.beginGesture() } else { model.endGesture(title) } })
                .controlSize(.mini)
                .background { if let gradient { LinearGradient(colors: gradient.map { $0.opacity(0.4) }, startPoint: .leading, endPoint: .trailing).frame(height: 2).padding(.horizontal, 3) } }
        }
    }
}

struct HistogramView: View {
    let bins: [[Double]]
    var body: some View {
        Canvas { context, size in
            for fraction in [0.25, 0.5, 0.75] {
                var grid = Path(); grid.move(to: CGPoint(x: size.width * fraction, y: 0)); grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                context.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 1)
            }
            for (index, channel) in bins.enumerated() where channel.count > 1 {
                var p = Path(); p.move(to: CGPoint(x: 0, y: size.height))
                for (i, value) in channel.enumerated() { p.addLine(to: CGPoint(x: Double(i) / Double(channel.count - 1) * size.width, y: (1 - value) * size.height)) }
                p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath()
                context.blendMode = .plusLighter
                context.fill(p, with: .color([Color(red: 0.7, green: 0.35, blue: 0.3), Color(red: 0.42, green: 0.67, blue: 0.43), Color(red: 0.35, green: 0.49, blue: 0.72)][index].opacity(0.55)))
            }
        }.background(Theme.background.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityLabel("Biểu đồ phân bố sáng RGB")
    }
}

struct CurveEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var channel = "ToneCurvePV2012"
    private var points: [CurvePoint] { model.edits.curves[channel] ?? [.init(0, 0), .init(0.25, 0.25), .init(0.5, 0.5), .init(0.75, 0.75), .init(1, 1)] }
    private var color: Color { channel.hasSuffix("Red") ? .red : channel.hasSuffix("Green") ? .green : channel.hasSuffix("Blue") ? .blue : Theme.accent }
    var body: some View {
        VStack(spacing: 10) {
            Picker("Kênh", selection: $channel) { Text("RGB").tag("ToneCurvePV2012"); Text("R").tag("ToneCurvePV2012Red"); Text("G").tag("ToneCurvePV2012Green"); Text("B").tag("ToneCurvePV2012Blue") }.pickerStyle(.segmented).labelsHidden()
            GeometryReader { geo in
                Canvas { context, size in
                    for i in 1...3 {
                        let f = CGFloat(i) / 4
                        var path = Path(); path.move(to: .init(x: f * size.width, y: 0)); path.addLine(to: .init(x: f * size.width, y: size.height)); path.move(to: .init(x: 0, y: f * size.height)); path.addLine(to: .init(x: size.width, y: f * size.height))
                        context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
                    }
                    var line = Path(); line.move(to: .init(x: 0, y: size.height)); line.addLine(to: .init(x: size.width, y: 0)); context.stroke(line, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    var curve = Path()
                    for i in 0...256 {
                        let x = Double(i) / 256, y = ImageEngine.curve(x, points)
                        let point = CGPoint(x: x * size.width, y: (1-y) * size.height)
                        if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
                    }
                    context.stroke(curve, with: .color(color), lineWidth: 1.5)
                }
                ForEach(points.indices, id: \.self) { index in
                    Circle().fill(color).frame(width: 8, height: 8).position(x: points[index].x * geo.size.width, y: (1 - points[index].y) * geo.size.height)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("curve"))
                            .onChanged { event in
                                model.beginGesture(); var updated = points
                                let x = min(max(event.location.x / geo.size.width, 0), 1)
                                let y = min(max(1 - event.location.y / geo.size.height, 0), 1)
                                updated[index].y = y
                                if index > 0 && index < points.count - 1 { updated[index].x = min(max(x, points[index - 1].x + 0.01), points[index + 1].x - 0.01) }
                                model.edits.curves[channel] = updated; model.commitCurrent(); model.scheduleRender()
                            }.onEnded { _ in model.endGesture("Đường cong") })
                }
            }.coordinateSpace(name: "curve").frame(height: 190).padding(6).background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
            HStack { Text("Kéo điểm để chỉnh"); Spacer(); Button("Đặt lại") { model.change("Đặt lại đường cong") { $0.curves.removeValue(forKey: channel) } } }.font(.system(size: 9)).foregroundStyle(Theme.muted)
        }
    }
}

struct ExportView: View {
    @EnvironmentObject var model: AppModel
    @State private var format = "jpg"
    @State private var quality = 0.95
    @State private var size = 0.0
    @State private var all = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 13) { Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(Theme.accent); VStack(alignment: .leading, spacing: 4) { Text("Mang bức ảnh ra thế giới").font(.system(size: 22, weight: .light, design: .serif)); Text("Kết xuất từ ảnh gốc với các chỉnh sửa của bạn.").font(.system(size: 11)).foregroundStyle(Theme.muted) } }
            Form {
                Picker("Định dạng", selection: $format) { Text("JPEG · 8-bit").tag("jpg"); Text("PNG · 8-bit").tag("png"); Text("TIFF · 16-bit").tag("tiff") }
                if format == "jpg" { HStack { Text("Chất lượng"); Slider(value: $quality, in: 0.1...1); Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 40) } }
                Picker("Cạnh dài tối đa", selection: $size) { Text("Độ phân giải gốc").tag(0.0); Text("3840 px").tag(3840.0); Text("2560 px").tag(2560.0); Text("2048 px").tag(2048.0); Text("1080 px").tag(1080.0) }
                Toggle("Xuất tất cả \(model.photos.count) ảnh đang lọc", isOn: $all).disabled(model.photos.isEmpty)
            }.formStyle(.grouped).frame(height: format == "jpg" ? 205 : 170)
            Text("Không gian màu sRGB. Không sao chép EXIF/GPS. Xuất hàng loạt tự thêm số nếu trùng tên; ảnh gốc trong thư viện luôn được giữ nguyên.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
            HStack { Button("Hủy") { model.exportSheet = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Chọn nơi lưu & Xuất") { model.export(format: format, quality: quality, maxDimension: size, all: all) }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 500).background(Theme.panel).tint(Theme.accent)
    }
}

struct GradingControls: View {
    @State private var zone = "Shadow"
    private var hue: String { zone == "Shadow" || zone == "Highlight" ? "SplitToning" + zone + "Hue" : "ColorGrade" + zone + "Hue" }
    private var saturation: String { zone == "Shadow" || zone == "Highlight" ? "SplitToning" + zone + "Saturation" : "ColorGrade" + zone + "Sat" }
    var body: some View {
        VStack(spacing: 14) {
            Picker("Vùng màu", selection: $zone) {
                Text("Vùng tối").tag("Shadow"); Text("Trung gian").tag("Midtone")
                Text("Vùng sáng").tag("Highlight"); Text("Toàn ảnh").tag("Global")
            }.font(.system(size: 11))
            AdjustmentSlider(title: "Hue", key: hue, range: 0...360)
            AdjustmentSlider(title: "Saturation", key: saturation, range: 0...100)
            AdjustmentSlider(title: "Luminance", key: "ColorGrade" + zone + "Lum")
            AdjustmentSlider(title: "Blending", key: "ColorGradeBlending", range: 0...100)
            AdjustmentSlider(title: "Balance", key: "SplitToningBalance")
        }
    }
}
