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
    private enum Phase {
        case idle
        case dragging
        case selected
    }

    private let screen: NSScreen
    private let onCapture: (CGImage) -> Void
    private let onCancel: () -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var phase: Phase = .idle
    private var isCompleting = false

    private let confirmButton = NSButton(title: "翻译", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    init(screen: NSScreen, onCapture: @escaping (CGImage) -> Void, onCancel: @escaping () -> Void) {
        self.screen = screen
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func configureButtons() {
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "翻译")
        confirmButton.imagePosition = .imageLeading
        confirmButton.isHidden = true

        cancelButton.target = self
        cancelButton.action = #selector(cancelFromButton)
        cancelButton.bezelStyle = .rounded
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "取消")
        cancelButton.imagePosition = .imageLeading
        cancelButton.isHidden = true

        addSubview(confirmButton)
        addSubview(cancelButton)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            cancel()
        case 36, 76: // Return / Enter
            if phase == .selected {
                confirmSelection()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        cancel()
    }

    override func mouseDown(with event: NSEvent) {
        guard isCompleting == false else { return }
        // 点击到按钮时交给按钮处理
        let point = convert(event.locationInWindow, from: nil)
        if confirmButton.isHidden == false,
           confirmButton.frame.contains(point) || cancelButton.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }

        hideActionButtons()
        phase = .dragging
        startPoint = boundedPoint(from: event)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard phase == .dragging, isCompleting == false else { return }
        currentPoint = boundedPoint(from: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard phase == .dragging, isCompleting == false else { return }
        currentPoint = boundedPoint(from: event)
        let selection = normalizedSelection()
        guard selection.width > 6, selection.height > 6 else {
            // 无效框选：回到初始状态，等待重新拖选
            phase = .idle
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        phase = .selected
        showActionButtons(around: selection)
        needsDisplay = true
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

        if phase == .selected {
            drawConfirmHint(selection)
        }
    }

    private func drawInstruction() {
        let text = "拖动选择要翻译的屏幕区域，按 Esc 或右键取消"
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

    private func drawConfirmHint(_ selection: NSRect) {
        let text = "回车确认翻译，重新拖动可调整选区"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let size = text.size(withAttributes: attributes)
        let x = min(max(selection.minX, bounds.minX + 4), bounds.maxX - size.width - 4)
        let y = min(selection.maxY + 34, bounds.maxY - size.height - 4)
        text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    private func showActionButtons(around selection: NSRect) {
        confirmButton.sizeToFit()
        cancelButton.sizeToFit()

        let spacing: CGFloat = 8
        let totalWidth = confirmButton.frame.width + spacing + cancelButton.frame.width
        let buttonHeight = max(confirmButton.frame.height, cancelButton.frame.height)

        // 优先放在选区下方右对齐，放不下则放上方
        var x = selection.maxX - totalWidth
        x = min(max(x, bounds.minX + 8), bounds.maxX - totalWidth - 8)
        var y = selection.minY - buttonHeight - 10
        if y < bounds.minY + 8 {
            y = min(selection.maxY + 10, bounds.maxY - buttonHeight - 8)
        }

        cancelButton.setFrameOrigin(NSPoint(x: x, y: y))
        confirmButton.setFrameOrigin(NSPoint(x: x + cancelButton.frame.width + spacing, y: y))
        cancelButton.isHidden = false
        confirmButton.isHidden = false
        window?.makeFirstResponder(self)
    }

    private func hideActionButtons() {
        confirmButton.isHidden = true
        cancelButton.isHidden = true
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
        let preferredY = selection.maxY + 6
        let y = preferredY <= bounds.maxY - badgeSize.height - 4
            ? preferredY
            : max(selection.minY - badgeSize.height - 6, bounds.minY + 4)
        let badgeRect = NSRect(origin: NSPoint(x: x, y: y), size: badgeSize)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
        text.draw(
            at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 3),
            withAttributes: attributes
        )
    }

    @objc private func confirmSelection() {
        guard phase == .selected, isCompleting == false else { return }
        let selection = normalizedSelection()
        guard selection.width > 6, selection.height > 6 else { return }

        isCompleting = true
        hideActionButtons()
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

    @objc private func cancelFromButton() {
        cancel()
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
