import AppKit
import FMClipCore

// fm-object-clip-cli: read and manage the fm-object-clip history. Safe while the app runs: each change locks the
// history and reads the latest files first, and the app reloads when the files change.

let usage = """
fm-object-clip-cli: read and manage the fm-object-clip history of FileMaker objects.

Usage: fm-object-clip-cli [--history DIR] [--json] COMMAND [ARGS]

Read commands:
  list [--folder NAME | --no-folder] [--class C] [--search TEXT] [--limit N]
                              the entries, newest first
  show ID                     the data of one entry
  xml ID                      the stored XML bytes of the entry, to stdout
  folders                     the folders and the number of entries in each
  info                        the FileMaker objects on the clipboard now

Write commands:
  add FILE.xml --class C [--name NAME] [--folder NAME] [--force]
                              add an entry from a file (same rules as a capture: the same class
                              and XML gives no new entry, it updates the name and the folder);
                              XML2 with a portal child outside the first row stops, unless --force
  restore ID [--force]        put the entry on the clipboard, with its class (then Cmd+V in FileMaker);
                              the same portal check as add, unless --force
  rename ID NAME              give the entry a name; NAME "" gives the automatic title again
  move ID FOLDER              move the entry to the folder (made if necessary)
  move ID --no-folder         take the entry out of its folder
  delete ID [ID ...]          delete the entries (all the IDs must exist, else nothing is deleted)
  folder new NAME             make a folder
  folder rename OLD NEW       rename a folder; its entries go with it
  folder delete NAME          delete a folder; its entries go to the uncategorized group
  folder move NAME POSITION   move a folder to a position in the list (1 is the first); its entries stay in it

Settings (settings.json in the history folder, shared with the app):
  settings                    show the settings
  settings set KEY VALUE      set one setting:
                                appearance           system, light or dark
                                uncategorized-name   the name of the group of entries in no folder
                                uncategorized-limit  \(ClipSettings.limitRange.lowerBound) to \(ClipSettings.limitRange.upperBound); a lower limit deletes the
                                                     oldest uncategorized entries at once

Backup:
  backup FILE [--force]       write the full history (entries, folders, settings) to one backup file;
                              --force overwrites an existing file
  import-backup FILE          add the entries of the backup that are not in the history (Merge)
  import-backup FILE --replace
                              replace the full history and the settings with the backup; the current
                              history is saved to the backups folder first

Other:
  watch                       add each FileMaker object on the clipboard to the history (Ctrl+C to stop)
  help, --help                this text

Options:
  --history DIR   the history folder (default: \(HistoryStore.defaultFolder.path))
  --json          JSON output (an entry, a list of entries, a folder, a list of folders, or
                  the counts of a backup command)
  C               one of \(FMClass.allCases.map(\.rawValue).joined(separator: ", "))

Exit codes: 0 OK, 1 error, 2 bad usage, 3 not found. Errors go to stderr.
The app and the CLI can change the history at the same time. Nothing is lost.
"""

enum ExitCode: Int32 {
    case ok = 0, error = 1, usage = 2, notFound = 3
}

struct CLIError: Error {
    let code: ExitCode
    let message: String
}

func fail(_ code: ExitCode, _ message: String) -> CLIError {
    CLIError(code: code, message: message)
}

/// Stops add and restore for a layout clip with a portal child outside the first portal row (PortalCheck).
/// FileMaker pastes such a child as an object that the user cannot select. `--force` skips the check.
func refuseBadPortals(_ cls: FMClass, _ data: Data, _ args: Arguments) throws {
    guard !args.flags.contains("--force"), let message = PortalCheck.message(cls: cls, data: data) else { return }
    throw fail(.error, message + "\nTo go on anyway, add --force.")
}

// MARK: - Arguments

struct Arguments {
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    static let valueOptions: Set<String> = ["--history", "--folder", "--class", "--search", "--limit", "--name"]
    static let flagOptions: Set<String> = ["--json", "--no-folder", "--help", "-h", "--force", "--replace"]

    init(_ raw: [String]) throws {
        var i = 0
        while i < raw.count {
            let arg = raw[i]
            if arg.hasPrefix("-") && arg.count > 1 && Double(arg) == nil {
                var key = arg
                var inline: String?
                if let eq = arg.firstIndex(of: "="), arg.hasPrefix("--") {
                    key = String(arg[..<eq])
                    inline = String(arg[arg.index(after: eq)...])
                }
                if Self.flagOptions.contains(key) {
                    flags.insert(key)
                } else if Self.valueOptions.contains(key) {
                    if let inline {
                        values[key] = inline
                    } else {
                        guard i + 1 < raw.count else { throw fail(.usage, "\(key) needs a value") }
                        values[key] = raw[i + 1]
                        i += 1
                    }
                } else {
                    throw fail(.usage, "unknown option \(arg)")
                }
            } else {
                positional.append(arg)
            }
            i += 1
        }
    }

    var json: Bool { flags.contains("--json") }
}

// MARK: - Output

/// The JSON of an entry. These field names are stable (see the Command-Line Tool page of the wiki).
func entryJSON(_ e: HistoryEntry, _ store: HistoryStore) -> [String: Any] {
    let url = store.fileURL(for: e)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    return [
        "id": e.id,
        "class": e.cls.rawValue,
        "type": e.cls.label,
        "title": e.displayTitle,
        "autoTitle": e.title,
        "name": e.name as Any? ?? NSNull(),
        "folder": e.folder as Any? ?? NSNull(),
        "time": e.time,
        "sha256": e.sha256,
        "source": e.source,
        "bytes": size,
        "file": url.path,
        "canonical": store.canonicalKey(for: e) as Any? ?? NSNull(),
    ]
}

func folderJSON(_ name: String, _ store: HistoryStore) -> [String: Any] {
    ["name": name, "count": store.count(in: name)]
}

func printJSON(_ value: Any, pretty: Bool = true) {
    var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
    if pretty { options.insert(.prettyPrinted) }
    let data = (try? JSONSerialization.data(withJSONObject: value, options: options)) ?? Data("null".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

/// One line for each entry: tab-separated fields. Tabs and line breaks in a field become spaces, so that each entry
/// stays on one line.
func line(_ e: HistoryEntry) -> String {
    [e.id, e.cls.rawValue, e.time, e.folder ?? "-", e.displayTitle].map(oneLine).joined(separator: "\t")
}

func oneLine(_ s: String) -> String {
    s.components(separatedBy: CharacterSet(charactersIn: "\t\r\n")).joined(separator: " ")
}

// MARK: - Commands

func openStore(_ args: Arguments) throws -> HistoryStore {
    let folder = args.values["--history"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? HistoryStore.defaultFolder
    do { return try HistoryStore(folder: folder) } catch {
        throw fail(.error, "cannot open the history in \(folder.path): \(error.localizedDescription)")
    }
}

func parseClass(_ value: String?) throws -> FMClass? {
    guard let value else { return nil }
    guard let cls = FMClass(rawValue: value.uppercased()) else {
        throw fail(.usage, "unknown class \(value); use one of \(FMClass.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    return cls
}

func need(_ args: Arguments, _ count: Int, _ form: String) throws {
    guard args.positional.count == count else { throw fail(.usage, "usage: fm-object-clip-cli \(form)") }
}

func entryOrFail(_ store: HistoryStore, _ id: String) throws -> HistoryEntry {
    guard let e = store.entry(id: id) else { throw fail(.notFound, "no entry with the id \(id)") }
    return e
}

func run(_ args: Arguments) throws {
    let p = args.positional
    if args.flags.contains("--help") || args.flags.contains("-h") || p.first == "help" || p.isEmpty {
        print(usage)
        return
    }
    switch p[0] {
    case "list":
        try need(args, 1, "list [--folder NAME | --no-folder] [--class C] [--search TEXT] [--limit N]")
        if args.values["--folder"] != nil && args.flags.contains("--no-folder") {
            throw fail(.usage, "give --folder or --no-folder, not both")
        }
        var limit: Int?
        if let raw = args.values["--limit"] {
            guard let n = Int(raw), n >= 0 else { throw fail(.usage, "--limit needs a number of 0 or more") }
            limit = n
        }
        let store = try openStore(args)
        var scope = HistoryStore.FolderScope.any
        if let f = args.values["--folder"] {
            guard let existing = store.existingFolder(f) else { throw fail(.notFound, "no folder with the name \(f)") }
            scope = .folder(existing)
        } else if args.flags.contains("--no-folder") {
            scope = .none
        }
        let result = store.query(scope: scope, cls: try parseClass(args.values["--class"]),
                                 search: args.values["--search"], limit: limit)
        if args.json { printJSON(result.map { entryJSON($0, store) }) } else { result.forEach { print(line($0)) } }

    case "show":
        try need(args, 2, "show ID")
        let store = try openStore(args)
        let e = try entryOrFail(store, p[1])
        if args.json {
            printJSON(entryJSON(e, store))
        } else {
            for (k, v) in entryJSON(e, store).sorted(by: { $0.key < $1.key }) {
                print("\(k): \(v is NSNull ? "-" : "\(v)")")
            }
        }

    case "xml":
        try need(args, 2, "xml ID")
        let store = try openStore(args)
        let e = try entryOrFail(store, p[1])
        do { FileHandle.standardOutput.write(try store.data(for: e)) } catch {
            throw fail(.error, "cannot read \(store.fileURL(for: e).path): \(error.localizedDescription)")
        }

    case "folders":
        try need(args, 1, "folders")
        let store = try openStore(args)
        if args.json { printJSON(store.folders.map { folderJSON($0, store) }) } else {
            store.folders.forEach { print("\($0)\t\(store.count(in: $0))") }
        }

    case "info":
        try need(args, 1, "info")
        let objects = FMPasteboard.read()
        if args.json {
            printJSON(objects.map { o -> [String: Any] in
                ["class": o.cls.rawValue, "bytes": o.data.count, "name": o.name as Any? ?? NSNull(), "folder": o.folder as Any? ?? NSNull()]
            })
        } else {
            if objects.isEmpty { print("no FileMaker objects on the clipboard") }
            for o in objects {
                print("\(o.cls.rawValue)\t\(o.data.count) bytes\(o.name.map { "\tname: \($0)" } ?? "")\(o.folder.map { "\tfolder: \($0)" } ?? "")")
            }
        }

    case "add":
        try need(args, 2, "add FILE.xml --class C [--name NAME] [--folder NAME] [--force]")
        guard let cls = try parseClass(args.values["--class"]) else { throw fail(.usage, "add needs --class C") }
        guard let data = FileManager.default.contents(atPath: p[1]) else { throw fail(.notFound, "cannot read the file \(p[1])") }
        guard !data.isEmpty else { throw fail(.error, "the file \(p[1]) is empty") }
        try refuseBadPortals(cls, data, args)
        let store = try openStore(args)
        let e = try store.add(data, cls: cls, name: args.values["--name"], folder: args.values["--folder"], source: "cli")
        if args.json { printJSON(entryJSON(e, store)) } else { print(line(e)) }

    case "restore":
        try need(args, 2, "restore ID [--force]")
        let store = try openStore(args)
        let e = try entryOrFail(store, p[1])
        try refuseBadPortals(e.cls, try store.data(for: e), args)
        guard try store.copy(e) != nil else { throw fail(.error, "the clipboard refused the data") }
        if args.json { printJSON(entryJSON(e, store)) } else { print("clipboard set: \(e.cls.rawValue), \(e.displayTitle)") }

    case "rename":
        try need(args, 3, "rename ID NAME")
        let store = try openStore(args)
        guard let e = try store.rename(id: p[1], to: p[2]) else { throw fail(.notFound, "no entry with the id \(p[1])") }
        if args.json { printJSON(entryJSON(e, store)) } else { print(line(e)) }

    case "move":
        let noFolder = args.flags.contains("--no-folder")
        try need(args, noFolder ? 2 : 3, "move ID FOLDER | move ID --no-folder")
        let store = try openStore(args)
        guard let e = try store.move(id: p[1], to: noFolder ? nil : p[2]) else {
            throw fail(.notFound, "no entry with the id \(p[1])")
        }
        if args.json { printJSON(entryJSON(e, store)) } else { print(line(e)) }

    case "delete":
        guard p.count >= 2 else { throw fail(.usage, "usage: fm-object-clip-cli delete ID [ID ...]") }
        let store = try openStore(args)
        let ids = Array(p.dropFirst())
        let missing = ids.filter { store.entry(id: $0) == nil }
        guard missing.isEmpty else { throw fail(.notFound, "no entry with the id \(missing.joined(separator: ", ")); nothing deleted") }
        // The JSON is made before the delete, while the XML files (and their sizes) are still there.
        let before = ids.compactMap { store.entry(id: $0) }.map { entryJSON($0, store) }
        let gone = try store.delete(ids: ids)
        if args.json { printJSON(before) } else { gone.forEach { print("deleted\t\(line($0))") } }

    case "folder":
        guard p.count >= 2 else { throw fail(.usage, "usage: fm-object-clip-cli folder new NAME | rename OLD NEW | delete NAME | move NAME POSITION") }
        let store = try openStore(args)
        do {
            switch p[1] {
            case "new":
                try need(args, 3, "folder new NAME")
                let name = try store.makeFolder(p[2])
                if args.json { printJSON(folderJSON(name, store)) } else { print("\(name)\t\(store.count(in: name))") }
            case "rename":
                try need(args, 4, "folder rename OLD NEW")
                let name = try store.renameFolder(p[2], to: p[3])
                if args.json {
                    var j = folderJSON(name, store)
                    j["oldName"] = p[2]
                    printJSON(j)
                } else {
                    print("\(name)\t\(store.count(in: name))")
                }
            case "delete":
                try need(args, 3, "folder delete NAME")
                let existing = store.existingFolder(p[2]) ?? p[2]
                let moved = try store.deleteFolder(p[2])
                if args.json { printJSON(["name": existing, "movedEntries": moved]) } else {
                    print("deleted folder\t\(existing)\t\(count(moved, "entry", "entries")) to \(store.settings.displayName)")
                }
            case "move":
                try need(args, 4, "folder move NAME POSITION")
                guard let position = Int(p[3]), position >= 1 else { throw fail(.usage, "POSITION needs a number of 1 or more") }
                let order = try store.moveFolder(p[2], to: position - 1)
                if args.json { printJSON(order.map { folderJSON($0, store) }) } else {
                    order.forEach { print("\($0)\t\(store.count(in: $0))") }
                }
            default:
                throw fail(.usage, "unknown folder command \(p[1]); use new, rename, delete or move")
            }
        } catch let error as HistoryStore.FolderError {
            switch error {
            case .notFound: throw fail(.notFound, error.localizedDescription)
            case .emptyName: throw fail(.usage, error.localizedDescription)
            case .exists: throw fail(.error, error.localizedDescription)
            }
        }

    case "settings":
        try runSettings(args)

    case "backup":
        try need(args, 2, "backup FILE [--force]")
        let url = URL(fileURLWithPath: p[1])
        if FileManager.default.fileExists(atPath: url.path) && !args.flags.contains("--force") {
            throw fail(.error, "the file \(url.path) exists; use --force to overwrite it")
        }
        let store = try openStore(args)
        let backup = try store.writeBackup(to: url)
        if args.json {
            printJSON(["file": url.path, "entries": backup.items.count, "folders": backup.folders.count,
                       "settings": backup.settings != nil])
        } else {
            print("backup written\t\(url.path)\t\(count(backup.items.count, "entry", "entries"))\t\(count(backup.folders.count, "folder"))")
        }

    case "import-backup":
        try need(args, 2, "import-backup FILE [--replace]")
        guard FileManager.default.fileExists(atPath: p[1]) else { throw fail(.notFound, "cannot read the file \(p[1])") }
        let backup = try Backup.read(from: URL(fileURLWithPath: p[1]))
        let store = try openStore(args)
        if args.flags.contains("--replace") {
            let r = try store.replace(with: backup)
            if args.json {
                printJSON(["mode": "replace", "entries": r.entries, "folders": r.folders, "safetyBackup": r.safetyBackup.path])
            } else {
                print("history replaced\t\(count(r.entries, "entry", "entries"))\t\(count(r.folders, "folder"))\tsafety backup \(r.safetyBackup.path)")
            }
        } else {
            let r = try store.merge(backup)
            if args.json {
                printJSON(["mode": "merge", "added": r.added, "skippedDuplicates": r.skippedDuplicates,
                           "foldersAdded": r.foldersAdded])
            } else {
                print("merged\t\(r.added) added\t\(count(r.skippedDuplicates, "duplicate")) skipped\t\(count(r.foldersAdded, "folder")) added")
            }
        }

    case "watch":
        try need(args, 1, "watch")
        let store = try openStore(args)
        let json = args.json
        let watcher = ClipboardWatcher(onOther: { store.forgetRestore() }) { objects in
            for obj in objects {
                do {
                    let e = try store.add(obj.data, cls: obj.cls, name: obj.name, folder: obj.folder)
                    if json { printJSON(entryJSON(e, store), pretty: false) } else { print(line(e)) }
                    // A copy from FileMaker Pro is kept as it is; restore needs --force for it.
                    if let message = PortalCheck.message(cls: obj.cls, data: obj.data) {
                        FileHandle.standardError.write(Data("warning: \(e.id): \(message)\n".utf8))
                    }
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                }
            }
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        if !json { print("watching the clipboard; history in \(store.folder.path); press Ctrl+C to stop") }
        watcher.start()
        RunLoop.main.run()

    default:
        throw fail(.usage, "unknown command \(p[0]); run fm-object-clip-cli help")
    }
}

/// `settings` and `settings set KEY VALUE`.
func runSettings(_ args: Arguments) throws {
    let p = args.positional
    if p.count == 1 {
        printSettings(try openStore(args).settings, json: args.json)
        return
    }
    guard p.count == 4, p[1] == "set" else { throw fail(.usage, "usage: fm-object-clip-cli settings [set KEY VALUE]") }
    var check = ClipSettings()
    do { try check.set(p[2], to: p[3]) } catch { throw fail(.usage, error.localizedDescription) }  // before the store opens
    let store = try openStore(args)
    let gone = try store.updateSettings { try? $0.set(p[2], to: p[3]) }
    let settings = store.settings
    if args.json {
        var j = settingsJSON(settings)
        j["deletedEntries"] = gone.count
        printJSON(j)
    } else {
        print("\(p[2])\t\(settings.value(of: p[2]) ?? "")")
        if !gone.isEmpty { print("deleted \(count(gone.count, "oldest uncategorized entry", "oldest uncategorized entries"))") }
    }
}

func settingsJSON(_ s: ClipSettings) -> [String: Any] {
    ["appearance": s.appearance, "uncategorizedName": s.displayName, "uncategorizedLimit": s.uncategorizedLimit]
}

/// "1 entry", "2 entries": a number and a noun, in the style of the count helper of the titles (Titles.count).
func count(_ n: Int, _ noun: String, _ plural: String? = nil) -> String {
    "\(n) \(n == 1 ? noun : plural ?? noun + "s")"
}

func printSettings(_ s: ClipSettings, json: Bool) {
    if json { printJSON(settingsJSON(s)) } else {
        for key in ClipSettings.keys { print("\(key)\t\(s.value(of: key) ?? "")") }
    }
}

do {
    try run(try Arguments(Array(CommandLine.arguments.dropFirst())))
    exit(ExitCode.ok.rawValue)
} catch let error as CLIError {
    FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
    exit(error.code.rawValue)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(ExitCode.error.rawValue)
}
