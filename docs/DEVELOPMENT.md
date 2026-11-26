# Development

This page is for people who build, test or change fm-object-clip. For how to install and use the app, see the [wiki](https://github.com/solutionscay/fm-object-clip/wiki).

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

The command-line tool has its own reference: [Command-Line Tool](https://github.com/solutionscay/fm-object-clip/wiki/Command-Line-Tool).

## Test and demo history: `-HistoryFolder`

To test or to make screenshots without your real history, start the app with `-HistoryFolder PATH`, for example `open -n build/FMObjectClip.app --args -HistoryFolder ~/Desktop/demo-history`. The app then uses that folder in place of the real history: it reads and writes the entries, the folders and the settings there, and the safety backups of a restore go to the `backups` folder next to it. A note under the list shows the path of the folder (`~` for your home folder), and **About fm-object-clip** shows the full path. A leading `~` is your home folder. With no argument, or an empty one, the app uses the real history. The CLI uses `--history DIR` for the same purpose.

## Clipboard capture

The app checks the clipboard (`NSPasteboard.changeCount`) every 0.4 seconds, because macOS does not send an event when the clipboard changes. After a change, the app waits until two checks in a row read the same contents, or until 1.2 seconds have gone by. Then it captures the contents one time. So a copy is in the history 0.4 to 0.8 seconds after Cmd+C, when its contents do not change. If the clipboard changes again before the capture, the app drops the first contents and waits for the new ones. Contents with no FileMaker class (for example plain text) do not wait: at the first check, the app forgets the entry that **Copy Entry** or `restore` put on the clipboard. So the next FileMaker copy of that entry moves it to the top. Any program that puts one of the FileMaker classes (`XMSS`, `XMTB`, `XMFD` or `XML2`) on the clipboard is captured the same way as FileMaker Pro.

The classes, the pasteboard type names, the `FOPN` and `FOPF` classes for the name and the folder, and how a tool must write them are on the wiki page [Clipboard Format](https://github.com/solutionscay/fm-object-clip/wiki/Clipboard-Format). The history and backup file formats are on [History Files](https://github.com/solutionscay/fm-object-clip/wiki/History-Files).

## Change the documentation

The user guide and the reference are on the [wiki](https://github.com/solutionscay/fm-object-clip/wiki). A pull request cannot change the wiki. If your change alters a CLI command, its JSON, a history or backup file, or the clipboard format, say so in the pull request, and paste the new text for the wiki page. The maintainer updates the wiki when the pull request is merged.

Change this file, and the README, in the pull request itself.
