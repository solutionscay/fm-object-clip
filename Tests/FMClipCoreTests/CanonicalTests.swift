import AppKit
import XCTest
@testable import FMClipCore

/// The canonical dedupe. The XML here is synthetic, made for the test.
final class CanonicalTests: XCTestCase {
    // The form that FileMaker puts on the clipboard first: compact, no declaration.
    let compact = ##"<fmxmlsnippet type="FMObjectList"><Step enable="True" id="89" name="# (comment)"><Text>Line one&#10;line two</Text></Step><Step enable="True" id="141" name="Set Variable"><Value><Calculation><![CDATA[Get ( ScriptParameter )]]></Calculation></Value><Repetition><Calculation><![CDATA[1]]></Calculation></Repetition><Name>$x</Name></Step><Step enable="False" id="93" name="Beep"></Step><Field table="T" id="1" name="a&#10;b" note="say &quot;hi&quot;"></Field></fmxmlsnippet>"##

    // The second form: declaration, 2-space indent, self-closing empty elements, decoded references,
    // attributes in another order.
    let pretty = """
    <?xml version="1.0" encoding="UTF-8"?>
    <fmxmlsnippet type="FMObjectList">
      <Step enable="True" id="89" name="# (comment)">
        <Text>Line one
    line two</Text>
      </Step>
      <Step name="Set Variable" enable="True" id="141">
        <Value>
          <Calculation><![CDATA[Get ( ScriptParameter )]]></Calculation>
        </Value>
        <Repetition>
          <Calculation><![CDATA[1]]></Calculation>
        </Repetition>
        <Name>$x</Name>
      </Step>
      <Step enable="False" id="93" name="Beep"/>
      <Field table="T" id="1" name="a
    b" note='say "hi"'/>
    </fmxmlsnippet>

    """

    func key(_ s: String) -> String? { Canonical.key(for: Data(s.utf8)) }

    func testCompactAndPrettyFormsHaveTheSameKey() {
        XCTAssertNotNil(key(compact))
        XCTAssertEqual(key(compact), key(pretty))
    }

    func testDifferentContentHasADifferentKey() {
        XCTAssertNotEqual(key(compact), key(compact.replacingOccurrences(of: "$x", with: "$y")))
        XCTAssertNotEqual(key(compact), key(compact.replacingOccurrences(of: #"enable="False""#, with: #"enable="True""#)))
        XCTAssertNotEqual(key(compact), key(compact.replacingOccurrences(of: "Line one", with: "Line 1")))
        XCTAssertNotEqual(key("<a><b>x</b></a>"), key("<a><b> x </b></a>"))  // whitespace in real text counts
    }

    func testCDATAAndEscapedTextAreTheSame() {
        XCTAssertEqual(key("<a><c><![CDATA[1 < 2]]></c></a>"), key("<a><c>1 &lt; 2</c></a>"))
    }

    func testNotXMLHasNoKey() {
        XCTAssertNil(key("not xml"))
        XCTAssertNil(key("<a><b></a>"))
        XCTAssertNil(Canonical.key(for: Data()))
    }

    func testSampleAndItsCompactFormHaveTheSameKey() throws {
        for cls in FMClass.allCases {
            let data = Samples.data(for: cls)
            var text = String(decoding: data, as: UTF8.self)
            if let end = text.range(of: "?>"), text.hasPrefix("<?xml") { text = String(text[end.upperBound...]) }
            let squeezed = text.replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(Canonical.key(for: data), key(squeezed), "\(cls)")
        }
    }

    // MARK: - Store

    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testStoreKeepsOneEntryWithTheFirstBytes() throws {
        let store = try HistoryStore(folder: folder)
        let first = try store.add(Data(compact.utf8), cls: .XMSS, now: Date(timeIntervalSince1970: 1000))
        let second = try store.add(Data(pretty.utf8), cls: .XMSS, now: Date(timeIntervalSince1970: 1004))
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(try store.data(for: store.entries[0]), Data(compact.utf8))  // the bytes of the first capture
        XCTAssertNotEqual(store.entries[0].time, first.time)  // the time of the last capture
        XCTAssertEqual(store.entries[0].canonical, key(compact))
        // Another class with the same XML is another entry.
        try store.add(Data(pretty.utf8), cls: .XMFD)
        XCTAssertEqual(store.entries.count, 2)
    }

    func testOldEntryWithoutCanonicalKeyIsAlsoFound() throws {
        let store = try HistoryStore(folder: folder)
        let first = try store.add(Data(compact.utf8), cls: .XMSS)
        // An index from an earlier version has no canonical field.
        let indexURL = folder.appendingPathComponent("index.json")
        var items = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as! [[String: Any]]
        items[0].removeValue(forKey: "canonical")
        try JSONSerialization.data(withJSONObject: items).write(to: indexURL)

        let again = try HistoryStore(folder: folder)
        XCTAssertNil(again.entries[0].canonical)
        let second = try again.add(Data(pretty.utf8), cls: .XMSS)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(again.entries.count, 1)
        XCTAssertEqual(try HistoryStore(folder: folder).entries[0].canonical, key(compact))  // saved now
    }

    func testCaptureFromThePasteboardTwoFormsGiveOneEntry() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(folder: folder)
        var captures = 0
        let watcher = ClipboardWatcher(pasteboard: pasteboard) { objects in
            for o in objects { _ = try? store.add(o.data, cls: o.cls); captures += 1 }
        }
        // FileMaker: first the compact XMSS, then the pretty XMSS with a text flavor.
        FMPasteboard.write(Data(compact.utf8), as: .XMSS, to: pasteboard)
        watcher.settle()
        pasteboard.clearContents()
        pasteboard.setData(Data(pretty.utf8), forType: FMClass.XMSS.pasteboardType)
        pasteboard.setString(pretty, forType: .string)
        watcher.settle()
        XCTAssertEqual(captures, 2)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(try store.data(for: store.entries[0]), Data(compact.utf8))
    }
}
