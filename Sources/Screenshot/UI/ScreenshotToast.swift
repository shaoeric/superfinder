import AppKit
import QuartzCore

/// Small non-interactive confirmation shown above the screenshot overlay.
/// The fade is a one-shot Core Animation; there is no timer or polling.
final class ScreenshotToast: NSPanel {
    static let shared = ScreenshotToast()

    private let container = NSView()
    private let label = NSTextField(labelWithString: "")

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.86).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        container.layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7)
        ])
        contentView = container
        orderOut(nil)
    }

    func show(_ message: String, near rect: CGRect, on screen: NSScreen?) {
        label.stringValue = message
        container.layoutSubtreeIfNeeded()
        let fitting = container.fittingSize
        setContentSize(CGSize(width: max(104, fitting.width), height: max(28, fitting.height)))

        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? rect
        var x = rect.midX - frame.width / 2
        var y = rect.minY - frame.height - 8
        if y < visible.minY + 6 {
            y = rect.maxY + 8
        }
        x = min(max(x, visible.minX + 6), visible.maxX - frame.width - 6)
        y = min(max(y, visible.minY + 6), visible.maxY - frame.height - 6)
        setFrameOrigin(CGPoint(x: x, y: y))

        contentView?.layer?.removeAnimation(forKey: "toastFade")
        contentView?.layer?.opacity = 1
        alphaValue = 1
        orderFrontRegardless()

        guard let layer = contentView?.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.beginTime = CACurrentMediaTime() + 0.9
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "toastFade")
    }

    func hide() {
        contentView?.layer?.removeAnimation(forKey: "toastFade")
        contentView?.layer?.opacity = 1
        orderOut(nil)
    }
}
