import AppKit

/// One FileMaker object on a pasteboard: its class, its data (UTF-8 XML), and the optional entry name and folder
/// that the tool that wrote the pasteboard gave it (see `FMPasteboard.nameType` and `FMPasteboard.folderType`).
public struct FMObject: Equatable, Sendable {
    public let cls: FMClass
    public let data: Data
    public let name: String?
    public let folder: String?

    public init(cls: FMClass, data: Data, name: String? = nil, folder: String? = nil) {
        self.cls = cls
        self.data = data
        self.name = name
        self.folder = folder
    }
}

/// Reads and writes the FileMaker classes on a pasteboard. Other contents (plain text and others) are ignored.
public enum FMPasteboard {
    /// The pasteboard class `FOPN`: the name of the entry (UTF-8 text). A tool that puts FileMaker objects on the
    /// clipboard can add it next to the FileMaker class. FileMaker Pro ignores it.
    public static let nameType = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x464F504E")

    /// The pasteboard class `FOPF`: the folder of the entry (UTF-8 text). FileMaker Pro ignores it.
    public static let folderType = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x464F5046")

    /// The FileMaker objects that are on the pasteboard now, with the name and the folder if the pasteboard has them.
    public static func read(_ pasteboard: NSPasteboard = .general) -> [FMObject] {
        let name = readName(pasteboard)
        let folder = readFolder(pasteboard)
        return FMClass.allCases.compactMap { cls in
            guard let data = pasteboard.data(forType: cls.pasteboardType), !data.isEmpty else { return nil }
            return FMObject(cls: cls, data: data, name: name, folder: folder)
        }
    }

    /// The name on the pasteboard (class `FOPN`), or nil if there is no name (see `cleanLabel`).
    public static func readName(_ pasteboard: NSPasteboard = .general) -> String? {
        pasteboard.data(forType: nameType).flatMap(cleanLabel)
    }

    /// The folder on the pasteboard (class `FOPF`), or nil if there is no folder (see `cleanLabel`).
    public static func readFolder(_ pasteboard: NSPasteboard = .general) -> String? {
        pasteboard.data(forType: folderType).flatMap(cleanLabel)
    }

    /// The maximum length of a name or a folder from the clipboard, in characters.
    public static let maxLabelLength = 200

    /// The text of a `FOPN` or `FOPF` value, made safe to keep:
    /// - Data that is not valid UTF-8 gives nil.
    /// - Line breaks and tabs become spaces. The other control characters (C0, DEL and C1, for example NUL) go away.
    /// - The spaces at the two ends go away, and the text is cut to `maxLabelLength` characters.
    /// - An empty result gives nil, the same as no value.
    public static func cleanLabel(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var scalars = String.UnicodeScalarView()
        for u in text.unicodeScalars {
            if CharacterSet.newlines.contains(u) || u == "\t" {
                scalars.append(" ")
            } else if u.properties.generalCategory != .control {  // Cc: C0, DEL and C1
                scalars.append(u)
            }
        }
        guard let clean = HistoryStore.cleanName(String(scalars)) else { return nil }
        return HistoryStore.cleanName(String(clean.prefix(maxLabelLength)))
    }

    /// Puts the data on the pasteboard with the class. Returns the new change count, or nil if the pasteboard refused the data.
    @discardableResult
    public static func write(_ data: Data, as cls: FMClass, to pasteboard: NSPasteboard = .general) -> Int? {
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: cls.pasteboardType) else { return nil }
        return pasteboard.changeCount
    }
}
