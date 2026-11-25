import AppKit
import XCTest
@testable import FMClipCore

/// The rules for the name and folder classes (FOPN, FOPF): the cleanup of the value, the watcher when a tool writes
/// the classes one by one, and the uncategorized group (its limit and its label).
final class NameFolderRulesTests: XCTestCase {
    var folder: URL!
    var pasteboard: NSPasteboard!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        pasteboard.releaseGlobally()
    }

    func xml(_ i: Int) -> Data { Data("<fmxmlsnippet><Step name=\"Step \(i)\"/></fmxmlsnippet>".utf8) }

    /// One clipboard write as the docs tell a tool to do it: declare all the types at once, then set the data.
    func putBytes(_ data: Data, _ cls: FMClass = .XMSS, name: Data? = nil, folder: Data? = nil) {
        var types = [cls.pasteboardType]
        if name != nil { types.append(FMPasteboard.nameType) }
        if folder != nil { types.append(FMPasteboard.folderType) }
        pasteboard.declareTypes(types, owner: nil)
        XCTAssertTrue(pasteboard.setData(data, forType: cls.pasteboardType))
        if let name { XCTAssertTrue(pasteboard.setData(name, forType: FMPasteboard.nameType)) }
        if let folder { XCTAssertTrue(pasteboard.setData(folder, forType: FMPasteboard.folderType)) }
    }

    func put(_ data: Data, _ cls: FMClass = .XMSS, name: String? = nil, folder: String? = nil) {
        putBytes(data, cls, name: name.map { Data($0.utf8) }, folder: folder.map { Data($0.utf8) })
    }

    /// A capture from the clipboard, as the app and `watch` do it.
    @discardableResult
    func capture(_ store: HistoryStore) throws -> [HistoryEntry] {
        try FMPasteboard.read(pasteboard).map { try store.add($0.data, cls: $0.cls, name: $0.name, folder: $0.folder) }
    }

    func label(_ s: String) -> String? { FMPasteboard.cleanLabel(Data(s.utf8)) }

    // MARK: - The cleanup of the value

    func testInvalidUTF8IsNoValue() {
        XCTAssertNil(FMPasteboard.cleanLabel(Data([0x4E, 0xFF, 0xFE, 0x61])))
        XCTAssertNil(FMPasteboard.cleanLabel(Data([0xC3])))  // a cut 2-byte sequence
        putBytes(xml(1), name: Data([0xFF]), folder: Data([0x80, 0x41]))
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XMSS, data: xml(1))])
    }

    func testControlCharactersGoAway() {
        XCTAssertEqual(label("Count\tcontacts"), "Count contacts")  // a tab becomes a space
        XCTAssertEqual(label("A\u{0}B\u{7}C\u{1B}D\u{7F}E\u{90}F\u{9F}G"), "ABCDEFG")  // C0, DEL and C1
        XCTAssertEqual(label("one\r\ntwo\u{2028}three\u{85}four"), "one  two three four")
        XCTAssertEqual(label("N\u{0}a\u{0}m\u{0}e\u{0}"), "Name")  // UTF-16 text read as UTF-8
        XCTAssertNil(label("\u{0}\t\n \u{1F}"))  // nothing is left
        XCTAssertEqual(label("Família 👩‍💻 – ✓"), "Família 👩‍💻 – ✓")  // other text stays, also the zero width joiner
    }

    func testLongValueIsCut() {
        XCTAssertEqual(label(String(repeating: "x", count: 1_000_000))?.count, FMPasteboard.maxLabelLength)
        XCTAssertEqual(label("  " + String(repeating: "é", count: 250))?.count, 200)  // counts characters, not bytes
        XCTAssertEqual(label(String(repeating: "a", count: 199) + "  b"), String(repeating: "a", count: 199))  // no end space
    }

    func testLongFolderMakesAShortFolder() throws {
        let store = try HistoryStore(folder: folder)
        put(xml(1), folder: String(repeating: "F", count: 1_000_000))
        try capture(store)
        XCTAssertEqual(store.folders.map(\.count), [200])
        XCTAssertEqual(store.entries[0].folder?.count, 200)
    }

    // MARK: - The watcher: one capture for each clipboard change, after the contents settle

    /// A watcher of the private pasteboard that captures into the store, as the app and `watch` do. It counts the
    /// calls of onCapture (one call is one line of `watch`).
    final class Calls { var count = 0 }

    func makeWatcher(_ store: HistoryStore, calls: Calls? = nil) -> ClipboardWatcher {
        ClipboardWatcher(pasteboard: pasteboard, onOther: { store.forgetRestore() }) { objects in
            calls?.count += 1
            for o in objects { _ = try? store.add(o.data, cls: o.cls, name: o.name, folder: o.folder) }
        }
    }

    func testOneWriteIsCapturedOnceAfterOneSettleStep() throws {
        let store = try HistoryStore(folder: folder)
        let calls = Calls()
        let watcher = makeWatcher(store, calls: calls)
        put(xml(1), name: "Name", folder: "Folder")
        XCTAssertEqual(watcher.poll(), [])  // the change: no capture yet
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(watcher.poll(), [FMObject(cls: .XMSS, data: xml(1), name: "Name", folder: "Folder")])
        XCTAssertEqual(watcher.poll(), [])
        XCTAssertEqual(watcher.poll(), [])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(store.entries.map(\.folder), ["Folder"])
    }

    /// Review finding P1: the object comes first, the folder later, in the same change count. At the limit, nothing
    /// may be deleted, because the capture is in a folder.
    func testLateFolderAtTheLimitDeletesNothing() throws {
        let (store, ids) = try storeAtLimit()
        let watcher = makeWatcher(store)
        pasteboard.declareTypes([FMClass.XMSS.pasteboardType, FMPasteboard.folderType], owner: nil)
        let count = pasteboard.changeCount
        pasteboard.setData(xml(100), forType: FMClass.XMSS.pasteboardType)
        XCTAssertEqual(watcher.poll(), [])  // the object without the folder
        pasteboard.setData(Data("Project A".utf8), forType: FMPasteboard.folderType)
        XCTAssertEqual(pasteboard.changeCount, count)  // the same clipboard generation
        XCTAssertEqual(watcher.poll(), [])  // the contents changed: wait again
        XCTAssertEqual(watcher.poll(), [FMObject(cls: .XMSS, data: xml(100), folder: "Project A")])

        XCTAssertEqual(store.uncategorizedCount, 10)
        XCTAssertEqual(store.entries.count, 11)
        XCTAssertEqual(store.entries[0].folder, "Project A")
        XCTAssertTrue(Set(store.entries.map(\.id)).isSuperset(of: ids))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(ids[0] + ".xml").path))
    }

    /// Review finding P2: after the capture, the user deletes the entry. A new name in the same change count
    /// does not make the entry again.
    func testDeletedCaptureIsNotMadeAgain() throws {
        let store = try HistoryStore(folder: folder)
        let watcher = makeWatcher(store)
        put(xml(1), name: "First")
        XCTAssertEqual(watcher.settle().count, 1)
        let e = try XCTUnwrap(store.entries.first)
        try store.delete(id: e.id)
        pasteboard.setData(Data("Second".utf8), forType: FMPasteboard.nameType)
        for _ in 0..<4 { XCTAssertEqual(watcher.poll(), []) }
        XCTAssertTrue(store.entries.isEmpty)
    }

    /// Review finding P2: after the capture, the user moves the entry. A new name in the same change count does not
    /// put the folder of the clipboard back.
    func testMovedCaptureStaysWhereTheUserPutIt() throws {
        let store = try HistoryStore(folder: folder)
        let watcher = makeWatcher(store)
        put(xml(1), name: "First", folder: "From clipboard")
        XCTAssertEqual(watcher.settle().count, 1)
        let e = try XCTUnwrap(store.entries.first)
        try store.move(id: e.id, to: "User choice")
        pasteboard.setData(Data("Second".utf8), forType: FMPasteboard.nameType)
        for _ in 0..<4 { XCTAssertEqual(watcher.poll(), []) }
        XCTAssertEqual(store.entries.map(\.folder), ["User choice"])
        XCTAssertEqual(store.entries.map(\.name), ["First"])
    }

    /// A value that comes after the capture is ignored.
    func testNameAfterTheCaptureIsIgnored() throws {
        let store = try HistoryStore(folder: folder)
        let calls = Calls()
        let watcher = makeWatcher(store, calls: calls)
        pasteboard.clearContents()
        pasteboard.setData(xml(1), forType: FMClass.XMSS.pasteboardType)
        XCTAssertEqual(watcher.settle(), [FMObject(cls: .XMSS, data: xml(1))])
        pasteboard.setData(Data("Too late".utf8), forType: FMPasteboard.nameType)
        for _ in 0..<4 { XCTAssertEqual(watcher.poll(), []) }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.entries[0].name)
    }

    func testObjectAfterTheNameInTheSameChangeIsCaptured() throws {
        let store = try HistoryStore(folder: folder)
        let watcher = makeWatcher(store)
        pasteboard.declareTypes([FMPasteboard.nameType, FMClass.XMSS.pasteboardType], owner: nil)
        pasteboard.setData(Data("First name".utf8), forType: FMPasteboard.nameType)
        XCTAssertEqual(watcher.poll(), [])  // no FileMaker class yet
        pasteboard.setData(xml(1), forType: FMClass.XMSS.pasteboardType)
        XCTAssertEqual(watcher.poll(), [])
        XCTAssertEqual(watcher.poll(), [FMObject(cls: .XMSS, data: xml(1), name: "First name")])
        XCTAssertEqual(store.entries.map(\.name), ["First name"])
    }

    /// With all the types declared at once, a check before the data is set sees no object. The data comes before the
    /// contents settle, so the capture has it.
    func testDeclaredTypesWithLateDataAreCaptured() throws {
        let store = try HistoryStore(folder: folder)
        let watcher = makeWatcher(store)
        pasteboard.declareTypes([FMClass.XMSS.pasteboardType, FMPasteboard.nameType], owner: nil)
        XCTAssertEqual(watcher.poll(), [])
        pasteboard.setData(xml(1), forType: FMClass.XMSS.pasteboardType)
        pasteboard.setData(Data("Declared".utf8), forType: FMPasteboard.nameType)
        XCTAssertEqual(watcher.settle(), [FMObject(cls: .XMSS, data: xml(1), name: "Declared")])
        XCTAssertEqual(store.entries.map(\.name), ["Declared"])
    }

    /// Contents that change at each check are captured one time when `maxWait` has gone by.
    func testContentsThatDoNotSettleAreCapturedAfterTheMaxWait() throws {
        let store = try HistoryStore(folder: folder)
        let calls = Calls()
        let watcher = makeWatcher(store, calls: calls)
        var clock = Date(timeIntervalSince1970: 1000)
        watcher.now = { clock }
        pasteboard.declareTypes([FMClass.XMSS.pasteboardType, FMPasteboard.nameType], owner: nil)
        pasteboard.setData(xml(1), forType: FMClass.XMSS.pasteboardType)
        XCTAssertEqual(watcher.poll(), [])
        for i in 0..<2 {
            clock += 0.4
            pasteboard.setData(Data("Name \(i)".utf8), forType: FMPasteboard.nameType)
            XCTAssertEqual(watcher.poll(), [])
        }
        clock = Date(timeIntervalSince1970: 1000) + ClipboardWatcher.maxWait  // 1.2 s since the change
        pasteboard.setData(Data("Name 2".utf8), forType: FMPasteboard.nameType)
        XCTAssertEqual(watcher.poll(), [FMObject(cls: .XMSS, data: xml(1), name: "Name 2")])
        XCTAssertEqual(watcher.poll(), [])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(store.entries.map(\.name), ["Name 2"])
    }

    /// A second copy before the first settles: only the second (settled) copy is captured.
    func testSecondCopyDuringTheWaitReplacesTheFirst() throws {
        let store = try HistoryStore(folder: folder)
        let calls = Calls()
        let watcher = makeWatcher(store, calls: calls)
        put(xml(1), name: "First")
        XCTAssertEqual(watcher.poll(), [])
        put(xml(2), name: "Second")
        XCTAssertEqual(watcher.poll(), [])  // a new change: the wait starts again
        XCTAssertEqual(watcher.poll(), [FMObject(cls: .XMSS, data: xml(2), name: "Second")])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(store.entries.map(\.name), ["Second"])
    }

    /// The copy of the app itself (Copy Entry) is not captured, also when it comes during the wait of another change.
    func testIgnoredCopyIsNotCaptured() throws {
        let store = try HistoryStore(folder: folder)
        let calls = Calls()
        let watcher = makeWatcher(store, calls: calls)
        put(xml(1), name: "Name")
        XCTAssertEqual(watcher.poll(), [])  // waits
        let count = try XCTUnwrap(FMPasteboard.write(xml(2), as: .XMSS, to: pasteboard))
        watcher.ignore(changeCount: count)
        for _ in 0..<4 { XCTAssertEqual(watcher.poll(), []) }
        XCTAssertEqual(calls.count, 0)
        XCTAssertTrue(store.entries.isEmpty)

        put(xml(3))  // the next copy is captured as usual
        XCTAssertEqual(watcher.settle().count, 1)
        XCTAssertEqual(calls.count, 1)
    }

    /// NSPasteboardItem does not accept the type names "CorePasteboardFlavorType 0x...": setData returns false.
    /// This is why the docs say to use declareTypes, not writeObjects with an item.
    func testPasteboardItemRefusesTheLegacyTypeNames() {
        let item = NSPasteboardItem()
        XCTAssertFalse(item.setData(xml(1), forType: FMClass.XMSS.pasteboardType))
        XCTAssertFalse(item.setData(Data("Name".utf8), forType: FMPasteboard.nameType))
    }

    // MARK: - The uncategorized limit

    /// Fills the uncategorized group to a limit of 10. Returns the ids, oldest first.
    func storeAtLimit() throws -> (HistoryStore, [String]) {
        let store = try HistoryStore(folder: folder)
        try store.updateSettings { $0.uncategorizedLimit = 10 }
        var ids: [String] = []
        for i in 0..<10 { ids.append(try store.add(xml(i), cls: .XMSS, now: Date(timeIntervalSince1970: Double(1000 + i))).id) }
        XCTAssertEqual(store.limit, 10)
        XCTAssertEqual(store.uncategorizedCount, 10)
        return (store, ids)
    }

    func testCaptureWithFolderDoesNotCountForTheLimit() throws {
        let (store, ids) = try storeAtLimit()
        put(xml(100), name: "Kept", folder: "Project A")
        let e = try XCTUnwrap(try capture(store).first)
        XCTAssertEqual(e.folder, "Project A")
        XCTAssertEqual(store.entries.count, 11)
        XCTAssertEqual(store.uncategorizedCount, 10)
        XCTAssertEqual(Set(store.entries.map(\.id)), Set(ids + [e.id]))  // nothing was deleted
        try store.reload()
        XCTAssertEqual(store.entries.count, 11)
    }

    func testCaptureWithNoFolderCountsForTheLimit() throws {
        let (store, ids) = try storeAtLimit()
        put(xml(100), name: "Loose")
        let e = try XCTUnwrap(try capture(store).first)
        XCTAssertNil(e.folder)
        XCTAssertEqual(store.uncategorizedCount, 10)
        XCTAssertEqual(store.entries.count, 10)
        XCTAssertEqual(store.entries.first?.id, e.id)
        XCTAssertFalse(store.entries.contains { $0.id == ids[0] })  // the oldest uncategorized entry is gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(ids[0] + ".xml").path))
    }

    func testDuplicateWithNewFolderLeavesTheUncategorizedGroup() throws {
        let (store, ids) = try storeAtLimit()
        put(xml(3), folder: "Project B")  // the same XML as an uncategorized entry
        try capture(store)
        XCTAssertEqual(store.entries.count, 10)  // no new entry, and nothing was deleted
        XCTAssertEqual(store.entries[0].id, ids[3])
        XCTAssertEqual(store.entries[0].folder, "Project B")
        XCTAssertEqual(store.uncategorizedCount, 9)
        XCTAssertEqual(store.folders, ["Project B"])

        // Now there is space for one more uncategorized capture, so nothing is deleted.
        put(xml(200))
        try capture(store)
        XCTAssertEqual(store.entries.count, 11)
        XCTAssertEqual(store.uncategorizedCount, 10)
    }

    // MARK: - The label of the uncategorized group

    func testFolderWithTheDefaultLabelIsNoFolder() throws {
        let store = try HistoryStore(folder: folder)
        put(xml(1), folder: "Uncategorized")
        XCTAssertNil(try capture(store).first?.folder)
        put(xml(1), folder: " uncategorized ")
        XCTAssertNil(try capture(store).first?.folder)
        XCTAssertEqual(store.folders, [])
        XCTAssertEqual(store.uncategorizedCount, 1)
    }

    func testFolderWithACustomLabelIsNoFolder() throws {
        let store = try HistoryStore(folder: folder)
        try store.updateSettings { $0.uncategorizedName = "Inbox" }
        put(xml(1), folder: "INBOX")
        XCTAssertNil(try capture(store).first?.folder)
        put(xml(2), folder: "Uncategorized")  // a tool does not know the label of the user
        XCTAssertNil(try capture(store).first?.folder)
        XCTAssertEqual(store.folders, [])
        XCTAssertEqual(store.uncategorizedCount, 2)
    }

    func testFolderWithTheLabelOnADuplicateKeepsItsFolder() throws {
        let store = try HistoryStore(folder: folder)
        let e = try store.add(xml(1), cls: .XMSS, folder: "Project A")
        put(xml(1), folder: "Uncategorized")  // the same as no FOPF
        try capture(store)
        XCTAssertEqual(store.entries.map(\.id), [e.id])
        XCTAssertEqual(store.entries[0].folder, "Project A")
        XCTAssertEqual(store.folders, ["Project A"])
    }

    func testRealFolderWithTheLabelStaysAFolder() throws {
        let store = try HistoryStore(folder: folder)
        try store.makeFolder("Uncategorized")  // the user made this folder
        put(xml(1), folder: "uncategorized")
        XCTAssertEqual(try capture(store).first?.folder, "Uncategorized")
        XCTAssertEqual(store.uncategorizedCount, 0)
    }

    func testCLIAddWithTheLabelIsNotChanged() throws {
        let store = try HistoryStore(folder: folder)
        let e = try store.add(xml(1), cls: .XMSS, folder: "Uncategorized", source: "cli")
        XCTAssertEqual(e.folder, "Uncategorized")  // only the clipboard rule changes
    }
}
