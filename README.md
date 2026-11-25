# fm-object-clip

fm-object-clip is a clipboard history for FileMaker Pro objects on macOS.

When you copy script steps, tables, fields or layout objects in FileMaker Pro, the app keeps a copy. You can give the copies names and sort them into folders. Later, you select a copy in the app, the app puts it on the clipboard again, and you paste it in FileMaker Pro with Cmd+V.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/01-main-window-dark.png">
  <img src="docs/screenshots/01-main-window-light.png" width="860" alt="The fm-object-clip window. On the left, the folders Invoicing, CRM and Snippets and the Uncategorized group list the captured objects, each with a colored type badge (Scripts, Layout, Fields, Tables) and a date. On the right, the selected script, Invoice - Create PDF, shows its steps.">
</picture>

fm-object-clip keeps only FileMaker objects. It never keeps plain text, and no setting changes this.

## Requirements

- macOS 13 or later. On macOS 26 and later, the window uses Liquid Glass.
- FileMaker Pro for macOS, to copy and paste the objects.
- To build the app: Xcode 15 or later, or the Xcode Command Line Tools.

## Install

There is no download yet. You build the app from the source code.

1. Install Xcode or the Xcode Command Line Tools (`xcode-select --install`).
2. Get the source code and build the app:

   ```bash
   git clone https://github.com/solutionscay/fm-object-clip.git
   cd fm-object-clip
   scripts/make-app.sh
   ```

3. Copy `build/FMObjectClip.app` to your `Applications` folder.
4. Open the app. If macOS refuses to open it the first time, right-click the app and select **Open**. See [FAQ and troubleshooting](https://github.com/solutionscay/fm-object-clip/wiki/FAQ-and-Troubleshooting#macos-does-not-open-the-app).

## Quick start

1. Keep the app open. In FileMaker Pro, copy script steps, tables, fields or layout objects (Cmd+C).
2. The copy shows in the app. Double-click it to put it on the clipboard again.
3. In FileMaker Pro, press Cmd+V.
4. Drag entries to folders to keep them. The app keeps 500 entries in no folder, and deletes the oldest when there are more.

## Documentation

The full guide is in the [wiki](https://github.com/solutionscay/fm-object-clip/wiki):

- [Usage guide](https://github.com/solutionscay/fm-object-clip/wiki/Usage-Guide) · [Folders](https://github.com/solutionscay/fm-object-clip/wiki/Folders) · [Find and Show XML](https://github.com/solutionscay/fm-object-clip/wiki/Find-and-Show-XML)
- [Settings](https://github.com/solutionscay/fm-object-clip/wiki/Settings) · [Backup and restore](https://github.com/solutionscay/fm-object-clip/wiki/Backup-and-Restore) · [Menus and shortcuts](https://github.com/solutionscay/fm-object-clip/wiki/Menus-and-Shortcuts)
- [Command-line tool](https://github.com/solutionscay/fm-object-clip/wiki/Command-Line-Tool) · [History files](https://github.com/solutionscay/fm-object-clip/wiki/History-Files) · [Clipboard format for tool authors](https://github.com/solutionscay/fm-object-clip/wiki/Clipboard-Format)
- [FAQ and troubleshooting](https://github.com/solutionscay/fm-object-clip/wiki/FAQ-and-Troubleshooting), with the limits of the app

To build, test or change the code, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

fm-object-clip is open source under the [MIT License](LICENSE). Copyright (c) 2026 Solutions Cay LLC.
