import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// PortalCheck: a portal child must be in the first portal row, with bounds relative to the portal.
final class PortalCheckTests: XCTestCase {
    /// A portal at 112,20,292,740 with 6 rows of 30, and one field with the given bounds.
    func clip(_ top: String, _ left: String, _ bottom: String, _ right: String) -> Data {
        Data("""
        <fmxmlsnippet type="LayoutObjectList"><Layout>
        <Object type="Portal" key="1" name="portal_one"><Bounds top="112" left="20" bottom="292" right="740"/>
        <PortalObj numOfRows="6"><TableAliasKey>Contacts</TableAliasKey>
        <Object type="Field" key="2"><Bounds top="\(top)" left="\(left)" bottom="\(bottom)" right="\(right)"/>
        <FieldObj><Name>Contacts::Company</Name></FieldObj></Object>
        </PortalObj></Object></Layout></fmxmlsnippet>
        """.utf8)
    }

    func testGoodChildPasses() {
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("4", "4", "24", "214")), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("4.5", "4", "24.25", "214")), [])
        XCTAssertNil(PortalCheck.message(cls: .XML2, data: clip("4", "4", "24", "214")))
    }

    func testChildOutsideRowOne() {
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("116", "24", "136", "234")), [
            "portal portal_one: Field Contacts::Company at 116,24,136,234 "
            + "is outside the first row of the portal (0,0,30,720; 6 rows)",
        ])
        let message = PortalCheck.message(cls: .XML2, data: clip("116", "24", "136", "234")) ?? ""
        XCTAssertTrue(message.hasPrefix("1 portal child is in the wrong place:\n  portal portal_one:"), message)
        let two = Data(String(decoding: clip("116", "24", "136", "234"), as: UTF8.self).replacingOccurrences(
            of: "</PortalObj>", with: "<Object type=\"Field\" key=\"3\"><Bounds top=\"40\" left=\"4\" bottom=\"60\" right=\"9\"/></Object></PortalObj>").utf8)
        XCTAssertTrue(PortalCheck.message(cls: .XML2, data: two)?.hasPrefix("2 portal children are in the wrong place:") == true)
    }

    func testChildOutsideThePortal() {
        for b in [("348", "24", "368", "64"), ("4", "694", "24", "754"), ("-2", "4", "18", "214")] {
            let problems = PortalCheck.problems(cls: .XML2, data: clip(b.0, b.1, b.2, b.3))
            XCTAssertEqual(problems.count, 1)
            XCTAssertTrue(problems[0].hasSuffix("is outside the portal (0,0,180,720)"), problems[0])
        }
    }

    /// FileMaker writes a child on the portal border at -1. One point outside the portal or the row passes.
    func testOnePointOfSlack() {
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("-1", "-1", "31", "721")), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("0", "0", "31.5", "200")).count, 1)
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("0", "-1.5", "20", "200")).count, 1)
    }

    /// Real copies from FileMaker Pro 26.1.1 (Layout mode, Cmd+C on a portal). The table, field and value list
    /// names are neutral, and the styles, calculations and icons are taken out. The objects, their nesting and
    /// their bounds are as FileMaker wrote them. The portals are not at the top left of the layout, and the child
    /// bounds start at the portal top left.
    static func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testRealFileMakerCopiesPass() throws {
        // Portal at 157,40,1145,440 with 29 rows; fields at -1,-1,34,235 and -1,235,34,382.
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: try Self.fixture("portal-real.xml")), [])
        // Portal at 723,420,1100,1740 with 15 rows; a group at 0,-1,25,393 with two fields in it.
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: try Self.fixture("portal-real-group.xml")), [])
    }

    /// The bounds of an object in a group start at the top left of the group. A field below the first row in a
    /// group is found, also when the group itself is in the first row.
    func testChildInAGroup() throws {
        let real = String(decoding: try Self.fixture("portal-real-group.xml"), as: UTF8.self)
        let moved = real.replacingOccurrences(of: "<Bounds top=\"0.0000000\" left=\"0.0000000\" bottom=\"25.0000000\" right=\"93.0000000\"/>",
                                              with: "<Bounds top=\"30\" left=\"0\" bottom=\"55\" right=\"93\"/>")
        XCTAssertNotEqual(moved, real)
        let problems = PortalCheck.problems(cls: .XML2, data: Data(moved.utf8))
        XCTAssertEqual(problems, ["portal key 466: Field Portal_Rows::Date at 30,-1,55,92 "
                                  + "is outside the first row of the portal (0,0,25.1333,1320; 15 rows)"])
        let probe = "<fmxmlsnippet type=\"LayoutObjectList\"><Layout><Object type=\"Portal\" key=\"1\">"
            + "<Bounds top=\"0\" left=\"0\" bottom=\"100\" right=\"100\"/><PortalObj numOfRows=\"4\">"
            + "<Object type=\"Group\" key=\"5\"><Bounds top=\"0\" left=\"0\" bottom=\"20\" right=\"50\"/><GroupObj>"
            + "<Object type=\"Field\" key=\"6\"><Bounds top=\"60\" left=\"0\" bottom=\"80\" right=\"50\"/></Object>"
            + "</GroupObj></Object></PortalObj></Object></Layout></fmxmlsnippet>"
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: Data(probe.utf8)).count, 1)
    }

    func testOtherClassesAndBadXMLPass() {
        XCTAssertEqual(PortalCheck.problems(cls: .XMSS, data: clip("116", "24", "136", "234")), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: Data("<fmxmlsnippet".utf8)), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: Samples.data(for: .XML2)), [])
    }

    /// Copy Entry in the window: for a bad layout entry the app asks first. Cancel leaves the clipboard as it was,
    /// Copy Anyway copies. A good entry is copied with no question.
    func testCopyEntryRefusesABadPortal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(folder: folder)
        let bad = try store.add(clip("116", "24", "136", "234"), cls: .XML2, name: "bad")
        let good = try store.add(clip("4", "4", "24", "214"), cls: .XML2, name: "good")
        let model = AppModel(store: store, watch: false)
        let board = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let before = board.changeCount

        var asked: [String] = []
        var answer = false
        model.confirmPortalCopy = { message, done in asked.append(message); done(answer) }

        model.copy(bad, to: board)
        XCTAssertEqual(board.changeCount, before)
        XCTAssertEqual(asked.count, 1)
        XCTAssertTrue(asked[0].contains("outside the first row"), asked[0])
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(store.lastRestore())

        answer = true
        model.copy(bad, to: board)
        XCTAssertEqual(asked.count, 2)
        XCTAssertNotEqual(board.changeCount, before)
        XCTAssertEqual(board.data(forType: FMClass.XML2.pasteboardType), try store.data(for: bad))

        let afterBad = board.changeCount
        model.copy(good, to: board)
        XCTAssertEqual(asked.count, 2)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotEqual(board.changeCount, afterBad)
    }

    /// A capture keeps the clip as FileMaker Pro wrote it. A bad portal gives a warning; a real copy gives none.
    func testCaptureKeepsABadPortalWithAWarning() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(folder: folder)
        let model = AppModel(store: store, watch: false)

        model.capture([FMObject(cls: .XML2, data: try Self.fixture("portal-real.xml"))])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(store.entries.count, 1)

        model.capture([FMObject(cls: .XML2, data: clip("116", "24", "136", "234"))])
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(model.errorMessage?.hasPrefix("The app kept the capture, but Copy Entry will ask") == true,
                      model.errorMessage ?? "nil")
    }

    /// A capture with a name and a folder from the clipboard (FOPN, FOPF) keeps them, and still gets the portal
    /// warning when the check fails.
    func testCaptureWithNameAndFolderStillWarnsForABadPortal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(folder: folder)
        let model = AppModel(store: store, watch: false)
        let board = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }

        board.declareTypes([FMClass.XML2.pasteboardType, FMPasteboard.nameType, FMPasteboard.folderType], owner: nil)
        board.setData(clip("116", "24", "136", "234"), forType: FMClass.XML2.pasteboardType)
        board.setData(Data("Bad portal".utf8), forType: FMPasteboard.nameType)
        board.setData(Data("Layouts".utf8), forType: FMPasteboard.folderType)
        model.capture(FMPasteboard.read(board))

        let e = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(e.name, "Bad portal")
        XCTAssertEqual(e.folder, "Layouts")
        XCTAssertTrue(model.errorMessage?.hasPrefix("The app kept the capture, but Copy Entry will ask") == true,
                      model.errorMessage ?? "nil")

        // A good portal with a name and a folder: no warning.
        model.errorMessage = nil
        board.declareTypes([FMClass.XML2.pasteboardType, FMPasteboard.nameType, FMPasteboard.folderType], owner: nil)
        board.setData(try Self.fixture("portal-real.xml"), forType: FMClass.XML2.pasteboardType)
        board.setData(Data("Good portal".utf8), forType: FMPasteboard.nameType)
        board.setData(Data("Layouts".utf8), forType: FMPasteboard.folderType)
        model.capture(FMPasteboard.read(board))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(store.entries.first?.name, "Good portal")
        XCTAssertEqual(store.entries.first?.folder, "Layouts")
    }

    /// A temp history, a model on it, a private pasteboard, and a bad layout entry whose question stays open.
    /// `answer` answers the question later, as a sheet does.
    func pendingCopy() throws -> (HistoryStore, AppModel, NSPasteboard, HistoryEntry, (Bool) -> Void, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        let store = try HistoryStore(folder: folder)
        let bad = try store.add(clip("116", "24", "136", "234"), cls: .XML2, name: "bad")
        let model = AppModel(store: store, watch: false)
        var answer: ((Bool) -> Void)?
        model.confirmPortalCopy = { _, done in answer = done }
        let board = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        board.clearContents()
        model.copy(bad, to: board)
        return (store, model, board, bad, try XCTUnwrap(answer), folder)
    }

    /// The review's case: while the question is open, a Replace puts other XML with another class under the same
    /// id. Copy Anyway then copies nothing, and the app says why.
    func testCopyAnywayAfterAReplaceCopiesNothing() throws {
        let (store, model, board, bad, answer, folder) = try pendingCopy()
        defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
        let before = board.changeCount

        let newData = Data("<fmxmlsnippet type=\"FMObjectList\"><Step enable=\"True\" id=\"89\" name=\"# (comment)\"/></fmxmlsnippet>".utf8)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bad)) as? [String: Any])
        json["class"] = "XMSS"
        json["sha256"] = HistoryStore.sha256(newData)
        json["canonical"] = Canonical.key(for: newData)
        let newEntry = try JSONDecoder().decode(HistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        let backup = Backup(created: bad.time, folders: [], settings: nil, items: [.init(entry: newEntry, data: newData)])
        try store.replace(with: try Backup.decode(backup.encoded()))
        model.reloadFromDisk()
        XCTAssertEqual(store.entry(id: bad.id)?.cls, .XMSS)

        answer(true)
        XCTAssertEqual(board.changeCount, before)
        XCTAssertNil(board.data(forType: FMClass.XML2.pasteboardType))
        XCTAssertNil(board.data(forType: FMClass.XMSS.pasteboardType))
        XCTAssertEqual(model.errorMessage, "The history changed while the question was open, so the app did not copy the entry.")
    }

    /// The entry is deleted (here by another store, as the CLI does) while the question is open: no copy.
    func testCopyAnywayAfterADeleteCopiesNothing() throws {
        let (_, model, board, bad, answer, folder) = try pendingCopy()
        defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
        let before = board.changeCount
        try HistoryStore(folder: folder).delete(ids: [bad.id])

        answer(true)
        XCTAssertEqual(board.changeCount, before)
        XCTAssertTrue(model.errorMessage?.hasPrefix("The history changed") == true, model.errorMessage ?? "nil")
    }

    /// With no change, a late Copy Anyway copies the bytes that were read before the question.
    func testLateCopyAnywayCopiesTheApprovedBytes() throws {
        let (store, model, board, bad, answer, folder) = try pendingCopy()
        defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
        answer(true)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(board.data(forType: FMClass.XML2.pasteboardType), clip("116", "24", "136", "234"))
        XCTAssertEqual(store.lastRestore()?.id, bad.id)
    }
}
