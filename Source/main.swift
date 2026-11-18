import AppKit
import ServiceManagement

struct FolderEntry: Codable {
    var path: String
    var visitedAt: Date
    var pinnedAt: Date?
    var isPinned: Bool { pinnedAt != nil }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

final class HistoryStore {
    private(set) var entries: [FolderEntry] = []
    private let file: URL
    var onChange: (() -> Void)?
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KlasorPanosu/history.json")
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode([FolderEntry].self, from: data) {
            entries = saved
        }
    }
    func record(_ path: String) {
        guard path.hasPrefix("/") else { return }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let pinnedAt = entries.first { $0.path == normalized }?.pinnedAt
        entries.removeAll { $0.path == normalized }
        entries.insert(FolderEntry(path: normalized, visitedAt: Date(), pinnedAt: pinnedAt), at: 0)
        sortAndTrim()
        persist()
    }
    func togglePin(_ path: String) {
        guard let index = entries.firstIndex(where: { $0.path == path }) else { return }
        entries[index].pinnedAt = entries[index].isPinned ? nil : Date()
        sortAndTrim()
        persist()
    }
    private func sortAndTrim() {
        entries.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return ($0.pinnedAt ?? $0.visitedAt) > ($1.pinnedAt ?? $1.visitedAt)
        }
        var recentCount = 0
        entries = entries.filter {
            if $0.isPinned { return true }
            recentCount += 1
            return recentCount <= 100
        }
    }
    func remove(_ path: String) { entries.removeAll { $0.path == path }; persist() }
    func clear() { entries.removeAll { !$0.isPinned }; persist() }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            NSLog("Klasör geçmişi kaydedilemedi: %@", error.localizedDescription)
        }
        onChange?()
    }
}

final class FinderObserver {
    var onFolder: ((String) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.wabp.klasorpanosu.finder")
    private var busy = false
    private var denied = false
    private var lastPath: String?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }
    func retry() { denied = false; lastPath = nil; poll(force: true) }
    func resetLastPath() { lastPath = nil }
    private func poll(force: Bool = false) {
        guard !busy, !denied else { return }
        guard force || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        busy = true
        queue.async { [weak self] in
            let source = """
            tell application "Finder"
                if (count of Finder windows) is 0 then return ""
                try
                    return POSIX path of (target of front Finder window as alias)
                on error
                    return ""
                end try
            end tell
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
            let code = error?[NSAppleScript.errorNumber] as? Int
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                if code == -1743 {
                    self.denied = true
                    self.onStatus?("Finder erişimi kapalı. İzinleri açıp tekrar dene.", true)
                    return
                }
                if code != nil {
                    self.onStatus?("Finder okunamadı. Tekrar deneyebilirsin.", true)
                    return
                }
                self.onStatus?("Finder açıkken klasörler otomatik kaydedilir.", false)
                guard let path = result, !path.isEmpty else { self.lastPath = nil; return }
                guard path != self.lastPath else { return }
                self.lastPath = path
                self.onFolder?(path)
            }
        }
    }
}

final class SearchField: NSSearchField {
    var onDown: (() -> Void)?
    var onOpen: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 125 { onDown?(); return true }
        if event.keyCode == 36 { onOpen?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class FolderTable: NSTableView {
    var onOpen: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && rowActionsVisible { rowActionsVisible = false }
        else if event.keyCode == 36 || event.keyCode == 76 { onOpen?() }
        else { super.keyDown(with: event) }
    }
}

final class HoverRow: NSTableRowView {
    private var hoverTracking: NSTrackingArea?
    private var hovered = false {
        didSet {
            if hovered != oldValue { needsDisplay = true }
            updatePinVisibility()
        }
    }
    private func updatePinVisibility() {
        func visit(_ view: NSView) {
            if let pin = view as? PinButton {
                if pin.isHidden == hovered { pin.isHidden = !hovered }
            } else {
                for child in view.subviews { visit(child) }
            }
        }
        visit(self)
    }
    override func layout() {
        super.layout()
        updatePinVisibility()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = hoverTracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
        if let window = window {
            hovered = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else { hovered = false }
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if hovered && !isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
    }
}

final class PinButton: NSButton {
    var onToggle: (() -> Void)?
    init(pinned: Bool, folderName: String) {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        toolTip = pinned ? "Sabitlemeyi kaldır" : "Klasörü sabitle"
        setAccessibilityLabel("\(folderName): \(toolTip!)")
        target = self
        action = #selector(togglePin)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func togglePin() { onToggle?() }
}

final class PanelController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let store: HistoryStore
    let observer: FinderObserver
    let search = SearchField()
    let table = FolderTable()
    private let status = NSTextField(wrappingLabelWithString: "Finder’da bir klasör açarak başlayabilirsin.")
    private let empty = NSTextField(wrappingLabelWithString: "Henüz klasör yok\nFinder’da açtığın klasörler burada görünecek.")
    private let permission = NSButton(title: "İzinler", target: nil, action: nil)
    private let retry = NSButton(title: "Tekrar dene", target: nil, action: nil)
    private var visible: [FolderEntry] = []
    var onClose: (() -> Void)?

    init(store: HistoryStore, observer: FinderObserver) {
        self.store = store; self.observer = observer
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 520))
        let title = NSTextField(labelWithString: "Klasör Panosu")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        search.placeholderString = "Klasör adı veya yol ara"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.onDown = { [weak self] in
            guard let self = self, !self.visible.isEmpty else { return }
            self.view.window?.makeFirstResponder(self.table)
            self.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        search.onOpen = { [weak self] in self?.openSelected() }
        table.headerView = nil
        table.rowHeight = 54
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.style = .fullWidth
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.frame = NSRect(x: 0, y: 0, width: 404, height: 350)
        table.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.width = 404
        table.addTableColumn(column)
        table.delegate = self; table.dataSource = self
        table.target = self; table.action = #selector(clicked)
        table.onOpen = { [weak self] in self?.openSelected() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        empty.alignment = .center; empty.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize: 13)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        permission.target = self; permission.action = #selector(openPermissions)
        retry.target = self; retry.action = #selector(retryPermission)
        permission.isHidden = true; retry.isHidden = true
        let clear = NSButton(title: "Geçmişi temizle", target: self, action: #selector(clearHistory))
        let quit = NSButton(title: "Çıkış", target: self, action: #selector(quitApp))
        for item in [title, search, scroll, empty, status, permission, retry, clear, quit] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            search.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            search.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(equalToConstant: 340),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: clear.topAnchor, constant: -12),
            clear.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            clear.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            quit.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            quit.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            permission.leadingAnchor.constraint(equalTo: clear.trailingAnchor, constant: 4),
            permission.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            retry.leadingAnchor.constraint(equalTo: permission.trailingAnchor, constant: 4),
            retry.centerYAnchor.constraint(equalTo: clear.centerYAnchor)
        ])
        reload()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        table.sizeLastColumnToFit()
    }
    func prepare() {
        search.stringValue = ""
        reload()
        DispatchQueue.main.async { self.view.window?.makeFirstResponder(self.search) }
    }
    func setStatus(_ message: String, needsPermission: Bool) {
        loadViewIfNeeded()
        status.stringValue = message
        permission.isHidden = !needsPermission; retry.isHidden = !needsPermission
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) { search.onDown?(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { openSelected(); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { onClose?(); return true }
        return false
    }
    func reload() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = store.entries.filter { query.isEmpty || $0.path.localizedStandardContains(query) }
        table.rowActionsVisible = false
        table.reloadData()
        empty.isHidden = !visible.isEmpty
        empty.stringValue = query.isEmpty ? "Henüz klasör yok\nFinder’da açtığın klasörler burada görünecek." : "Eşleşen klasör bulunamadı."
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing, visible.indices.contains(row) else { return [] }
        let path = visible[row].path
        let action = NSTableViewRowAction(style: .destructive, title: "Sil") { [weak self] _, _ in
            tableView.rowActionsVisible = false
            self?.store.remove(path)
        }
        action.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Listeden kaldır")
        return [action]
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { HoverRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = visible[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Klasör")
        icon.contentTintColor = .systemBlue
        let title = NSTextField(labelWithString: entry.name.isEmpty ? "/" : entry.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let displayPath = entry.path == home ? "~" : (entry.path.hasPrefix(home + "/") ? "~" + entry.path.dropFirst(home.count) : entry.path)
        let path = NSTextField(labelWithString: displayPath)
        path.font = .systemFont(ofSize: 11); path.textColor = .secondaryLabelColor
        path.alphaValue = 0.5
        path.lineBreakMode = .byTruncatingMiddle
        cell.toolTip = entry.path
        let pin = PinButton(pinned: entry.isPinned, folderName: entry.name)
        pin.isHidden = true
        pin.onToggle = { [weak self] in self?.store.togglePin(entry.path) }
        for item in [icon, title, path, pin] { item.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(item) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26), icon.heightAnchor.constraint(equalToConstant: 26),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: pin.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
            path.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            path.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            path.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            pin.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            pin.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 28),
            pin.heightAnchor.constraint(equalToConstant: 28)
        ])
        return cell
    }
    @objc private func clicked() { if table.clickedRow >= 0 { open(row: table.clickedRow) } }
    func openSelected() { open(row: table.selectedRow >= 0 ? table.selectedRow : 0) }
    private func open(row: Int) {
        guard visible.indices.contains(row) else { return }
        let entry = visible[row]
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &directory), directory.boolValue else {
            let alert = NSAlert()
            alert.messageText = "Klasöre ulaşılamıyor"
            alert.informativeText = "Klasör taşınmış veya silinmiş olabilir. Harici diskteyse diski bağla.\n\n" + entry.path
            alert.runModal(); return
        }
        if NSWorkspace.shared.open(URL(fileURLWithPath: entry.path)) {
            store.record(entry.path)
            onClose?()
        }
    }
    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
    @objc private func retryPermission() { observer.retry() }
    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Klasör geçmişi temizlensin mi?"
        alert.informativeText = "Sabitlenmemiş klasörler listeden kaldırılır. Sabitlediklerin korunur; klasörlerin silinmez."
        alert.addButton(withTitle: "Temizle"); alert.addButton(withTitle: "Vazgeç")
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = HistoryStore()
    private let observer = FinderObserver()
    private var panel: PanelController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "folder.badge.clock", accessibilityDescription: "Klasör Panosu")
            ?? NSImage(systemSymbolName: "folder", accessibilityDescription: "Klasör Panosu")
        statusItem.button?.toolTip = "Klasör Panosu — son açılan klasörler"
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        panel = PanelController(store: store, observer: observer)
        popover.contentViewController = panel
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        panel.onClose = { [weak self] in self?.popover.performClose(nil) }
        store.onChange = { [weak self] in self?.panel.reload() }
        observer.onFolder = { [weak self] path in self?.store.record(path) }
        observer.onStatus = { [weak self] text, denied in self?.panel.setStatus(text, needsPermission: denied) }
        observer.start()
    }
    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            panel.prepare()
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = dir.appendingPathComponent("history.json")
    let history = HistoryStore(file: file)
    history.record("/tmp/a/"); history.record("/tmp/b"); history.record("/tmp/a")
    precondition(history.entries.map(\.path) == ["/tmp/a", "/tmp/b"])
    precondition(HistoryStore(file: file).entries.count == 2)
    for i in 0..<120 { history.record("/tmp/folder-\(i)") }
    precondition(history.entries.count == 100)
    history.clear()
    precondition(HistoryStore(file: file).entries.isEmpty)
    // Older histories omit pinnedAt; decoding must preserve them.
    let legacy = Data("[{\"path\":\"/tmp/legacy\",\"visitedAt\":0}]".utf8)
    try! legacy.write(to: file)
    let migrated = HistoryStore(file: file)
    precondition(migrated.entries.count == 1 && !migrated.entries[0].isPinned)
    migrated.togglePin("/tmp/legacy")
    for i in 0..<120 { migrated.record("/tmp/new-\(i)") }
    precondition(migrated.entries.count == 101 && migrated.entries[0].path == "/tmp/legacy")
    migrated.record("/tmp/legacy")
    precondition(HistoryStore(file: file).entries[0].isPinned)
    migrated.clear()
    precondition(migrated.entries.count == 1 && migrated.entries[0].isPinned)
    migrated.togglePin("/tmp/legacy")
    precondition(!HistoryStore(file: file).entries[0].isPinned)
    migrated.clear()
    precondition(migrated.entries.isEmpty)
    migrated.record("/tmp/keep")
    migrated.record("/tmp/remove")
    migrated.togglePin("/tmp/remove")
    migrated.remove("/tmp/remove")
    precondition(HistoryStore(file: file).entries.map(\.path) == ["/tmp/keep"])
    try? FileManager.default.removeItem(at: dir)
    print("PASS: normalization, recency, deduplication, persistence, limit, clear, legacy migration, pin persistence, pin protection, unpin, individual removal")
} else if CommandLine.arguments.contains("--enable-login") {
    do {
        if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval { try SMAppService.mainApp.register() }
        switch SMAppService.mainApp.status {
        case .enabled: print("LOGIN_ENABLED")
        case .requiresApproval: print("LOGIN_REQUIRES_APPROVAL")
        case .notRegistered: print("LOGIN_NOT_REGISTERED")
        case .notFound: print("LOGIN_NOT_FOUND")
        @unknown default: print("LOGIN_UNKNOWN")
        }
    } catch { fputs("Login registration failed: \(error)\n", stderr); exit(1) }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
