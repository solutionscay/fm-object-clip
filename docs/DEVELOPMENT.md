# Development

This page is for people who build, test or change fm-object-clip. For how to install and use the app, see [the README](../README.md).

## Requirements

- macOS 13 or later.
- Xcode 15 or later (Swift 5.9 or later), or the Xcode Command Line Tools.

## Build and test

Clone the repository and run the commands in its root folder.

```bash
swift build          # debug build
swift test           # the tests
swift run FMObjectClip
```

The tests use a private pasteboard and a temporary folder. They do not change your clipboard or your history.

## The app bundle

```bash
scripts/make-app.sh
```

The script builds the release binaries. It puts the app in `build/FMObjectClip.app` (bundle ID `com.solutionscay.fm-object-clip`), with an `Info.plist` and the icon. It puts the command-line tool in `build/bin/fm-object-clip-cli` and in `build/FMObjectClip.app/Contents/MacOS/fm-object-clip-cli`. Git ignores `build/`.

The script also writes the SDK version into the binary, because SwiftPM writes the deployment target (13.0) there. Without the SDK version, macOS 26 shows the app without Liquid Glass.

The binary has an ad hoc signature, because Apple silicon runs only signed code. The bundle has no Developer ID signature and is not notarized. To open the app, double-click `build/FMObjectClip.app` in Finder, or run `open build/FMObjectClip.app`. If macOS does not open the app the first time, right-click the app and select **Open**. To install it, copy `build/FMObjectClip.app` to `/Applications`.

## The icon

The icon is `Resources/AppIcon.icns`. `scripts/make-icon.swift` draws it, and `scripts/make-icon.sh` makes the `.icns` file with `sips` and `iconutil`. To change the icon, change `make-icon.swift` and run `scripts/make-icon.sh`.

## Package layout

One Swift package (`Package.swift`) with 3 targets and the test target `FMClipCoreTests`:

| Target | Type | What it does |
|---|---|---|
| `FMClipCore` | Library | Reads and writes the pasteboard classes. Keeps the history. |
| `fm-object-clip-cli` | Command-line tool | Reads and manages the history, for scripts and agents. |
| `FMObjectClip` | App (SwiftUI) | The main window and the menus |

The command-line tool has its own reference: [CLI.md](CLI.md).

## Test and demo history: `-HistoryFolder`

To test or to make screenshots without your real history, start the app with `-HistoryFolder PATH`, for example `open -n build/FMObjectClip.app --args -HistoryFolder ~/Desktop/demo-history`. The app then uses that folder in place of the real history: it reads and writes the entries, the folders and the settings there, and the safety backups of a restore go to the `backups` folder next to it. A note under the list shows the path of the folder (`~` for your home folder), and **About fm-object-clip** shows the full path. A leading `~` is your home folder. With no argument, or an empty one, the app uses the real history. The CLI uses `--history DIR` for the same purpose.

## Clipboard capture

The app checks the clipboard (`NSPasteboard.changeCount`) every 0.4 seconds, because macOS does not send an event when the clipboard changes. After a change, the app waits until two checks in a row read the same contents, or until 1.2 seconds have gone by. Then it captures the contents one time. So a copy is in the history 0.4 to 0.8 seconds after Cmd+C, when its contents do not change. If the clipboard changes again before the capture, the app drops the first contents and waits for the new ones. Contents with no FileMaker class (for example plain text) do not wait: at the first check, the app forgets the entry that **Copy Entry** or `restore` put on the clipboard. So the next FileMaker copy of that entry moves it to the top. Any program that puts one of the classes below on the clipboard is captured the same way as FileMaker Pro.

| Class | Objects | Label in the app |
|---|---|---|
| `XMSS` | Script steps | Scripts |
| `XMTB` | Tables | Tables |
| `XMFD` | Fields | Fields |
| `XML2` | Layout objects | Layout |

The pasteboard type of a class is `CorePasteboardFlavorType 0x` followed by the hex of the 4 ASCII letters. For example, the type of `XMSS` is `CorePasteboardFlavorType 0x584D5353`.

## Name and folder from the clipboard

A tool that puts FileMaker objects on the clipboard can add two more classes. They give the entry a name and put it in a folder. FileMaker Pro does not know these classes, so it pastes the FileMaker class only.

| Class | Pasteboard type | Value |
|---|---|---|
| `FOPN` | `CorePasteboardFlavorType 0x464F504E` | The name of the entry |
| `FOPF` | `CorePasteboardFlavorType 0x464F5046` | The folder of the entry |

Each class is optional. The app capture, `fm-object-clip-cli watch` and `fm-object-clip-cli info` read them.

### Write all the classes in one clipboard write

The change count of the clipboard changes when a program clears it or declares its types. It does not change when the program sets the data of one more type. So the app cannot see when a write is complete. It waits until the clipboard is stable (up to about 1 second, see [Clipboard capture](#clipboard-capture)), and then it captures one time. A value that arrives after the capture is ignored.

Do this:

1. Declare all the types at once: the FileMaker class, `FOPN` and `FOPF`.
2. Set the data of each type at once, with no wait between the calls.

```swift
let fm = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x584D5353")    // XMSS
let name = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x464F504E")  // FOPN
let folder = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x464F5046") // FOPF
let pb = NSPasteboard.general
pb.declareTypes([fm, name, folder], owner: nil)
pb.setData(xmlData, forType: fm)
pb.setData(Data("Invoice - Create PDF".utf8), forType: name)
pb.setData(Data("Invoicing".utf8), forType: folder)
```

Do not use `clearContents` and then one `setData` call for each type: then the types arrive one by one. Do not use `NSPasteboardItem` with these type names. It refuses them (`setData` returns false and logs "is not a valid UTI string").

If a tool sets the data slowly, with a pause between the calls, the capture can come before the name or the folder. Then the entry has no name, or it goes to the **Uncategorized** group. The app does not change the entry later. So write all the classes together.

### How the app reads the values

- The data must be UTF-8 text. Data that is not valid UTF-8 is the same as no value.
- Line breaks and tabs become spaces. The app removes the other control characters (for example NUL).
- The app removes the spaces at the start and the end, and keeps the first 200 characters.
- An empty value is the same as no value.
- If one clipboard write has more than one FileMaker class, each object gets the same name and the same folder. FileMaker Pro itself puts one of these classes on the clipboard at a time.

### What the app does with them

- If the folder does not exist, the app makes it. The match with an existing folder ignores case: `project a` goes into `Project A`.
- An entry with a folder is not in the **Uncategorized** group, so it does not count for the Uncategorized limit, and the app never deletes it for the limit. An entry with no `FOPF` goes to the **Uncategorized** group and counts. It can make the app delete the oldest uncategorized entry.
- A folder value that is the name of the Uncategorized group is the same as no folder. The app compares it with the name in Settings and with the default name "Uncategorized", and ignores case. So no folder named "Uncategorized" is made. The exception: if you made a folder with that name yourself, the entry goes into that folder.
- If the class and the XML are the same as an entry, the app does not make a new entry. It moves that entry to the top, and a new name or a new folder replaces the old one. With a folder, the entry leaves the **Uncategorized** group. With no `FOPF` (or the Uncategorized name), the entry stays in its folder.
- **Copy Entry** and `fm-object-clip-cli restore` put the FileMaker class only, not the name or the folder.
- The rule for the Uncategorized name is for the clipboard only. `fm-object-clip-cli add --folder Uncategorized` makes a folder with that name, as before.

## History files

The history is in `~/Library/Application Support/fm-object-clip/history/`. Your history can contain the names and logic of your FileMaker solutions, so do not commit it to a public repository.

- Each entry is one file, `<id>.xml`. The file has the clipboard data as UTF-8 XML, with no changes.
- The file `index.json` has one item for each entry, with these fields:

| Field | Value |
|---|---|
| `id` | An id that is different for each entry. It is also the name of the `.xml` file. |
| `class` | `XMSS`, `XMTB`, `XMFD` or `XML2` |
| `time` | The time of the capture, in ISO 8601 |
| `title` | A short name from the XML. For a script: the first comment that has text, and the count of steps. If no comment has text, the first step that does something (not `Set Error Capture`, `Allow User Abort`, `Freeze Window` or `Enter Browse Mode`), as a short preview. |
| `titleVersion` | The version of the title rules. When the rules change, the app or the CLI makes the title again one time for each entry. |
| `sha256` | The hash of the data |
| `source` | `clipboard`, or `cli` for an entry from `fm-object-clip-cli add` |
| `name` | Optional. The name from **Rename** or from `fm-object-clip-cli add --name`. The window shows it in place of `title`. |
| `folder` | Optional. The folder of the entry. |
| `canonical` | The SHA-256 of the canonical XML, for the duplicate check. An entry from an earlier version can have no value. The app adds it when it needs it. |

- The file `folders.json` has the names of the folders, also the empty folders, in the order of the list.
- The file `settings.json` has the settings (see [Settings](../README.md#settings)).
- The file `.last-restore.json` has the class and the hashes of the last entry that **Copy Entry** or `fm-object-clip-cli restore` put on the clipboard. When the clipboard gets other contents, the app deletes the file.
- The file `.generation` changes at each **Replace** from a backup (app or CLI). When an open window sees a new value, it clears its Undo steps, so that an Undo cannot bring entries of the old history into the new one.
- The history keeps 500 uncategorized entries (entries in no folder). You can change the limit in **Settings**. When there are more uncategorized entries, the app or the CLI deletes the oldest uncategorized entries. Entries in folders do not count, and the app never deletes them.
- If a new capture has the same class and the same content as an entry, the app does not add a new entry. It moves the old entry to the top, and the entry keeps the bytes of the first capture. The same content is the same bytes, or the same canonical XML.
- A copy from the app (**Copy Entry**) or from `fm-object-clip-cli restore` does not change the entry. The entry keeps its time and its place. When you paste, FileMaker Pro can put the same object on the clipboard again. The app does not move the entry for this capture. The rule stops when the clipboard gets other contents. Then an identical copy in FileMaker Pro moves the entry to the top again.
- The canonical XML does not include these items:
  - the XML declaration
  - the whitespace between elements
  - the order of the attributes
  - character references
  - the form of empty elements (`<a/>` or `<a></a>`)
- FileMaker Pro can put one script on the clipboard two times, a few seconds apart. First it puts compact XML. Then it puts pretty-printed XML with a declaration and a text flavor. The two captures give one entry.

The files are plain XML and JSON. Scripts and agents can read them without the app.

## Backup file format

A backup is one file with the full history: all the entries with their XML, all the folders in their order, and the settings. The file is UTF-8 JSON, pretty-printed, with sorted keys:

| Field | Value |
|---|---|
| `format` | `fm-object-clip-backup` |
| `version` | `1`. The app refuses a higher version. |
| `created` | The time of the backup, ISO 8601 |
| `folders` | The folder names, in their order |
| `settings` | The object of `settings.json`, or `null` |
| `entries` | The entries, newest first. Each entry has the fields of `index.json`, and `data`: the XML bytes in base64. The bytes must agree with `sha256`. |

The command-line tool has the same operations: `backup FILE` and `import-backup FILE [--replace]`.

