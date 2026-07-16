import AppKit
import CoreGraphics

@MainActor
final class CaptureOverlayWindow: NSWindow {
    init(
        screen: NSScreen,
        onCapture: @escaping (CGImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlay = CaptureOverlayView(screen: screen) { [weak self] image in
            self?.orderOut(nil)
            onCapture(image)
        } onCancel: { [weak self] in
            self?.orderOut(nil)
            onCancel()
        }
        contentView = overlay
        initialFirstResponder = overlay
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { true }
}

@MainActor
final class CaptureOverlayView: NSView {
    private let screen: NSScreen
    private let onCapture: (CGImage) -> Void
    private let onCancel: () -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isCompleting = false

    init(screen: NSScreen, onCapture: @escaping (CGImage) -> Void, onCancel: @escaping () -> Void) {
        self.screen = screen
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isCompleting == false else { return }
        startPoint = boundedPoint(from: event)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil, isCompleting == false else { return }
        currentPoint = boundedPoint(from: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil, isCompleting == false else { return }
        currentPoint = boundedPoint(from: event)
        let selection = normalizedSelection()
        guard selection.width > 6, selection.height > 6 else {
            cancel()
            return
        }

        isCompleting = true
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            if let image = self.capture(selection: selection) {
                self.onCapture(image)
            } else {
                self.onCancel()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        let selection = normalizedSelection()
        guard selection.width > 0, selection.height > 0 else {
            drawInstruction()
            return
        }

        NSColor.clear.setFill()
        selection.fill(using: .clear)

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 2
        path.stroke()

        drawSelectionSize(selection)
    }

    private func drawInstruction() {
        let text = "拖动选择要翻译的屏幕区域，按 Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attributes)
    }

    private func normalizedSelection() -> CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let width = abs(startPoint.x - currentPoint.x)
        let height = abs(startPoint.y - currentPoint.y)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func boundedPoint(from event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func drawSelectionSize(_ selection: CGRect) {
        let text = "\(Int(selection.width)) x \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let badgeSize = NSSize(width: textSize.width + 12, height: textSize.height + 6)
        let x = min(max(selection.minX, bounds.minX + 4), bounds.maxX - badgeSize.width - 4)
        let preferredY = selection.minY - badgeSize.height - 6
        let y = preferredY >= bounds.minY + 4
            ? preferredY
            : min(selection.maxY + 6, bounds.maxY - badgeSize.height - 4)
        let badgeRect = NSRect(origin: NSPoint(x: x, y: y), size: badgeSize)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
        text.draw(
            at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 3),
            withAttributes: attributes
        )
    }

    private func cancel() {
        guard isCompleting == false else { return }
        isCompleting = true
        onCancel()
    }

    private func capture(selection: CGRect) -> CGImage? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let backingScale = screen.backingScaleFactor
        let displayRect = CGRect(
            x: selection.minX * backingScale,
            y: (screen.frame.height - selection.maxY) * backingScale,
            width: selection.width * backingScale,
            height: selection.height * backingScale
        )

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        return CGDisplayCreateImage(displayID, rect: displayRect)
    }
}
