import AppKit
import SwiftUI

struct PhotoPreviewInput: NSViewRepresentable {
    struct Divider {
        let hitArea: CGRect
        let move: (CGPoint) -> Void
    }

    let magnify: (Double, CGPoint) -> Void
    let pan: (CGSize) -> Void
    var divider: Divider?

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.magnify = magnify
        view.pan = pan
        view.divider = divider
    }

    final class InputView: NSView {
        var magnify: ((Double, CGPoint) -> Void)?
        var pan: ((CGSize) -> Void)?
        var divider: Divider?

        private enum Drag {
            case pan(from: CGPoint)
            case divider
        }
        private var drag: Drag?

        override var isFlipped: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            guard drag == nil, event.momentumPhase.isEmpty, event.scrollingDeltaY != 0 else { return }
            let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.15
            let amount = max(-0.35, min(0.35, event.scrollingDeltaY * step))
            magnify?(exp(amount), convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if let divider, divider.hitArea.contains(point) {
                drag = .divider
                divider.move(point)
            } else {
                drag = .pan(from: point)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            switch drag {
            case .pan(let previous):
                drag = .pan(from: point)
                pan?(CGSize(width: point.x - previous.x, height: point.y - previous.y))
            case .divider:
                divider?.move(point)
            case nil:
                break
            }
        }

        override func mouseUp(with event: NSEvent) {
            drag = nil
        }
    }
}
