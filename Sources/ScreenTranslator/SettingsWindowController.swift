import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let baseURLField = NSTextField()
    private let modelPopup = NSPopUpButton()
    private let targetLanguageField = NSTextField()
    private let apiKeyField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var modelRequest: URLSessionDataTask?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
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

        stack.addArrangedSubview(row(label: "API 地址", field: baseURLField))
        modelPopup.addItems(withTitles: AppSettings.fallbackModels)
        modelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let refreshModelsButton = NSButton(title: "", target: self, action: #selector(refreshModels))
        refreshModelsButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新模型列表"
        )
        refreshModelsButton.bezelStyle = NSButton.BezelStyle.texturedRounded
        refreshModelsButton.toolTip = "从当前 API 刷新模型列表"
        refreshModelsButton.setContentHuggingPriority(
            NSLayoutConstraint.Priority.required,
            for: NSLayoutConstraint.Orientation.horizontal
        )

        let modelControls = NSStackView(views: [modelPopup, refreshModelsButton])
        modelControls.orientation = .horizontal
        modelControls.alignment = .centerY
        modelControls.spacing = 8
        stack.addArrangedSubview(row(label: "模型", control: modelControls))
        stack.addArrangedSubview(row(label: "目标语言", field: targetLanguageField))
        stack.addArrangedSubview(row(label: "API Key", field: apiKeyField))
        apiKeyField.placeholderString = "sk-..."

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(statusLabel)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas

        let hint = NSTextField(labelWithString: "快捷键：Control + Option + T")
        hint.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded

        buttonRow.addArrangedSubview(hint)
        buttonRow.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func row(label: String, field: NSTextField) -> NSView {
        row(label: label, control: field)
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

    private func loadValues() {
        let settings = AppSettings.shared
        baseURLField.stringValue = settings.baseURL
        modelPopup.selectItem(withTitle: settings.model)
        targetLanguageField.stringValue = settings.targetLanguage
        apiKeyField.stringValue = settings.apiKey
    }

    @objc private func save() {
        let settings = AppSettings.shared
        settings.baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.model = modelPopup.selectedItem?.title ?? AppSettings.defaultModel
        settings.targetLanguage = targetLanguageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        settings.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = "已保存。API Key 将以明文保存在本机应用配置中。"
    }

    @objc private func refreshModels() {
        loadAvailableModels()
    }

    private func loadAvailableModels() {
        modelRequest?.cancel()

        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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

        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: uniqueModels)
        modelPopup.selectItem(withTitle: settings.model)
        if let remoteCount {
            statusLabel.stringValue = "已加载 \(uniqueModels.count) 个模型，接口返回 \(remoteCount) 个。"
        } else {
            statusLabel.stringValue = "接口未返回完整模型列表，已使用内置模型列表。"
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
