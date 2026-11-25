import SwiftUI
import LightImageCore

struct SplitComparison: View {
    let before: NSImage
    let after: NSImage
    let area: CGSize
    let viewport: MaskViewport
    let input: PhotoPreviewInput

    @State private var divider = 0.5

    var body: some View {
        let rect = viewport.frame
        let visible = rect.intersection(CGRect(origin: .zero, size: area))
        if !visible.isEmpty {
            let boundary = visible.minX + visible.width * divider
            ZStack {
                picture(after, rect: rect)
                picture(before, rect: rect)
                    .mask(alignment: .leading) { Rectangle().frame(width: boundary) }
                Rectangle().fill(.white).frame(width: 1, height: visible.height)
                    .position(x: boundary, y: visible.midY)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.background)
                    .frame(width: 30, height: 30).background(Theme.accent, in: Circle())
                    .position(x: boundary, y: visible.midY)
                HStack {
                    label("Trước")
                    Spacer()
                    label("Sau")
                }
                .padding(10)
                .frame(width: visible.width, height: visible.height, alignment: .top)
                .position(x: visible.midX, y: visible.midY)
            }
            .frame(width: area.width, height: area.height)
            .clipped()
            .overlay {
                PhotoPreviewInput(magnify: input.magnify, pan: input.pan, divider: .init(
                    hitArea: viewport.zoom == 1 ? visible : CGRect(
                        x: boundary - 16, y: visible.minY, width: 32, height: visible.height
                    )
                ) { point in
                    setDivider((point.x - visible.minX) / visible.width)
                })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vạch so sánh trước và sau")
            .accessibilityValue("\(Int(divider * 100))%")
            .accessibilityAdjustableAction { direction in
                if direction == .increment { setDivider(divider + 0.1) }
                else if direction == .decrement { setDivider(divider - 0.1) }
            }
        }
    }

    private func setDivider(_ value: Double) {
        divider = min(max(value, 0.02), 0.98)
    }

    private func picture(_ image: NSImage, rect: CGRect) -> some View {
        ZStack {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: area.width, height: area.height)
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).padding(6)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
    }
}
