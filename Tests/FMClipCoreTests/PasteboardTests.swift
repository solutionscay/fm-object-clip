import AppKit
import XCTest
@testable import FMClipCore

final class PasteboardTests: XCTestCase {
    var pasteboard: NSPasteboard!

    override func setUp() {
        // A private, named pasteboard. The tests never use the general clipboard.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    func testClassList() {
        XCTAssertEqual(FMClass.allCases.map(\.rawValue), ["XMSS", "XMTB", "XMFD", "XML2"])
    }

    func testTypeNames() {
        XCTAssertEqual(FMClass.XMSS.pasteboardType.rawValue, "CorePasteboardFlavorType 0x584D5353")
        XCTAssertEqual(FMClass.XMTB.pasteboardType.rawValue, "CorePasteboardFlavorType 0x584D5442")
        XCTAssertEqual(FMClass.XMFD.pasteboardType.rawValue, "CorePasteboardFlavorType 0x584D4644")
        XCTAssertEqual(FMClass.XML2.pasteboardType.rawValue, "CorePasteboardFlavorType 0x584D4C32")
    }

    func testWriteAndReadEachClass() throws {
        for cls in FMClass.allCases {
            let data = Samples.data(for: cls)
            XCTAssertNotNil(FMPasteboard.write(data, as: cls, to: pasteboard))
            XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: cls, data: data)])
        }
    }

    func testPlainTextIsIgnored() {
        pasteboard.clearContents()
        pasteboard.setString("<fmxmlsnippet/>", forType: .string)
        XCTAssertEqual(FMPasteboard.read(pasteboard), [])
    }

    func testWatcherCapturesOnlyNewFileMakerContents() throws {
        var captured: [FMObject] = []
        let watcher = ClipboardWatcher(pasteboard: pasteboard) { captured += $0 }
        XCTAssertEqual(watcher.poll(), [])  // no change

        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)
        XCTAssertEqual(watcher.settle(), [])
        XCTAssertTrue(captured.isEmpty)

        let data = Samples.data(for: .XMSS)
        FMPasteboard.write(data, as: .XMSS, to: pasteboard)
        XCTAssertEqual(watcher.settle().map(\.cls), [.XMSS])
        XCTAssertEqual(watcher.poll(), [])  // same change count
        XCTAssertEqual(captured.count, 1)

        let count = FMPasteboard.write(data, as: .XMSS, to: pasteboard)!
        watcher.ignore(changeCount: count)
        XCTAssertEqual(watcher.settle(), [])
        XCTAssertEqual(captured.count, 1)
    }
}
