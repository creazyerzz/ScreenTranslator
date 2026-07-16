import AppKit

@MainActor
final class ResultWindowController: NSWindowController {
    private let originalView = NSTextView()
    private let translatedView = NSTextView()
    private let originalCountLabel = NSTextField(labelWithString: "0 字")
    private let translatedCountLabel = NSTextField(labelWithString: "0 字")

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "翻译结果"
        window.level = .floating
        window.contentMinSize = NSSize(width: 680, height: 440)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(original: String, translated: String) {
        originalView.string = original
        translatedView.string = translated
        originalCountLabel.stringValue = "\(original.count) 字"
        translatedCountLabel.stringValue = "\(translated.count) 字"

        scrollToBeginning(originalView)
        scrollToBeginning(translatedView)

        if window?.isVisible == false {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let comparison = NSStackView()
        comparison.orientation = .horizontal
        comparison.alignment = .height
        comparison.distribution = .fillEqually
        comparison.spacing = 16
        comparison.translatesAutoresizingMaskIntoConstraints = false
        comparison.setContentHuggingPriority(.defaultLow, for: .vertical)
        comparison.addArrangedSubview(
            section(title: "原文", countLabel: originalCountLabel, textView: originalView)
        )
        comparison.addArrangedSubview(
            section(title: "译文", countLabel: translatedCountLabel, textView: translatedView)
        )
        contentView.addSubview(comparison)

        let actions = buttonRow()
        actions.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actions)

        NSLayoutConstraint.activate([
            comparison.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            comparison.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            comparison.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            actions.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            actions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            actions.topAnchor.constraint(equalTo: comparison.bottomAnchor, constant: 14),
            actions.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            comparison.heightAnchor.constraint(greaterThanOrEqualToConstant: 340)
        ])
    }

    private func section(title: String, countLabel: NSTextField, textView: NSTextView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .gravityAreas

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 12)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(countLabel)

        let scroll = configuredScrollView(textView: textView)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(scroll)
        return stack
    }

    private func configuredScrollView(textView: NSTextView) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 360))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        textView.frame = scroll.contentView.bounds
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        scroll.documentView = textView
        return scroll
    }

    private func buttonRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let copyOriginal = button(
            title: "复制原文",
            symbol: "doc.on.doc",
            action: #selector(copyOriginalText)
        )
        let copyTranslated = button(
            title: "复制译文",
            symbol: "doc.on.doc.fill",
            action: #selector(copyTranslation)
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\r"

        row.addArrangedSubview(copyOriginal)
        row.addArrangedSubview(copyTranslated)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(close)
        return row
    }

    private func button(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    private func scrollToBeginning(_ textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    @objc private func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedView.string, forType: .string)
    }

    @objc private func copyOriginalText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(originalView.string, forType: .string)
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
    }
}
