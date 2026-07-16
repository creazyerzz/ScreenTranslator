import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var settingsWindow: SettingsWindowController?
    private var historyWindow: HistoryWindowController?
    private var resultWindow: ResultWindowController?
    private var overlayWindow: CaptureOverlayWindow?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var menuActionTargets: [MenuActionTarget] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureDefaults()
        configureMainMenu()
        configureStatusMenu()
        installHotkeyMonitors()
        _ = TranslationHistoryStore.shared.entries()
    }

    /// 菜单栏应用默认没有主菜单，导致 Cmd+C/V 等编辑快捷键失效，这里补一个隐藏的编辑菜单。
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    private func configureDefaults() {
        AppSettings.defaults.register(defaults: [
            AppSettings.Keys.baseURL: "",
            AppSettings.Keys.model: AppSettings.defaultModel,
            AppSettings.Keys.targetLanguage: "中文",
            AppSettings.Keys.sourceLanguage: "auto",
            AppSettings.Keys.apiKey: "",
            AppSettings.Keys.autoCopyTranslation: false
        ])
    }

    private func configureStatusMenu() {
        statusItem.button?.title = "译"
        statusItem.button?.toolTip = "Screen Translator"

        let menu = NSMenu()
        let captureItem = menuItem(title: "截图翻译", keyEquivalent: "t") { [weak self] in
            self?.beginCapture()
        }
        captureItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(captureItem)
        menu.addItem(menuItem(title: "显示上次结果", keyEquivalent: "r") { [weak self] in
            self?.showLastResult()
        })
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "设置", keyEquivalent: ",") { [weak self] in
            self?.openSettings()
        })
        menu.addItem(menuItem(title: "翻译历史", keyEquivalent: "h") { [weak self] in
            self?.openHistory()
        })
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "退出", keyEquivalent: "q") {
            NSApplication.shared.terminate(nil)
        })
        statusItem.menu = menu
    }

    private func installHotkeyMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.isARepeat == false else {
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            guard isCaptureHotkey(flags: flags, key: key) else {
                return
            }
            DispatchQueue.main.async {
                self?.beginCapture()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.isARepeat == false else {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            guard isCaptureHotkey(flags: flags, key: key) else {
                return event
            }
            self?.beginCapture()
            return nil
        }
    }

    private func menuItem(title: String, keyEquivalent: String, action: @escaping @MainActor @Sendable () -> Void) -> NSMenuItem {
        let target = MenuActionTarget(action: action)
        menuActionTargets.append(target)

        let item = NSMenuItem(
            title: title,
            action: #selector(MenuActionTarget.handleScreenTranslatorMenuItem(_:)),
            keyEquivalent: keyEquivalent
        )
        item.target = target
        return item
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.show()
    }

    private func showLastResult() {
        guard let resultWindow else {
            showAlert(title: "暂无结果", message: "本次启动后还没有翻译记录，可先用快捷键或菜单发起截图翻译。")
            return
        }
        resultWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindowController()
        }
        historyWindow?.show()
    }

    private func beginCapture() {
        guard overlayWindow == nil else {
            return
        }

        guard AppSettings.shared.baseURL.isEmpty == false,
              AppSettings.shared.apiKey.isEmpty == false else {
            openSettings()
            showAlert(title: "需要完成配置", message: "请先在设置里填写 API 地址和 API Key 并保存。")
            return
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            showAlert(
                title: "需要屏幕录制权限",
                message: "请在系统设置的隐私与安全性中允许 Screen Translator 或当前终端录制屏幕，然后重新启动应用。"
            )
            return
        }

        guard let screen = NSScreen.screenContainingMouse() ?? NSScreen.main else {
            showAlert(title: "无法截图", message: "没有找到可用屏幕。")
            return
        }

        overlayWindow = CaptureOverlayWindow(screen: screen) { [weak self] image in
            Task { @MainActor in
                self?.overlayWindow = nil
                self?.processCapturedImage(image)
            }
        } onCancel: { [weak self] in
            self?.overlayWindow = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow?.makeKeyAndOrderFront(nil)
        if let overlay = overlayWindow, let contentView = overlay.contentView {
            overlay.makeFirstResponder(contentView)
        }
    }

    private func processCapturedImage(_ image: CGImage) {
        setStatusBusy(true)
        showResult(.recognizing)

        OCRService.recognize(image: image) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let text):
                    guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                        self?.setStatusBusy(false)
                        self?.showResult(.failure(original: "", message: "没有识别到文字，请尝试放大内容后重新框选。"))
                        return
                    }
                    self?.translate(text)
                case .failure(let error):
                    self?.setStatusBusy(false)
                    self?.showResult(.failure(original: "", message: "OCR 失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    private func translate(_ text: String) {
        setStatusBusy(true)
        showResult(.translating(original: text))
        TranslatorClient(settings: .shared).translate(text: text) { [weak self] result in
            Task { @MainActor in
                self?.setStatusBusy(false)
                switch result {
                case .success(let translated):
                    TranslationHistoryStore.shared.add(
                        original: text,
                        translated: translated,
                        model: AppSettings.shared.model
                    )
                    self?.showResult(.success(original: text, translated: translated))
                case .failure(let error):
                    self?.showResult(.failure(original: text, message: "翻译失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    private func setStatusBusy(_ busy: Bool) {
        statusItem.button?.title = busy ? "…" : "译"
        statusItem.button?.appearsDisabled = busy
    }

    private func showResult(_ state: ResultWindowController.DisplayState) {
        if resultWindow == nil {
            let controller = ResultWindowController()
            controller.onRetranslate = { [weak self] original in
                self?.translate(original)
            }
            resultWindow = controller
        }
        resultWindow?.apply(state: state)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@objc(ScreenTranslatorMenuActionTarget)
private final class MenuActionTarget: NSObject {
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    @objc(screenTranslatorHandleMenuItem:)
    func handleScreenTranslatorMenuItem(_ sender: NSMenuItem) {
        let action = action
        Task { @MainActor in
            action()
        }
    }
}

private func isCaptureHotkey(flags: NSEvent.ModifierFlags, key: String?) -> Bool {
    flags.contains(.control) && flags.contains(.option) && key == "t"
}

private extension NSScreen {
    static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
