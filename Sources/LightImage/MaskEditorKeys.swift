import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Handles brush and pan shortcuts before a focused control consumes them. The
/// monitor only handles events for the window hosting this editor sheet.
struct MaskEditorKeys: NSViewRepresentable {
    enum StrokeHistoryAction { case undo, redo }

    @Binding var spaceHeld: Bool
    let cancelBrushStroke: () -> Bool
    let changeStrokeHistory: (StrokeHistoryAction) -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        configure(view)
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        configure(view)
    }

    private func configure(_ view: KeyView) {
        view.updateSpaceHeld = { spaceHeld = $0 }
        view.cancelBrushStroke = cancelBrushStroke
        view.changeStrokeHistory = changeStrokeHistory
    }

    static func dismantleNSView(_ view: KeyView, coordinator: ()) {
        view.stop()
    }

    final class KeyView: NSView {
        var updateSpaceHeld: ((Bool) -> Void)?
        var cancelBrushStroke: (() -> Bool)?
        var changeStrokeHistory: ((StrokeHistoryAction) -> Void)?
        private static let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?
        private var spacePressed = false
        private var escapePressed = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.releaseKeys()
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self, weak window] event in
                guard let self, let window, window.isKeyWindow, event.window === window else { return event }
                switch Int(event.keyCode) {
                case kVK_Space: return self.handleSpace(event, in: window)
                case kVK_Escape: return self.handleEscape(event)
                default: return self.handleStrokeHistory(event)
                }
            }
        }

        private func handleSpace(_ event: NSEvent, in window: NSWindow) -> NSEvent? {
            if event.type == .keyUp {
                guard spacePressed else { return event }
                releaseSpace()
                return nil
            }
            if spacePressed { return nil }
            guard isUnmodifiedPress(event), !(window.firstResponder is NSTextView) else { return event }
            spacePressed = true
            updateSpaceHeld?(true)
            return nil
        }

        private func handleEscape(_ event: NSEvent) -> NSEvent? {
            if event.type == .keyUp {
                guard escapePressed else { return event }
                escapePressed = false
                return nil
            }
            if escapePressed { return nil }
            guard isUnmodifiedPress(event), cancelBrushStroke?() == true else { return event }
            escapePressed = true
            return nil
        }

        private func isUnmodifiedPress(_ event: NSEvent) -> Bool {
            event.modifierFlags.intersection(Self.shortcutModifiers).isEmpty && !event.isARepeat
        }

        private func handleStrokeHistory(_ event: NSEvent) -> NSEvent? {
            guard event.type == .keyDown, event.charactersIgnoringModifiers?.lowercased() == "z" else { return event }
            let modifiers = event.modifierFlags.intersection(Self.shortcutModifiers)
            let action: StrokeHistoryAction
            switch modifiers {
            case .command: action = .undo
            case [.command, .shift]: action = .redo
            default: return event
            }
            if !event.isARepeat { changeStrokeHistory?(action) }
            // Even with an empty stroke history, keep the sheet's shortcuts scoped to the mask.
            return nil
        }

        private func releaseSpace() {
            guard spacePressed else { return }
            spacePressed = false
            updateSpaceHeld?(false)
        }

        private func releaseKeys() {
            releaseSpace()
            escapePressed = false
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            monitor = nil
            resignObserver = nil
            releaseKeys()
        }
    }
}
