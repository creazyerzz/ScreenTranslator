import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let baseURLField = NSTextField()
    private let modelCombo = NSComboBox()
    private let targetLanguageCombo = NSComboBox()
    private let apiKeySecureField = NSSecureTextField()
    private let apiKeyPlainField = NSTextField()
    private let revealKeyButton = NSButton()
    private let autoCopyCheckbox = NSButton(checkboxWithTitle: "翻译完成后自动复制译文", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton()
    private let testSpinner = NSProgressIndicator()
    private var modelRequest: URLSessionDataTask?
    private var isKeyRevealed = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screen Translator 设置"
        window.center()
        super.init(window: window)
        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        loadValues()
        loadAvailableModels()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        stack.addArrangedSubview(row(label: "API 地址", control: baseURLField))
        baseURLField.placeholderString = "https://example.com/v1/chat/completions"

        modelCombo.usesDataSource = false
        modelCombo.addItems(withObjectValues: AppSettings.fallbackModels)
        modelCombo.completes = true
        modelCombo.toolTip = "可以直接输入模型名，也可以从下拉列表选择"
        modelCombo.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let refreshModelsButton = NSButton(title: "", target: self, action: #selector(refreshModels))
        refreshModelsButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新模型列表"
        )
        refreshModelsButton.bezelStyle = .texturedRounded
        refreshModelsButton.toolTip = "从当前 API 刷新模型列表"
        refreshModelsButton.setContentHuggingPriority(.required, for: .horizontal)

        let modelControls = NSStackView(views: [modelCombo, refreshModelsButton])
        modelControls.orientation = .horizontal
        modelControls.alignment = .centerY
        modelControls.spacing = 8
        stack.addArrangedSubview(row(label: "模型", control: modelControls))

        targetLanguageCombo.usesDataSource = false
        targetLanguageCombo.addItems(withObjectValues: AppSettings.commonTargetLanguages)
        targetLanguageCombo.completes = true
        targetLanguageCombo.toolTip = "可从列表选择，也可以直接输入任意语言"
        stack.addArrangedSubview(row(label: "目标语言", control: targetLanguageCombo))

        apiKeySecureField.placeholderString = "sk-..."
        apiKeyPlainField.placeholderString = "sk-..."
        apiKeyPlainField.isHidden = true

        revealKeyButton.target = self
        revealKeyButton.action = #selector(toggleKeyVisibility)
        revealKeyButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "显示 API Key")
        revealKeyButton.bezelStyle = .texturedRounded
        revealKeyButton.toolTip = "显示 / 隐藏 API Key"
        revealKeyButton.setContentHuggingPriority(.required, for: .horizontal)

        let keyControls = NSStackView(views: [apiKeySecureField, apiKeyPlainField, revealKeyButton])
        keyControls.orientation = .horizontal
        keyControls.alignment = .centerY
        keyControls.spacing = 8
        stack.addArrangedSubview(row(label: "API Key", control: keyControls))

        autoCopyCheckbox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(row(label: "", control: autoCopyCheckbox))

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(statusLabel)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let hint = NSTextField(labelWithString: "快捷键：Control + Option + T")
        hint.textColor = .secondaryLabelColor

        testSpinner.style = .spinning
        testSpinner.controlSize = .small
        testSpinner.isHidden = true

        testButton.title = "测试连接"
        testButton.target = self
        testButton.action = #selector(testConnection)
        testButton.bezelStyle = .rounded
        testButton.toolTip = "用当前填写的地址、模型和 Key 发送一次试翻译"

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        buttonRow.addArrangedSubview(hint)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(testSpinner)
        buttonRow.addArrangedSubview(testButton)
        buttonRow.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func row(label: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 70).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(control)
        return row
    }

    private var apiKeyValue: String {
        get { isKeyRevealed ? apiKeyPlainField.stringValue : apiKeySecureField.stringValue }
        set {
            apiKeySecureField.stringValue = newValue
            apiKeyPlainField.stringValue = newValue
        }
    }

    @objc private func toggleKeyVisibility() {
        let current = apiKeyValue
        isKeyRevealed.toggle()
        apiKeyValue = current
        apiKeySecureField.isHidden = isKeyRevealed
        apiKeyPlainField.isHidden = isKeyRevealed == false
        revealKeyButton.image = NSImage(
            systemSymbolName: isKeyRevealed ? "eye.slash" : "eye",
            accessibilityDescription: isKeyRevealed ? "隐藏 API Key" : "显示 API Key"
        )
    }

    private func loadValues() {
        let settings = AppSettings.shared
        baseURLField.stringValue = settings.baseURL
        modelCombo.stringValue = settings.model
        targetLanguageCombo.stringValue = settings.targetLanguage
        apiKeyValue = settings.apiKey
        autoCopyCheckbox.state = settings.autoCopyTranslation ? .on : .off
    }

    private var modelValue: String {
        let trimmed = modelCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettings.defaultModel : trimmed
    }

    @objc private func save() {
        let settings = AppSettings.shared
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetLanguage = targetLanguageCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard baseURL.isEmpty == false, URL(string: baseURL)?.host != nil else {
            showStatus("API 地址无效，请检查后再保存。", isError: true)
            return
        }
        guard targetLanguage.isEmpty == false else {
            showStatus("目标语言不能为空。", isError: true)
            return
        }

        settings.baseURL = baseURL
        settings.model = modelValue
        settings.targetLanguage = targetLanguage
        settings.apiKey = apiKey
        settings.autoCopyTranslation = autoCopyCheckbox.state == .on
        showStatus("已保存。API Key 以明文保存在本机应用配置中。", isError: false)
    }

    @objc private func testConnection() {
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseURL.isEmpty == false, apiKey.isEmpty == false else {
            showStatus("请先填写 API 地址和 API Key。", isError: true)
            return
        }

        // 用当前填写值构造临时配置测试，不影响已保存配置
        let config = TranslatorConfig(
            baseURL: baseURL,
            model: modelValue,
            apiKey: apiKey,
            targetLanguage: targetLanguageCombo.stringValue.isEmpty ? "中文" : targetLanguageCombo.stringValue
        )

        setTesting(true)
        showStatus("正在测试连接...", isError: false)
        TranslatorClient(config: config).translate(text: "Hello") { [weak self] result in
            Task { @MainActor in
                self?.setTesting(false)
                switch result {
                case .success:
                    self?.showStatus("连接成功，接口工作正常。", isError: false)
                case .failure(let error):
                    self?.showStatus("连接失败：\(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    private func setTesting(_ testing: Bool) {
        testButton.isEnabled = testing == false
        if testing {
            testSpinner.isHidden = false
            testSpinner.startAnimation(nil)
        } else {
            testSpinner.stopAnimation(nil)
            testSpinner.isHidden = true
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    @objc private func refreshModels() {
        loadAvailableModels()
    }

    private func loadAvailableModels() {
        modelRequest?.cancel()

        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let modelsURL = modelsURL(from: baseURL), apiKey.isEmpty == false else {
            applyModels(AppSettings.fallbackModels)
            return
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        modelRequest = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil, let data else {
                Task { @MainActor in
                    self?.applyModels(AppSettings.fallbackModels)
                }
                return
            }

            let ids = (try? JSONDecoder().decode(ModelsResponse.self, from: data))?.data.map(\.id) ?? []
            Task { @MainActor in
                if ids.isEmpty {
                    self?.applyModels(AppSettings.fallbackModels)
                } else {
                    self?.applyModels(ids, remoteCount: ids.count)
                }
            }
        }
        modelRequest?.resume()
    }

    private func applyModels(_ models: [String], remoteCount: Int? = nil) {
        let settings = AppSettings.shared
        let allModels = models + AppSettings.fallbackModels
        var uniqueModels = allModels.reduce(into: [String]()) { result, model in
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false, result.contains(trimmed) == false {
                result.append(trimmed)
            }
        }

        if uniqueModels.contains(settings.model) == false {
            uniqueModels.insert(settings.model, at: 0)
        }

        let currentInput = modelCombo.stringValue
        modelCombo.removeAllItems()
        modelCombo.addItems(withObjectValues: uniqueModels)
        modelCombo.stringValue = currentInput.isEmpty ? settings.model : currentInput
        if let remoteCount {
            showStatus("已加载 \(uniqueModels.count) 个模型，接口返回 \(remoteCount) 个。", isError: false)
        } else {
            showStatus("接口未返回完整模型列表，已使用内置模型列表。", isError: false)
        }
    }

    private func modelsURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil
        else {
            return nil
        }

        let chatSuffix = "/chat/completions"
        if components.path.hasSuffix(chatSuffix) {
            components.path = String(components.path.dropLast(chatSuffix.count)) + "/models"
        } else {
            components.path = "/v1/models"
        }
        return components.url
    }
}

private struct ModelsResponse: Decodable {
    let data: [ModelEntry]

    struct ModelEntry: Decodable {
        let id: String
    }
}
