import AppKit
import FMClipCore
import SwiftUI
import UniformTypeIdentifiers

/// The state of the main window. All calls come on the main thread (the watcher timer runs on the main run loop).
final class AppModel: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var folders: [String] = []
    /// The folders that show their entries. The app keeps this set between launches.
    @Published var expandedFolders: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(expandedFolders).sorted(), forKey: Self.expandedKey)
            dropHiddenSelection()
        }
    }
    /// The folder row that the user clicked last: Rename Folder and Delete Folder in the File menu act on it.
    @Published var selectedFolder: String? { didSet { if selectedFolder != nil { selectedNoFolder = false } } }
    /// True when the user clicked the group row "No Folder" last.
    @Published var selectedNoFolder = false
    @Published var filter: FMClass? { didSet { dropHiddenSelection() } }
    @Published var search = "" { didSet { dropHiddenSelection() } }
    /// The selected entries (one or more). An entry selection clears the folder selection, so that only entry rows show
    /// as selected.
    @Published private(set) var listSelection = ListSelection() {
        didSet {
            if !listSelection.isEmpty {
                selectedFolder = nil
                selectedNoFolder = false
            }
        }
    }

    /// The one selected entry id: nil when no entry or more than one entry is selected. Set it to select one entry.
    var selection: HistoryEntry.ID? {
        get { listSelection.single }
        set { if let id = newValue { listSelection.select(id) } else { listSelection.clear() } }
    }

    /// The ids of the visible entries, in the order of the tree.
    var visibleIDs: [HistoryEntry.ID] { filtered.map(\.id) }

    /// The selected entries that the list shows, in the order of the tree.
    var selectedEntries: [HistoryEntry] { filtered.filter { listSelection.ids.contains($0.id) } }

    func isSelected(_ id: HistoryEntry.ID) -> Bool { listSelection.ids.contains(id) }

    /// A click on an entry row: Cmd toggles the entry, Shift selects a range, else only this entry.
    func click(_ id: HistoryEntry.ID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            listSelection.toggle(id, order: visibleIDs)
        } else if modifiers.contains(.shift) {
            listSelection.extend(to: id, order: visibleIDs)
        } else {
            listSelection.select(id)
        }
    }

    // MARK: - Context menu of an entry row (the Finder rule)

    /// The entry row under the mouse pointer. The mouse monitor in ContentView reads it on a right-click.
    var hoveredEntry: HistoryEntry.ID?

    /// A right-click (or Control-click) on an entry row. If the row is in the selection, the selection does not
    /// change, and the context menu acts on all the selected entries. If not, only this row is selected first.
    func contextClick(_ id: HistoryEntry.ID) {
        if !listSelection.ids.contains(id) { listSelection.select(id) }
    }

    /// The entries that the context menu of this row acts on: the selection if the row is in it, else the row only.
    func contextTargets(for id: HistoryEntry.ID) -> [HistoryEntry] {
        isSelected(id) ? selectedEntries : filtered.filter { $0.id == id }
    }

    /// True when the context menu of this row acts on more than one entry. Then Copy, Rename and Save As are disabled.
    func contextActsOnMany(_ id: HistoryEntry.ID) -> Bool { contextTargets(for: id).count > 1 }

    /// The title of Delete in the context menu of this row: "Delete" for one entry, "Delete 6 Entries…" for more.
    func contextDeleteTitle(for id: HistoryEntry.ID) -> String {
        let n = contextTargets(for: id).count
        return n > 1 ? "Delete \(n) Entries…" : "Delete"
    }

    /// Delete in the context menu: deletes the entries of the menu. With more than one, the sheet asks first.
    func contextDelete(_ id: HistoryEntry.ID) {
        contextClick(id)
        deleteSelected()
    }

    /// Move to Folder in the context menu: moves all the entries of the menu.
    func contextMove(_ id: HistoryEntry.ID, to folder: String?) {
        contextClick(id)
        moveSelected(to: folder)
    }

    /// New Folder in the Move to Folder menu: the entries of the menu go to the new folder.
    func contextNewFolder(_ id: HistoryEntry.ID) {
        contextClick(id)
        startNewFolder(moveSelected: true)
    }

    /// Copy, Rename and Save As in the context menu act on one entry only.
    func contextCopy(_ id: HistoryEntry.ID) {
        contextClick(id)
        guard !contextActsOnMany(id) else { return }
        copySelected()
    }

    func contextRename(_ id: HistoryEntry.ID) {
        contextClick(id)
        guard !contextActsOnMany(id) else { return }
        startRename()
    }

    func contextSave(_ id: HistoryEntry.ID) {
        contextClick(id)
        guard !contextActsOnMany(id) else { return }
        saveSelected()
    }

    /// Up or Down; with Shift the selection grows or shrinks.
    func moveSelection(by step: Int, extend: Bool) {
        listSelection.move(by: step, extend: extend, order: visibleIDs)
    }

    /// The view that takes the keyboard focus for the list (ListKeyView in ContentView).
    weak var listKeyView: NSView?

    /// Gives the keyboard focus to the list (not to the search field), so that Cmd+A, Edit > Select All, Delete and
    /// Edit > Delete act on the entries.
    func focusList() {
        guard let view = listKeyView, let window = view.window else { return }
        if window.firstResponder !== view { window.makeFirstResponder(view) }
    }

    /// Cmd+A in the list: selects all the visible entries (not the folder rows).
    func selectAll() {
        listSelection.selectAll(order: visibleIDs)
    }

    /// The undo manager of the window (ContentView sets it). Delete registers an Undo with it.
    weak var undoManager: UndoManager?

    /// The group "No Folder" is open (the default) or closed. The app keeps it between launches.
    @Published var noFolderExpanded: Bool {
        didSet {
            UserDefaults.standard.set(!noFolderExpanded, forKey: Self.noFolderCollapsedKey)
            dropHiddenSelection()
        }
    }

    private static let expandedKey = "expandedFolders"
    private static let noFolderCollapsedKey = "noFolderCollapsed"
    @Published var errorMessage: String?
    @Published var showXML = false
    /// The settings from `settings.json` (see AppSettings.swift). The app reloads them when the file changes.
    @Published var settings = ClipSettings() { didSet { if settings.appearance != oldValue.appearance { applyAppearance() } } }
    /// True for the real app. Tests do not change the appearance of the process.
    private(set) var appliesAppearance = false

    private(set) var store: HistoryStore?
    private var watcher: ClipboardWatcher?
    private var textCache: [String: String] = [:]
    private var summaryCache: [String: String?] = [:]
    private var xmlCache: [String: NSAttributedString] = [:]
    /// The generation of the history that this model loaded (`HistoryStore.generation`). A Replace, also by the CLI,
    /// writes a new one: then the Undo actions and the caches belong to the old history.
    private var loadedGeneration: String?

    /// - Parameters:
    ///   - store: the history; nil opens the history of the app. Tests give a store in a temporary folder.
    ///   - watch: watch the clipboard and the history folder. Tests use false.
    /// The history folder of the `-HistoryFolder PATH` launch argument (the `HistoryFolder` user default), or nil.
    /// Tests and demos use it, so that the app does not open the real history. The window shows it in a footer note.
    static let historyFolderOverride = HistoryStore.folder(
        override: UserDefaults.standard.string(forKey: HistoryStore.folderOverrideKey))

    /// The history folder that the app opens: the override, else the default folder.
    static var appHistoryFolder: URL { historyFolderOverride ?? HistoryStore.defaultFolder }

    /// The override folder when this model uses it (the app), for the footer note and the About panel. Nil in tests.
    private(set) var historyOverride: URL?

    init(store: HistoryStore? = nil, watch: Bool = true) {
        expandedFolders = Set(UserDefaults.standard.stringArray(forKey: Self.expandedKey) ?? [])
        noFolderExpanded = !UserDefaults.standard.bool(forKey: Self.noFolderCollapsedKey)
        do {
            if store == nil { historyOverride = Self.historyFolderOverride }
            let store = try store ?? HistoryStore(folder: Self.appHistoryFolder)
            self.store = store
            entries = store.entries
            folders = store.folders
            settings = store.settings
            loadedGeneration = store.generation
        } catch {
            errorMessage = "Cannot open the history in \((store?.folder ?? Self.appHistoryFolder).path): \(error.localizedDescription)"
            return
        }
        guard watch else { return }
        appliesAppearance = true
        applyAppearance()
        let watcher = ClipboardWatcher(onOther: { [weak self] in self?.store?.forgetRestore() }) { [weak self] objects in
            self?.capture(objects)
        }
        watcher.start()
        self.watcher = watcher
        // Another process (fm-object-clip-cli, or a second app) can change the history. Then reload it.
        folderWatcher = HistoryFolderWatcher(folder: self.store?.folder ?? Self.appHistoryFolder) { [weak self] in self?.reloadFromDisk() }
    }

    private var folderWatcher: HistoryFolderWatcher?

    /// Reads the history again after a change on disk. The selection stays if its entry is still in the list.
    /// A folder that another process made starts expanded.
    func reloadFromDisk() {
        guard let store else { return }
        let before = Set(folders)
        do { try store.reload() } catch { return }  // a half-written file can not occur (atomic writes); try at the next change
        let generation = store.generation
        if generation != loadedGeneration {
            // The history was replaced (by this app or by the CLI). An Undo of an earlier change must not act on the
            // new history, and an id can have other XML now.
            loadedGeneration = generation
            undoManager?.removeAllActions()
            clearCaches()
        }
        let newSettings = store.settings
        if newSettings != settings { settings = newSettings }
        guard store.entries != entries || store.folders != folders else { return }
        refresh()
        expandNewFolders(since: before)
    }

    /// True while a type filter or a search is active. Then the tree shows only the folders with a match, expanded.
    var isFiltering: Bool {
        filter != nil || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True if the entry matches the class filter and the search text (name, title or XML).
    func matches(_ e: HistoryEntry) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return (filter == nil || e.cls == filter)
            && (query.isEmpty || e.displayTitle.localizedCaseInsensitiveContains(query)
                || e.title.localizedCaseInsensitiveContains(query) || text(for: e).localizedCaseInsensitiveContains(query))
    }

    /// The rows of the list: folders with their entries, then the entries in no folder.
    var rows: [TreeRow] {
        HistoryTree.rows(entries: entries, folders: folders, expanded: expandedFolders, noFolderExpanded: noFolderExpanded,
                         active: isFiltering, matches: matches)
    }

    /// The entries that the list shows now, in the order of the list.
    var filtered: [HistoryEntry] {
        rows.compactMap(\.entry)
    }

    /// Removes the selected entries that the list does not show, for example after a search or a collapse.
    private func dropHiddenSelection() {
        guard !listSelection.isEmpty else { return }
        var pruned = listSelection
        pruned.prune(visible: visibleIDs)
        if pruned != listSelection { listSelection = pruned }
    }

    func toggleFolder(_ name: String) {
        if expandedFolders.contains(name) { expandedFolders.remove(name) } else { expandedFolders.insert(name) }
    }

    /// The selected entry, only if the list shows it.
    var selected: HistoryEntry? {
        selection.flatMap { id in filtered.first { $0.id == id } }
    }

    func text(for entry: HistoryEntry) -> String {
        if let t = textCache[entry.id] { return t }
        let t = (try? store?.data(for: entry)).flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        textCache[entry.id] = t
        return t
    }

    /// The readable summary, or nil if the XML does not parse.
    func summary(for entry: HistoryEntry) -> String? {
        if let s = summaryCache[entry.id] { return s }
        let s = data(for: entry).flatMap { Summary.summary(for: entry.cls, data: $0) }
        summaryCache[entry.id] = s
        return s
    }

    /// The XML, indented and colored, for display only. Copy and Save As use the bytes as captured.
    func formattedXML(for entry: HistoryEntry) -> NSAttributedString {
        if let x = xmlCache[entry.id] { return x }
        let x = XMLHighlighter.attributed(XMLFormat.pretty(text(for: entry)))
        xmlCache[entry.id] = x
        return x
    }

    func data(for entry: HistoryEntry) -> Data? {
        try? store?.data(for: entry)
    }

    func capture(_ objects: [FMObject]) {
        guard let store else { return }
        let before = Set(store.folders)
        defer { expandNewFolders(since: before) }
        for obj in objects {
            do {
                try store.add(obj.data, cls: obj.cls, name: obj.name, folder: obj.folder)
                // A copy from FileMaker Pro is kept as it is. If the portal check finds a problem, say so now,
                // because Copy Entry asks before it copies this entry.
                if let message = PortalCheck.message(cls: obj.cls, data: obj.data) {
                    errorMessage = "The app kept the capture, but Copy Entry will ask before it copies it.\n" + message
                }
            } catch { errorMessage = "Cannot keep the capture: \(error.localizedDescription)" }
        }
        refresh()
    }

    /// The entry that shows the "Copied" mark now, for about one second after a copy.
    @Published var copiedID: HistoryEntry.ID?
    private var copiedClear: DispatchWorkItem?

    /// Puts the entry on the clipboard with its class. The watcher ignores this change, so it makes no new entry.
    /// The entry keeps its time and its place, also when FileMaker Pro writes the clipboard again (see RestoreRecord).
    /// For a layout entry with a portal child outside the first portal row (PortalCheck), the app asks first.
    /// The app reads the bytes once. After "Copy Anyway", it copies those bytes with the class of that entry, and
    /// does not read the file again. If the history changed while the question was open (a Replace, a delete, or
    /// other XML for the id), it does not copy, and it says so.
    func copy(_ entry: HistoryEntry, to pasteboard: NSPasteboard = .general) {
        guard let store else { return }
        let data: Data
        do { data = try store.data(for: entry) } catch {
            errorMessage = "Cannot read the entry \(entry.id): \(error.localizedDescription)"
            return
        }
        guard let message = PortalCheck.message(cls: entry.cls, data: data) else { return write(entry, data, to: pasteboard) }
        let generation = store.generation
        askPortalCopy(message) { [weak self] ok in
            guard ok, let self, let store = self.store else { return }
            self.reloadFromDisk()
            guard store.generation == generation, let now = store.entry(id: entry.id),
                  now.cls == entry.cls, now.sha256 == HistoryStore.sha256(data)
            else {
                self.errorMessage = "The history changed while the question was open, so the app did not copy the entry."
                return
            }
            self.write(entry, data, to: pasteboard)
        }
    }

    /// Puts the bytes on the clipboard as the entry. The watcher ignores this change.
    private func write(_ entry: HistoryEntry, _ data: Data, to pasteboard: NSPasteboard) {
        guard let store else { return }
        guard let count = store.copy(entry, data: data, to: pasteboard) else { errorMessage = "The clipboard refused the data."; return }
        watcher?.ignore(changeCount: count)
        showCopied(entry.id)
    }

    /// Asks before a copy of an entry that the portal check refuses, and calls the answer (true: copy).
    /// Nil shows the sheet on the window. Tests set it, because a test can not click a sheet.
    var confirmPortalCopy: ((_ message: String, _ answer: @escaping (Bool) -> Void) -> Void)?

    private func askPortalCopy(_ message: String, answer: @escaping (Bool) -> Void) {
        if let confirmPortalCopy { return confirmPortalCopy(message, answer) }
        let alert = Self.portalCopyAlert(message: message)
        let done = { (response: NSApplication.ModalResponse) in answer(response == .alertSecondButtonReturn) }
        // A sheet, not runModal: a modal loop that starts in the key monitor does not get the keyboard.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }

    /// The question before a copy that the portal check refuses. Cancel is the default button, so Return does not
    /// copy. The second button copies anyway.
    static func portalCopyAlert(message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Copy this layout entry anyway?"
        alert.informativeText = message
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Copy Anyway")
        return alert
    }

    private func showCopied(_ id: HistoryEntry.ID) {
        copiedClear?.cancel()
        copiedID = id
        let clear = DispatchWorkItem { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
        copiedClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: clear)
    }

    /// Reads the history again after a restore from a backup. The caches go: an id can have other XML now.
    func reloadAfterRestore() {
        clearCaches()
        reloadFromDisk()
    }

    private func clearCaches() {
        textCache = [:]
        summaryCache = [:]
        xmlCache = [:]
    }

    /// Forgets the cached text, summary and XML of the entries that are gone or whose bytes changed (another sha256),
    /// so that the window never shows other XML than Copy Entry copies.
    private func dropStaleCaches(old: [HistoryEntry], new: [HistoryEntry]) {
        let now = Dictionary(new.map { ($0.id, $0.sha256) }, uniquingKeysWith: { a, _ in a })
        for e in old where now[e.id] != e.sha256 {
            textCache[e.id] = nil
            summaryCache[e.id] = nil
            xmlCache[e.id] = nil
        }
    }

    func refresh() {
        guard let store else { return }
        dropStaleCaches(old: entries, new: store.entries)
        entries = store.entries
        folders = store.folders
        if let f = selectedFolder, !folders.contains(f) { selectedFolder = nil }
        // Forget the open state of folders that do not exist now (deleted or renamed, also by another process).
        let known = expandedFolders.intersection(folders)
        if known != expandedFolders { expandedFolders = known }
        dropHiddenSelection()
    }

    /// A new folder starts expanded (from --folder, New Folder or Move to Folder).
    private func expandNewFolders(since before: Set<String>) {
        let new = folders.filter { !before.contains($0) }
        if !new.isEmpty { expandedFolders.formUnion(new) }
    }

    /// A dialog with one text field: rename an entry, make a folder, or rename a folder.
    enum Prompt {
        case renameEntry(HistoryEntry)
        case newFolder(moveEntries: [HistoryEntry.ID])
        case renameFolder(String)

        var title: String {
            switch self {
            case .renameEntry: return "Rename Entry"
            case .newFolder: return "New Folder"
            case .renameFolder: return "Rename Folder"
            }
        }

        var button: String {
            switch self {
            case .newFolder: return "Make Folder"
            default: return "Rename"
            }
        }

        var message: String {
            switch self {
            case .renameEntry(let e): return "Leave the name empty to show the automatic title: \(e.title)"
            case .newFolder(let ids):
                switch ids.count {
                case 0: return "Give the folder a name."
                case 1: return "The app moves the selected entry to the new folder."
                default: return "The app moves the \(ids.count) selected entries to the new folder."
                }
            case .renameFolder(let f): return "The entries in \"\(f)\" stay in the folder."
            }
        }
    }

    @Published var prompt: Prompt?
    @Published var promptText = ""

    /// Opens the Rename dialog for the selected entry.
    func startRename() {
        guard let entry = selected else { return }
        promptText = entry.name ?? ""
        prompt = .renameEntry(entry)
    }

    /// Opens the New Folder dialog. With moveSelected, the selected entry goes to the new folder.
    func startNewFolder(moveSelected: Bool = false) {
        promptText = ""
        prompt = .newFolder(moveEntries: moveSelected ? selectedEntries.map(\.id) : [])
    }

    func startRenameFolder(_ name: String) {
        promptText = name
        prompt = .renameFolder(name)
    }

    /// Does the action of the dialog with the text in its field.
    func finishPrompt() {
        guard let store, let prompt else { return }
        self.prompt = nil
        let before = Set(store.folders)
        defer { expandNewFolders(since: before) }
        do {
            switch prompt {
            case .renameEntry(let entry):
                try store.rename(id: entry.id, to: promptText)  // an empty name gives the automatic title again
            case .newFolder(let ids):
                let folder = try store.makeFolder(promptText)
                if !ids.isEmpty {
                    try store.move(ids: ids, to: folder)
                    expandedFolders.insert(folder)
                }
            case .renameFolder(let old):
                try store.renameFolder(old, to: promptText)
                let new = store.existingFolder(promptText) ?? old
                if expandedFolders.contains(old) { expandedFolders.remove(old); expandedFolders.insert(new) }
                if selectedFolder == old { selectedFolder = new }
                refresh()
                return
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Deletes the folder. Its entries stay in the history, in no folder.
    func deleteFolder(_ name: String) {
        guard let store else { return }
        do { try store.deleteFolder(name) } catch { errorMessage = error.localizedDescription }
        expandedFolders.remove(name)
        if selectedFolder == name { selectedFolder = nil }
        refresh()
    }

    /// Moves a folder to a new position in the list (0 is the first). Its entries stay in it.
    /// Edit > Undo (Cmd+Z) puts the folder back at its old position.
    func moveFolder(_ name: String, to index: Int) {
        guard let store, let from = store.folders.firstIndex(of: name) else { return }
        do { try store.moveFolder(name, to: index) } catch { errorMessage = error.localizedDescription }
        refresh()
        guard let to = folders.firstIndex(of: name), to != from else { return }
        undoManager?.registerUndo(withTarget: self) { model in model.moveFolder(name, to: from) }
        undoManager?.setActionName("Move Folder")
    }

    /// True when the selected folder can move one place up (offset -1) or down (offset 1): File > Move Folder Up/Down.
    func canMoveSelectedFolder(by offset: Int) -> Bool {
        guard let f = selectedFolder, let i = folders.firstIndex(of: f) else { return false }
        return folders.indices.contains(i + offset)
    }

    /// Moves the selected folder one place up (offset -1) or down (offset 1), with Undo.
    func moveSelectedFolder(by offset: Int) {
        guard canMoveSelectedFolder(by: offset), let f = selectedFolder, let i = folders.firstIndex(of: f) else { return }
        moveFolder(f, to: i + offset)
    }

    /// Moves an entry to a folder, or to no folder (nil).
    func move(_ id: HistoryEntry.ID, to folder: String?) {
        guard let store else { return }
        let before = Set(store.folders)
        do { try store.move(id: id, to: folder) } catch { errorMessage = error.localizedDescription }
        refresh()
        expandNewFolders(since: before)
    }

    func count(in folder: String) -> Int {
        entries.filter { $0.folder == folder }.count
    }

    func copySelected() {
        if let e = selected { copy(e) }
    }

    /// Deletes one entry. Edit > Undo (Cmd+Z) puts it back.
    func delete(_ id: HistoryEntry.ID) {
        delete(ids: [id])
    }

    /// Deletes the entries in one change. Edit > Undo (Cmd+Z) puts them all back in one step, with their names,
    /// folders and bytes.
    func delete(ids: [HistoryEntry.ID]) {
        guard let store, !ids.isEmpty else { return }
        let items: [(HistoryEntry, Data)] = ids.compactMap { id in
            guard let e = store.entry(id: id), let data = try? store.data(for: e) else { return nil }
            return (e, data)
        }
        do { try store.delete(ids: ids) } catch { errorMessage = "Cannot delete: \(error.localizedDescription)" }
        for id in ids {
            textCache[id] = nil
            summaryCache[id] = nil
            xmlCache[id] = nil
        }
        refresh()
        if !items.isEmpty, let undoManager {
            undoManager.registerUndo(withTarget: self) { model in model.undelete(items) }
            undoManager.setActionName(Self.deleteActionName(items.map(\.0)))
        }
    }

    /// Puts deleted entries back (Undo of Delete) and selects them. Redo deletes them again.
    func undelete(_ items: [(HistoryEntry, Data)]) {
        guard let store else { return }
        do { try store.insert(items) } catch { errorMessage = "Cannot put the entries back: \(error.localizedDescription)" }
        refresh()
        for (entry, _) in items {
            if let folder = entry.folder { expandedFolders.insert(folder) } else { noFolderExpanded = true }
        }
        let ids = Set(items.map(\.0.id))
        listSelection.selectAll(order: visibleIDs.filter { ids.contains($0) })
        let entries = items.map(\.0)
        undoManager?.registerUndo(withTarget: self) { model in model.delete(ids: entries.map(\.id)) }
        undoManager?.setActionName(Self.deleteActionName(entries))
    }

    static func deleteActionName(_ entries: [HistoryEntry]) -> String {
        entries.count == 1 ? "Delete “\(entries[0].displayTitle)”" : "Delete \(entries.count) Entries"
    }

    /// Left Arrow: closes the group of the selected entry (and selects the group row), or the selected group.
    func collapseCurrentGroup() {
        guard !isFiltering else { return }
        if let entry = selected {
            selection = nil
            if let f = entry.folder, folders.contains(f) {
                selectedFolder = f
                expandedFolders.remove(f)
            } else {
                selectedNoFolder = true
                noFolderExpanded = false
            }
        } else if let f = selectedFolder {
            expandedFolders.remove(f)
        } else if selectedNoFolder {
            noFolderExpanded = false
        }
    }

    /// Right Arrow: opens the selected group.
    func expandCurrentGroup() {
        guard !isFiltering else { return }
        if let f = selectedFolder { expandedFolders.insert(f) } else if selectedNoFolder { noFolderExpanded = true }
    }

    /// True when the File menu Delete and the Delete key can delete: at least one selected entry is in the list.
    var canDeleteSelection: Bool { !selectedEntries.isEmpty }

    /// The title of File > Delete: "Delete" for one entry, "Delete 6 Entries…" for more.
    var deleteMenuTitle: String {
        let n = selectedEntries.count
        return n > 1 ? "Delete \(n) Entries…" : "Delete"
    }

    /// Asks before a bulk delete and calls the answer (true: delete). Nil shows the sheet on the window.
    /// Tests set it, because a test can not click a sheet.
    var confirmBulkDelete: ((_ count: Int, _ answer: @escaping (Bool) -> Void) -> Void)?

    /// Deletes the selected entries. With more than one, the app asks first ("Delete 12 entries?") in a sheet on the window.
    func deleteSelected() {
        let ids = selectedEntries.map(\.id)
        guard !ids.isEmpty else { return }
        guard ids.count > 1 else { return delete(ids: ids) }
        if let confirmBulkDelete {
            confirmBulkDelete(ids.count) { [weak self] ok in if ok { self?.delete(ids: ids) } }
            return
        }
        let alert = Self.bulkDeleteAlert(count: ids.count)
        let confirm = { [weak self] (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { self?.delete(ids: ids) }
        }
        // A sheet, not runModal: a modal loop that starts in the key monitor does not get the keyboard.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: confirm)
        } else {
            confirm(alert.runModal())
        }
    }

    /// The question before a bulk delete. The first button (Delete) is the default button: Return deletes, and Undo
    /// puts the entries back. Escape cancels. Do not set hasDestructiveAction: on macOS 26 a destructive button can
    /// not be the default button, and then Return did nothing (the bug "delete does not work after Cmd+A").
    static func bulkDeleteAlert(count: Int) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Delete \(count) entries?"
        alert.informativeText = "To put them back, select Edit > Undo (Cmd+Z)."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert
    }

    /// Moves the selected entries to a folder, or to no folder (nil).
    func moveSelected(to folder: String?) {
        guard let store else { return }
        let ids = selectedEntries.map(\.id)
        guard !ids.isEmpty else { return }
        let before = Set(store.folders)
        do { try store.move(ids: ids, to: folder) } catch { errorMessage = error.localizedDescription }
        refresh()
        expandNewFolders(since: before)
        if let folder = store.existingFolder(folder ?? "") { expandedFolders.insert(folder) } else if folder == nil { noFolderExpanded = true }
        listSelection.selectAll(order: visibleIDs.filter { ids.contains($0) })
    }

    /// Saves the XML of the entry to a file that the user selects.
    func saveSelected() {
        guard let entry = selected, let data = data(for: entry) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        let name = entry.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = String(name.prefix(80)) + ".xml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) } catch { errorMessage = "Cannot save the file: \(error.localizedDescription)" }
    }

    func showAbout() {
        var credits = "A history of the FileMaker Pro objects on the clipboard."
        if let historyOverride { credits += "\n\nHistory folder (-HistoryFolder): \(historyOverride.path)" }
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "fm-object-clip",
            .credits: NSAttributedString(string: credits,
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/solutionscay/fm-object-clip/wiki")!)
    }
}
