import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// The name and folder classes (FOPN, FOPF) that a tool can put next to the FileMaker class on the clipboard.
final class NameFolderFlavorTests: XCTestCase {
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

    /// One clipboard write, as a tool makes it: the FileMaker class, and the name and the folder if given.
    /// All the types are declared at once (see the Clipboard Format page of the wiki).
    func put(_ data: Data, _ cls: FMClass, name: String? = nil, folder: String? = nil) {
        var types = [cls.pasteboardType]
        if name != nil { types.append(FMPasteboard.nameType) }
        if folder != nil { types.append(FMPasteboard.folderType) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setData(data, forType: cls.pasteboardType)
        if let name { pasteboard.setData(Data(name.utf8), forType: FMPasteboard.nameType) }
        if let folder { pasteboard.setData(Data(folder.utf8), forType: FMPasteboard.folderType) }
    }

    func testTheTypesKeepTheirCodes() {
        XCTAssertEqual(FMPasteboard.nameType.rawValue, "CorePasteboardFlavorType 0x464F504E")  // FOPN
        XCTAssertEqual(FMPasteboard.folderType.rawValue, "CorePasteboardFlavorType 0x464F5046")  // FOPF
    }

    func testReadNameAndFolder() {
        let data = Samples.data(for: .XMSS)
        put(data, .XMSS, name: "  Count contacts – no email \n", folder: " Project A ")
        XCTAssertEqual(FMPasteboard.read(pasteboard),
                       [FMObject(cls: .XMSS, data: data, name: "Count contacts – no email", folder: "Project A")])
    }

    func testNoValueOrEmptyValueIsNil() {
        let data = Samples.data(for: .XML2)
        put(data, .XML2)
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XML2, data: data)])
        put(data, .XML2, name: "   ", folder: "")
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XML2, data: data)])
    }

    func testNameAndFolderAloneAreNotAnObject() {
        pasteboard.clearContents()
        pasteboard.setData(Data("Name".utf8), forType: FMPasteboard.nameType)
        pasteboard.setData(Data("Folder".utf8), forType: FMPasteboard.folderType)
        XCTAssertEqual(FMPasteboard.read(pasteboard), [])
    }

    /// The window capture keeps the name and the folder. Copy Entry puts the FileMaker class only.
    func testWindowCaptureUsesNameAndFolder() throws {
        let store = try HistoryStore(folder: folder)
        let model = AppModel(store: store, watch: false)
        let data = Samples.data(for: .XML2)
        put(data, .XML2, name: "Contact card", folder: "Project A")
        model.capture(FMPasteboard.read(pasteboard))
        XCTAssertNil(model.errorMessage)

        let e = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(e.name, "Contact card")
        XCTAssertEqual(e.folder, "Project A")
        XCTAssertEqual(store.folders, ["Project A"])
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: e)), data)  // the bytes do not change

        // The same XML again with a new folder and no name: one entry, new folder, the name stays.
        put(data, .XML2, folder: "Project B")
        model.capture(FMPasteboard.read(pasteboard))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].folder, "Project B")
        XCTAssertEqual(store.entries[0].name, "Contact card")

        try store.copy(store.entries[0], to: pasteboard)
        XCTAssertNil(pasteboard.data(forType: FMPasteboard.nameType))
        XCTAssertNil(pasteboard.data(forType: FMPasteboard.folderType))
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XML2, data: data)])
    }
}
