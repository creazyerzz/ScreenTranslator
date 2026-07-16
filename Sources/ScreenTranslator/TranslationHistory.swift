import AppKit
import Foundation

struct TranslationHistoryEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let original: String
    let translated: String
    let model: String
}

@MainActor
final class TranslationHistoryStore {
    static let shared = TranslationHistoryStore()

    private let key = "translationHistory"
    private let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    func entries() -> [TranslationHistoryEntry] {
        let current = load()
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let valid = current
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }

        if valid.count != current.count {
            save(valid)
        }
        return valid
    }

    func add(original: String, translated: String, model: String) {
        var current = entries()
        current.insert(
            TranslationHistoryEntry(
                id: UUID(),
                createdAt: Date(),
                original: original,
                translated: translated,
                model: model
            ),
            at: 0
        )
        save(current)
    }

    func remove(id: UUID) {
        save(entries().filter { $0.id != id })
    }

    func removeAll() {
        save([])
    }

    private func load() -> [TranslationHistoryEntry] {
        guard let data = AppSettings.defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    private func save(_ entries: [TranslationHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        AppSettings.defaults.set(data, forKey: key)
    }
}

@MainActor
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let originalView = NSTextView()
    private let translatedView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var allHistory: [TranslationHistoryEntry] = []
    private var history: [TranslationHistoryEntry] = []

    private let dateColumnID = NSUserInterfaceItemIdentifier("history.date")
    private let modelColumnID = NSUserInterfaceItemIdentifier("history.model")
    private let originalColumnID = NSUserInterfaceItemIdentifier("history.original")
    private let translatedColumnID = NSUserInterfaceItemIdentifier("history.translated")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "翻译历史"
        window.contentMinSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        reload()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索原文或译文"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        contentView.addSubview(searchField)

        let tableScroll = NSScrollView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .bezelBorder

        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = false

        let dateColumn = NSTableColumn(identifier: dateColumnID)
        dateColumn.title = "时间"
        dateColumn.width = 130
        let modelColumn = NSTableColumn(identifier: modelColumnID)
        modelColumn.title = "模型"
        modelColumn.width = 170
        let originalColumn = NSTableColumn(identifier: originalColumnID)
        originalColumn.title = "原文"
        originalColumn.width = 270
        let translatedColumn = NSTableColumn(identifier: translatedColumnID)
        translatedColumn.title = "译文"
        translatedColumn.width = 270
        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(modelColumn)
        tableView.addTableColumn(originalColumn)
        tableView.addTableColumn(translatedColumn)
        tableScroll.documentView = tableView
        contentView.addSubview(tableScroll)

        let detail = NSStackView()
        detail.orientation = .horizontal
        detail.alignment = .height
        detail.distribution = .fillEqually
        detail.spacing = 16
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.addArrangedSubview(textSection(title: "原文", textView: originalView))
        detail.addArrangedSubview(textSection(title: "译文", textView: translatedView))
        contentView.addSubview(detail)

        let actions = actionRow()
        actions.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actions)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            tableScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            tableScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            tableScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            tableScroll.heightAnchor.constraint(equalToConstant: 185),
            detail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            detail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            detail.topAnchor.constraint(equalTo: tableScroll.bottomAnchor, constant: 16),
            detail.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -16),
            detail.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            actions.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            actions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            actions.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    private func textSection(title: String, textView: NSTextView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        textView.frame = scroll.contentView.bounds
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(scroll)
        return stack
    }

    private func actionRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let copyOriginal = NSButton(title: "复制原文", target: self, action: #selector(copyOriginal))
        let copyTranslated = NSButton(title: "复制译文", target: self, action: #selector(copyTranslated))
        statusLabel.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let deleteEntry = NSButton(title: "删除选中", target: self, action: #selector(deleteSelectedEntry))
        deleteEntry.bezelStyle = .texturedRounded
        let clear = NSButton(title: "清空历史", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .texturedRounded
        row.addArrangedSubview(statusLabel)
        row.addArrangedSubview(copyOriginal)
        row.addArrangedSubview(copyTranslated)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(deleteEntry)
        row.addArrangedSubview(clear)
        return row
    }

    private func reload() {
        allHistory = TranslationHistoryStore.shared.entries()
        applyFilter()
    }

    private func applyFilter() {
        let keyword = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            history = allHistory
        } else {
            history = allHistory.filter {
                $0.original.localizedCaseInsensitiveContains(keyword)
                    || $0.translated.localizedCaseInsensitiveContains(keyword)
            }
        }

        tableView.reloadData()
        if history.isEmpty {
            originalView.string = ""
            translatedView.string = ""
            statusLabel.stringValue = keyword.isEmpty
                ? "近 7 天暂无翻译记录"
                : "没有匹配“\(keyword)”的记录"
            return
        }

        statusLabel.stringValue = keyword.isEmpty
            ? "近 7 天共 \(history.count) 条"
            : "匹配 \(history.count) 条（共 \(allHistory.count) 条）"
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showEntry(history[0])
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        applyFilter()
    }

    private func showEntry(_ entry: TranslationHistoryEntry) {
        originalView.string = entry.original
        translatedView.string = entry.translated
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, history.indices.contains(row) else { return nil }
        let entry = history[row]
        let value: String
        switch tableColumn.identifier {
        case dateColumnID:
            value = Self.dateFormatter.string(from: entry.createdAt)
        case modelColumnID:
            value = entry.model
        case originalColumnID:
            value = entry.original.replacingOccurrences(of: "\n", with: " ")
        case translatedColumnID:
            value = entry.translated.replacingOccurrences(of: "\n", with: " ")
        default:
            return nil
        }

        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard history.indices.contains(row) else { return }
        showEntry(history[row])
    }

    @objc private func copyOriginal() {
        copy(originalView.string)
    }

    @objc private func copyTranslated() {
        copy(translatedView.string)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func deleteSelectedEntry() {
        let row = tableView.selectedRow
        guard history.indices.contains(row) else { return }
        TranslationHistoryStore.shared.remove(id: history[row].id)
        reload()
    }

    @objc private func clearHistory() {
        guard allHistory.isEmpty == false else { return }

        let alert = NSAlert()
        alert.messageText = "清空翻译历史？"
        alert.informativeText = "将删除近 7 天的全部 \(allHistory.count) 条记录，此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        TranslationHistoryStore.shared.removeAll()
        searchField.stringValue = ""
        reload()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
