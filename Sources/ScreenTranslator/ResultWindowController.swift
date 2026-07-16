import AppKit

@MainActor
final class ResultWindowController: NSWindowController {
    enum DisplayState {
        case recognizing
        case translating(original: String)
        case success(original: String, translated: String)
        case failure(original: String, message: String)
    }

    var onRetranslate: ((String) -> Void)?

    private let originalView = NSTextView()
    private let translatedView = NSTextView()
    private let originalCountLabel = NSTextField(labelWithString: "0 字")
    private let translatedCountLabel = NSTextField(labelWithString: "0 字")
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyTranslatedButton: NSButton
    private let copyOriginalButton: NSButton
    private let retranslateButton: NSButton
    private var copyFeedbackTask: Task<Void, Never>?
    private var currentOriginal = ""

    init() {
        copyTranslatedButton = NSButton(title: "复制译文", target: nil, action: nil)
        copyOriginalButton = NSButton(title: "复制原文", target: nil, action: nil)
        retranslateButton = NSButton(title: "重新翻译", target: nil, action: nil)

        let window = KeyClosablePanel(
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

    func apply(state: DisplayState) {
        switch state {
        case .recognizing:
            currentOriginal = ""
            setTexts(original: "", translated: "")
            setBusy(true, status: "正在识别文字...")
            retranslateButton.isEnabled = false
        case .translating(let original):
            currentOriginal = original
            setTexts(original: original, translated: "")
            setBusy(true, status: "正在翻译...")
            retranslateButton.isEnabled = false
        case .success(let original, let translated):
            currentOriginal = original
            setTexts(original: original, translated: translated)
            setBusy(false, status: "")
            retranslateButton.isEnabled = original.isEmpty == false
            if AppSettings.shared.autoCopyTranslation, translated.isEmpty == false {
                copyToPasteboard(translated)
                flashStatus("译文已自动复制到剪贴板")
            }
        case .failure(let original, let message):
            currentOriginal = original
            setTexts(original: original, translated: message)
            setBusy(false, status: "")
            retranslateButton.isEnabled = original.isEmpty == false
        }
        presentWindow()
    }

    private func setTexts(original: String, translated: String) {
        originalView.string = original
        translatedView.string = translated
        originalCountLabel.stringValue = "\(original.count) 字"
        translatedCountLabel.stringValue = "\(translated.count) 字"
        scrollToBeginning(originalView)
        scrollToBeginning(translatedView)
    }

    private func setBusy(_ busy: Bool, status: String) {
        statusLabel.stringValue = status
        if busy {
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
        copyTranslatedButton.isEnabled = busy == false
        copyOriginalButton.isEnabled = busy == false
    }

    private func presentWindow() {
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

        configure(
            button: copyOriginalButton,
            symbol: "doc.on.doc",
            action: #selector(copyOriginalText)
        )
        configure(
            button: copyTranslatedButton,
            symbol: "doc.on.doc.fill",
            action: #selector(copyTranslation)
        )
        configure(
            button: retranslateButton,
            symbol: "arrow.clockwise",
            action: #selector(retranslate)
        )
        retranslateButton.toolTip = "使用当前设置重新翻译原文"

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\r"

        row.addArrangedSubview(copyOriginalButton)
        row.addArrangedSubview(copyTranslatedButton)
        row.addArrangedSubview(retranslateButton)
        row.addArrangedSubview(spinner)
        row.addArrangedSubview(statusLabel)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(close)
        return row
    }

    private func configure(button: NSButton, symbol: String, action: Selector) {
        button.target = self
        button.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title)
        button.imagePosition = .imageLeading
    }

    private func scrollToBeginning(_ textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func flashStatus(_ message: String) {
        copyFeedbackTask?.cancel()
        statusLabel.stringValue = message
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard Task.isCancelled == false else { return }
            self?.statusLabel.stringValue = ""
        }
    }

    @objc private func copyTranslation() {
        copyToPasteboard(translatedView.string)
        flashStatus("译文已复制")
    }

    @objc private func copyOriginalText() {
        copyToPasteboard(originalView.string)
        flashStatus("原文已复制")
    }

    @objc private func retranslate() {
        guard currentOriginal.isEmpty == false else { return }
        onRetranslate?(currentOriginal)
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
    }
}

/// 按 Esc 可直接关闭的浮动面板。
@MainActor
final class KeyClosablePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
