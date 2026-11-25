import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// A copy from the app (Copy Entry) or from the CLI (restore) does not change the entry, and a folder with names
/// shows its entries in the natural order of the names. Private pasteboard and temporary folder only.
final class CopyOrderTests: XCTestCase {
    var folder: URL!
    var store: HistoryStore!
    var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        store = try HistoryStore(folder: folder)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    static func compact(_ n: Int) -> Data {
        Data("<fmxmlsnippet type=\"FMObjectList\"><Step enable=\"True\" id=\"89\" name=\"# (comment)\"><Text>Step \(n)</Text></Step></fmxmlsnippet>".utf8)
    }

    /// The same object as FileMaker Pro writes it again: a declaration and pretty-printed.
    static func pretty(_ n: Int) -> Data {
        Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<fmxmlsnippet type=\"FMObjectList\">\n  <Step id=\"89\" enable=\"True\" name=\"# (comment)\">\n    <Text>Step \(n)</Text>\n  </Step>\n</fmxmlsnippet>\n".utf8)
    }

    /// Three entries, oldest first: 1, 2, 3. Entry 1 is at the bottom.
    @discardableResult
    func addThree() throws -> [HistoryEntry] {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return try (1...3).map { n in
            try store.add(Self.compact(n), cls: .XMSS, name: String(format: "%02d Script", n), folder: "Project Test",
                          now: base.addingTimeInterval(Double(n) * 60))
        }
    }

    /// A watcher of the private pasteboard that captures into the store, as the app does.
    func makeWatcher(_ store: HistoryStore) -> ClipboardWatcher {
        ClipboardWatcher(pasteboard: pasteboard, onOther: { store.forgetRestore() }) { objects in
            for obj in objects { _ = try? store.add(obj.data, cls: obj.cls) }
        }
    }

    // MARK: - 1. A copy does not change the entry

    func testCopyAndTheFileMakerRewriteKeepTheTimeAndThePlace() throws {
        let three = try addThree()
        let before = store.entries
        let watcher = makeWatcher(store)
        let count = try XCTUnwrap(store.copy(three[0], to: pasteboard))
        watcher.ignore(changeCount: count)
        XCTAssertEqual(watcher.poll(), [])  // the copy of the app itself

        // FileMaker Pro puts the same script on the clipboard again (compact, then pretty-printed).
        FMPasteboard.write(Self.compact(1), as: .XMSS, to: pasteboard)
        XCTAssertEqual(watcher.settle().count, 1)
        FMPasteboard.write(Self.pretty(1), as: .XMSS, to: pasteboard)
        XCTAssertEqual(watcher.settle().count, 1)

        try store.reload()
        XCTAssertEqual(store.entries, before)
        XCTAssertEqual(store.entries.count, 3)
    }

    func testRestoreFromTheCLIKeepsTheTimeAndThePlace() throws {
        let three = try addThree()
        let before = store.entries
        let watcher = makeWatcher(store)  // the app
        let cli = try HistoryStore(folder: folder)  // another process on the same history
        XCTAssertNotNil(try cli.copy(three[0], to: pasteboard))
        XCTAssertEqual(watcher.settle().count, 1)  // the app does not know the change count of the CLI
        FMPasteboard.write(Self.pretty(1), as: .XMSS, to: pasteboard)
        XCTAssertEqual(watcher.settle().count, 1)

        try store.reload()
        XCTAssertEqual(store.entries, before)
    }

    func testAnIdenticalCopyAfterOtherContentsStillMovesTheEntry() throws {
        let three = try addThree()
        let watcher = makeWatcher(store)
        try store.copy(three[0], to: pasteboard)
        XCTAssertNotNil(store.lastRestore())

        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)
        XCTAssertEqual(watcher.settle(), [])
        XCTAssertNil(store.lastRestore())

        // Now a copy of the same script in FileMaker Pro.
        FMPasteboard.write(Self.pretty(1), as: .XMSS, to: pasteboard)
        watcher.settle()
        XCTAssertEqual(store.entries.first?.id, three[0].id)
        XCTAssertNotEqual(store.entries.first?.time, three[0].time)
        XCTAssertEqual(store.entries.count, 3)
    }

    /// Re-review finding: plain text that a newer change replaces before it settles still forgets the restore record.
    /// Then a real FileMaker copy of the restored entry moves it to the top.
    func testPlainTextReplacedBeforeItSettlesStillForgetsTheRestore() throws {
        let three = try addThree()
        let watcher = makeWatcher(store)
        var clock = Date(timeIntervalSince1970: 1000)
        watcher.now = { clock }
        XCTAssertEqual(store.entries.first?.id, three[2].id)

        // Restore entry 1 (the oldest) from the app: the watcher ignores this copy.
        let count = try XCTUnwrap(store.copy(three[0], to: pasteboard))
        watcher.ignore(changeCount: count)
        XCTAssertNotNil(store.lastRestore())

        // Plain text at t=0.1, a check at t=0.4.
        clock += 0.1
        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)
        clock += 0.3
        XCTAssertEqual(watcher.poll(), [])
        XCTAssertNil(store.lastRestore())  // forgotten at the first check of the text

        // A real FileMaker copy of entry 1 at t=0.7, before the text settled. Checks at t=0.8 and t=1.2.
        clock += 0.3
        FMPasteboard.write(Self.pretty(1), as: .XMSS, to: pasteboard)
        clock += 0.1
        XCTAssertEqual(watcher.poll(), [])
        clock += 0.4
        XCTAssertEqual(watcher.poll().count, 1)

        XCTAssertNil(store.lastRestore())
        XCTAssertEqual(store.entries.first?.id, three[0].id)  // moved to the top
        XCTAssertNotEqual(store.entries.first?.time, three[0].time)
        XCTAssertEqual(store.entries.count, 3)
    }

    /// onOther runs one time for each change with no FileMaker class, at its first check, and never for a change
    /// with FileMaker objects (also when a newer change drops it).
    func testOnOtherRunsOnceAndOnlyForContentsWithNoFileMakerClass() throws {
        var others = 0
        let watcher = ClipboardWatcher(pasteboard: pasteboard, onOther: { others += 1 }) { _ in }
        pasteboard.clearContents()
        pasteboard.setString("text", forType: .string)
        XCTAssertEqual(watcher.poll(), [])
        XCTAssertEqual(others, 1)
        XCTAssertEqual(watcher.poll(), [])  // settles: no second call
        XCTAssertEqual(others, 1)

        FMPasteboard.write(Self.compact(1), as: .XMSS, to: pasteboard)
        XCTAssertEqual(watcher.poll(), [])  // waits
        let count = try XCTUnwrap(FMPasteboard.write(Self.compact(2), as: .XMSS, to: pasteboard))
        watcher.ignore(changeCount: count)  // drops the waiting FileMaker change
        pasteboard.clearContents()
        pasteboard.setString("more text", forType: .string)
        XCTAssertEqual(watcher.settle(), [])
        XCTAssertEqual(others, 2)
    }

    func testAnIdenticalCopyAfterAnotherObjectStillMovesTheEntry() throws {
        let three = try addThree()
        let watcher = makeWatcher(store)
        try store.copy(three[0], to: pasteboard)
        FMPasteboard.write(Self.compact(9), as: .XMSS, to: pasteboard)  // a new object
        watcher.settle()
        XCTAssertNil(store.lastRestore())
        FMPasteboard.write(Self.compact(1), as: .XMSS, to: pasteboard)
        watcher.settle()
        XCTAssertEqual(store.entries.first?.id, three[0].id)
        XCTAssertEqual(store.entries.count, 4)
    }

    func testACaptureWithANameIsNotAnEcho() throws {
        let three = try addThree()
        try store.copy(three[0], to: pasteboard)
        let e = try store.add(Self.compact(1), cls: .XMSS, name: "New name")
        XCTAssertEqual(e.id, three[0].id)
        XCTAssertEqual(store.entries.first?.name, "New name")
    }

    func testAddFromTheCLIKeepsTheRestoreRecord() throws {
        let three = try addThree()
        try store.copy(three[0], to: pasteboard)
        try store.add(Self.compact(7), cls: .XMSS, source: "cli")
        XCTAssertEqual(store.lastRestore()?.id, three[0].id)
    }

    func testCopyEntryInTheAppShowsCopiedAndKeepsTheOrder() throws {
        let three = try addThree()
        let model = AppModel(store: store, watch: false)
        let before = model.entries
        model.copy(three[0], to: pasteboard)
        XCTAssertEqual(model.copiedID, three[0].id)
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XMSS, data: Self.compact(1))])
        XCTAssertEqual(model.entries, before)
        let cleared = expectation(description: "the Copied mark goes away")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertNil(model.copiedID)
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 3)
    }

    // MARK: - 2. The order in a folder

    func entries(in rows: [TreeRow], folder name: String) -> [String] {
        var inside = false
        var names: [String] = []
        for row in rows {
            switch row.kind {
            case .folder(let n, _, _): inside = n == name
            case .noFolder: inside = name == ""
            case .entry(let e, _): if inside { names.append(e.displayTitle) }
            }
        }
        return names
    }

    func testAFolderWithNamesIsInTheNaturalOrderOfTheNames() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for (k, n) in [10, 2, 17, 1, 9, 11].enumerated() {
            try store.add(Self.compact(n), cls: .XMSS, name: "\(n) Script", folder: "Project Test", now: base.addingTimeInterval(Double(k)))
        }
        let rows = HistoryTree.rows(entries: store.entries, folders: store.folders, expanded: ["Project Test"],
                                    active: false) { _ in true }
        XCTAssertEqual(entries(in: rows, folder: "Project Test"),
                       ["1 Script", "2 Script", "9 Script", "10 Script", "11 Script", "17 Script"])
    }

    func testZeroPaddedNamesStayInOrderAfterACopy() throws {
        let three = try addThree()
        let watcher = makeWatcher(store)
        try store.copy(three[1], to: pasteboard)
        // A copy in FileMaker Pro after other contents moves entry 2 to the top of the history.
        pasteboard.clearContents()
        pasteboard.setString("x", forType: .string)
        watcher.settle()
        FMPasteboard.write(Self.compact(2), as: .XMSS, to: pasteboard)
        watcher.settle()
        XCTAssertEqual(store.entries.first?.id, three[1].id)
        let rows = HistoryTree.rows(entries: store.entries, folders: store.folders, expanded: ["Project Test"],
                                    active: false) { _ in true }
        XCTAssertEqual(entries(in: rows, folder: "Project Test"), ["01 Script", "02 Script", "03 Script"])
    }

    func testAFolderWithAnEntryWithNoNameIsNewestFirst() throws {
        try addThree()
        try store.add(Self.compact(4), cls: .XMSS, folder: "Project Test", now: Date(timeIntervalSince1970: 1_900_000_000))
        let rows = HistoryTree.rows(entries: store.entries, folders: store.folders, expanded: ["Project Test"],
                                    active: false) { _ in true }
        let titles = entries(in: rows, folder: "Project Test")
        XCTAssertEqual(titles.count, 4)
        XCTAssertEqual(Array(titles.dropFirst()), ["03 Script", "02 Script", "01 Script"])
    }

    func testNoFolderIsNewestFirstAlsoWithNames() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for n in 1...3 {
            try store.add(Self.compact(n), cls: .XMSS, name: "\(n) Loose", now: base.addingTimeInterval(Double(n)))
        }
        let rows = HistoryTree.rows(entries: store.entries, folders: store.folders, expanded: [], active: false) { _ in true }
        XCTAssertEqual(entries(in: rows, folder: ""), ["3 Loose", "2 Loose", "1 Loose"])
    }

    func testTheFilterKeepsTheNaturalOrder() throws {
        try addThree()
        let rows = HistoryTree.rows(entries: store.entries, folders: store.folders, expanded: [], active: true) {
            $0.name != "02 Script"
        }
        XCTAssertEqual(entries(in: rows, folder: "Project Test"), ["01 Script", "03 Script"])
    }
}
