# fm-object-clip

fm-object-clip is a clipboard history for FileMaker Pro objects on macOS.

When you copy script steps, tables, fields or layout objects in FileMaker Pro, the app keeps a copy. You can give the copies names and sort them into folders. Later, you select a copy in the app, the app puts it on the clipboard again, and you paste it in FileMaker Pro with Cmd+V.

Use it to keep the script steps, fields and layout objects that you use again in many solutions, or to move objects from one file to another without losing them when you copy something else.

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
4. Open the app. The app has no Developer ID signature, so macOS can refuse to open it the first time. If this occurs, right-click the app and select **Open**.

The script also makes the command-line tool, in `build/bin/fm-object-clip-cli`. See [Command-line tool](#command-line-tool).

## Use the app

### Copy objects in FileMaker Pro

Keep the app open. In FileMaker Pro, copy objects as usual with Cmd+C. For example, copy script steps in the Script Workspace, tables or fields in **Manage Database**, or objects on a layout in Layout mode. The app adds each copy to its history.

The app captures these types:

| Type in the app | What you copied in FileMaker Pro |
|---|---|
| Scripts | Script steps |
| Tables | Tables |
| Fields | Fields |
| Layout | Layout objects |

The app does not capture plain text or other FileMaker clipboard types, for example custom functions (`XMFN`), the older layout type `XMLO`, whole scripts or value lists.

If you copy the same object again, the app does not make a second entry. It moves the old entry to the top.

A tool that puts FileMaker objects on the clipboard can also give the entry a name and a folder. See [Name and folder from the clipboard](docs/DEVELOPMENT.md#name-and-folder-from-the-clipboard).

When you close the window, the app continues to keep your copies. To open the window again, click the app in the Dock, or select **Window** > **History Window** (Cmd+0). To stop the app, press Cmd+Q.

### Paste an object again

1. In the app, double-click the entry. Or select it and press Return, or select **File** > **Copy Entry** (Cmd+C).
2. The row shows a green check mark and "Copied" for approximately 1 second.
3. In FileMaker Pro, go to the place for the object (for example, the Script Workspace) and press Cmd+V.

The app does not paste into FileMaker Pro for you. A copy from the app does not change the entry or its place in the list.

### Sort entries into folders

Use folders to keep the entries of one project or one topic together. Folders are flat: a folder cannot contain a folder. An entry is in one folder or in no folder. The entries in no folder are in the **Uncategorized** group, after the folders.

- **Make a folder:** select **File** > **New Folder…** (Cmd+Shift+N), or right-click a folder row.
- **Move entries to a folder:** drag the entries to the folder row. Or select **File** > **Move to Folder**, or right-click an entry and select **Move to Folder**.
- **Take an entry out of its folder:** drag it to the **Uncategorized** group, or select **Move to Folder** > **Uncategorized**.
- **Change the order of the folders:** drag a folder row up or down. A line shows where the folder goes. You can also select a folder and select **File** > **Move Folder Up** or **Move Folder Down**, or use the same items on the right-click menu of the folder. The **Uncategorized** group always stays last.
- **Rename or delete a folder:** right-click the folder row, or select it and use **File** > **Rename Folder…** or **Delete Folder**. When you delete a folder, its entries go to the **Uncategorized** group. The app does not delete them.
- **Open or close a folder:** click the folder row. The app keeps the open folders between launches.

In a folder where all the entries have names, the entries are in the order of their names ("2" comes before "10"). In other folders and in the **Uncategorized** group, the newest entry is at the top.

To undo a folder move or a delete, select **Edit** > **Undo** (Cmd+Z).

### Find an entry

- **Filter by type:** click All, Scripts, Tables, Fields or Layout at the top of the window, or use **View** > **All Types** (Cmd+1) to **Layout** (Cmd+5).
- **Search:** type in the search field. The search finds text in the name, in the automatic title and in the XML.

While a filter or a search is active, the list shows only the folders that have a match, and these folders are open.

### See the contents and the XML

When you select an entry, the right side shows a short summary of it. For a script, you see one line for each step. For tables, you see each table and its fields. For fields, you see the name, the type and the options of each field. For layout objects, you see the number of objects of each type and the field names.

To see the full XML, turn on the **Show XML** switch at the top right, or select **View** > **Show XML** (Cmd+Option+X). The XML has indents and colors.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/02-xml-script-dark.png">
  <img src="docs/screenshots/02-xml-script-light.png" width="860" alt="The same script with Show XML turned on. The right side shows the fmxmlsnippet XML of the script steps, indented, with the tags, attribute names and values in different colors.">
</picture>

The XML view is for display only. You cannot change the XML in the app. **Copy Entry** and **Save As…** always use the XML as it was captured.

To save the XML of an entry to a file, select **File** > **Save As…** (Cmd+Shift+S).

### Rename an entry

Without a name, the app makes a title from the XML. For a script, the title is the first comment that has text, and the number of steps.

To give an entry a name, select **File** > **Rename…** (Cmd+R), or double-click the title on the right side. To go back to the automatic title, delete the name. The name does not change the XML.

### Select and delete entries

- Cmd+click to add an entry to the selection. Shift+click to select a range. Cmd+A selects all the entries that the list shows.
- To delete the selected entries, press Delete, or select **File** > **Delete** (Cmd+Delete). For more than one entry, the app asks first.
- To get deleted entries back, select **Edit** > **Undo** (Cmd+Z).

When you select more than one entry, **Move to Folder** and **Delete** act on all of them.

## Settings

To open the Settings window, select **fm-object-clip** > **Settings…** (Cmd+,) or **File** > **Settings…**. Each change applies at once.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/06-settings-dark.png">
  <img src="docs/screenshots/06-settings-light.png" width="450" alt="The Settings window: Appearance set to System, with Light and Dark as other choices; the Uncategorized group name field; the Uncategorized limit field set to 500 entries.">
</picture>

| Setting | Default | What it does |
|---|---|---|
| Appearance | System | System, Light or Dark. System follows the appearance of macOS. |
| Uncategorized group | Uncategorized | The name of the group for the entries in no folder. It changes only the label. A blank name gives "Uncategorized". |
| Uncategorized limit | 500 | The maximum number of entries in the uncategorized group, from 10 to 100000. When there are more, the app deletes the oldest uncategorized entries. |

Entries in folders do not count for the limit, and the app never deletes them. To keep an entry, put it in a folder.

If you set a limit that is lower than the number of uncategorized entries now, the app asks first, for example "Delete the 40 oldest uncategorized entries?". Click **OK** to delete them, or **Cancel** to keep the old limit.

## Back up and restore

A backup is one file with your full history: all the entries, all the folders in their order, and the settings.

**To make a backup:** select **File** > **Back Up History…** and select where to save the file. The default name is `fm-object-clip-backup-YYYY-MM-DD.json`.

**To restore a backup:** select **File** > **Restore from Backup…** and select the backup file. Then select one of these:

- **Merge** (the default): the app adds the entries of the backup that are not in your history, and the folders that are missing. Your current entries and your settings do not change.
- **Replace**: the app replaces your full history and your settings with the backup. Before it does this, it saves your current history to `~/Library/Application Support/fm-object-clip/backups/`. To go back, restore that file with **Replace**.

If the file is not a correct backup, the app shows an error and changes nothing.

## Where the history is

The history is in `~/Library/Application Support/fm-object-clip/history/`. Each entry is a plain XML file, with an `index.json` file for the titles, names and folders. Other programs and scripts can read these files.

Your history can contain the names and the logic of your FileMaker solutions. Do not put it in a public repository.

For the full file format, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#history-files).

## Menus and shortcuts

| Menu | Items |
|---|---|
| fm-object-clip | About fm-object-clip, Settings… (Cmd+,), Quit (Cmd+Q) |
| File | Copy Entry (Cmd+C), Rename… (Cmd+R), Move to Folder, Save As… (Cmd+Shift+S), Delete (Cmd+Delete). New Folder… (Cmd+Shift+N), Rename Folder…, Delete Folder, Move Folder Up, Move Folder Down. Back Up History…, Restore from Backup…, Settings…, Close Window (Cmd+W). |
| Edit | The standard items. When the list has the keyboard focus, **Select All** (Cmd+A) and **Delete** act on the entries. |
| View | All Types (Cmd+1), Scripts (Cmd+2), Tables (Cmd+3), Fields (Cmd+4), Layout (Cmd+5), Show XML (Cmd+Option+X) |
| Window | History Window (Cmd+0) and the standard items |
| Help | fm-object-clip Help: opens this page |

In the list:

- Up Arrow and Down Arrow move the selection, also while you type in the search field. Shift+Up Arrow and Shift+Down Arrow make the selection larger or smaller.
- Left Arrow closes the folder of the selected entry. Right Arrow opens the selected folder.
- Return copies the selected entry. Delete deletes the selected entries.

NOTE: When an entry is selected, Cmd+C copies the entry, also when you select text in the XML view. To copy only the selected text, use **Edit** > **Copy**.

## Command-line tool

`fm-object-clip-cli` reads and changes the same history from a terminal, a script or an AI agent. It is in `build/bin/fm-object-clip-cli` after you build, and also inside the app at `FMObjectClip.app/Contents/MacOS/fm-object-clip-cli`. The app and the tool can change the history at the same time. The app shows each change at once.

The main commands:

| Command | What it does |
|---|---|
| `list [--folder NAME] [--class C] [--search TEXT]` | Shows the entries, newest first, with their IDs |
| `xml ID` | Writes the XML of an entry to stdout |
| `restore ID` | Puts the entry on the clipboard. Then press Cmd+V in FileMaker Pro. |
| `add FILE.xml --class C [--name NAME] [--folder NAME]` | Adds an entry from an XML file |
| `rename ID NAME`, `move ID FOLDER`, `delete ID` | Change or delete entries |
| `folders`, `folder new NAME`, `folder move NAME POSITION` | Show, make and sort folders |
| `settings`, `settings set KEY VALUE` | Show or change the settings |
| `backup FILE`, `import-backup FILE [--replace]` | Make or restore a backup |
| `watch` | Keeps the FileMaker objects that you copy, without the app |

`C` is the FileMaker type: `XMSS` (script steps), `XMTB` (tables), `XMFD` (fields) or `XML2` (layout objects). Add `--json` to any command for JSON output.

```bash
fm-object-clip-cli list --folder "Invoicing"
fm-object-clip-cli restore 20261120-180123-0f558176
```

Run `fm-object-clip-cli --help` for all the commands. The full reference, with the JSON fields and the exit codes, is in [docs/CLI.md](docs/CLI.md).

## Limits

- The app is for macOS only. FileMaker Pro for Windows uses different clipboard formats.
- The app captures only the 4 types above.
- You cannot change the XML in the app.
- For layout objects with a portal, the app checks that each portal child is in the first portal row. If it is not, **Copy Entry** asks before it copies. See [the portal check](docs/CLI.md#portal-check).
- The app does not paste into FileMaker Pro. You press Cmd+V.

## Development

To build and test from the source code:

```bash
swift build
swift test
swift run FMObjectClip
```

The package has 3 targets: `FMClipCore` (the clipboard and history library), `FMObjectClip` (the SwiftUI app) and `fm-object-clip-cli` (the command-line tool). The tests do not change your clipboard or your history.

To run the app with a test history in place of your real history, start it with `-HistoryFolder PATH`:

```bash
open -n build/FMObjectClip.app --args -HistoryFolder ~/Desktop/demo-history
```

For the app bundle, the icon, the history file format and the backup file format, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

fm-object-clip is open source under the [MIT License](LICENSE). Copyright (c) 2026 Solutions Cay LLC.
