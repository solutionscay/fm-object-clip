# fm-object-clip-cli reference

This page is the full reference of the command-line tool. For a short introduction, see [the README](../README.md#command-line-tool).

`fm-object-clip-cli` reads and manages the history from a terminal, a script or an agent. Use `build/bin/fm-object-clip-cli`, or `build/FMObjectClip.app/Contents/MacOS/fm-object-clip-cli` inside the app bundle.

## Safe while the app runs

The app and the tool can change the history at the same time. Each change locks the history (the file `.lock` in the history folder), reads the latest `index.json` and `folders.json`, and writes the files atomically. The app sees each change on disk and shows it at once.

## Commands

Each command takes `--history DIR` (the default is the history of the app) and `--json`. The IDs come from `list`.

| Command | What it does |
|---|---|
| `list [--folder NAME \| --no-folder] [--class C] [--search TEXT] [--limit N]` | The entries, newest first. The search looks in the name, the automatic title and the XML. |
| `show ID` | The data of one entry. |
| `xml ID` | The stored XML bytes, to stdout. |
| `folders` | The folders, in the order of the list, and the number of entries in each. |
| `info` | The FileMaker objects on the clipboard now, with the name and the folder from `FOPN` and `FOPF` if the clipboard has them. |
| `add FILE.xml --class C [--name NAME] [--folder NAME] [--force]` | Adds an entry from a file, with the rules of a capture. If the class and the XML are the same as an entry, it updates the name and the folder of that entry. For `XML2`, the tool does the [portal check](#portal-check) first. |
| `restore ID [--force]` | Puts the entry on the clipboard with its class. The entry keeps its time and its place. For `XML2`, the tool does the [portal check](#portal-check) first. |
| `rename ID NAME` | Gives the entry a name. `""` gives the automatic title again. |
| `move ID FOLDER` | Moves the entry to the folder. The tool makes the folder if necessary. |
| `move ID --no-folder` | Takes the entry out of its folder. It goes to the uncategorized group. |
| `delete ID [ID ...]` | Deletes the entries. If an ID does not exist, the tool deletes nothing. |
| `folder new NAME` | Makes a folder. |
| `folder rename OLD NEW` | Renames a folder. Its entries go with it. |
| `folder delete NAME` | Deletes a folder. Its entries go to the uncategorized group. |
| `folder move NAME POSITION` | Moves a folder to a position in the list. Position 1 is the first. A position after the end puts the folder last. Its entries stay in it. It shows the folders in the new order. |
| `settings` | Shows the settings. |
| `settings set KEY VALUE` | Sets one setting. `KEY` is `appearance` (`system`, `light` or `dark`), `uncategorized-name` (text), or `uncategorized-limit` (10 to 100000). A lower limit deletes the oldest uncategorized entries at once, with no question. The tool shows how many entries it deleted. A bad key or value gives exit code 2. |
| `backup FILE [--force]` | Writes the full history to one backup file (see [Backup](DEVELOPMENT.md#backup-file-format)). The tool does not overwrite a file that exists, except with `--force`. |
| `import-backup FILE` | Merge: adds the entries of the backup that are not in the history, and the missing folders. The settings do not change. |
| `import-backup FILE --replace` | Replace: replaces the full history and the settings with the backup. First, the tool saves the current history to the `backups` folder next to the history folder. |
| `watch` | Adds each FileMaker object on the clipboard to the history, without the app. If a layout object fails the [portal check](#portal-check), the tool keeps it and writes a warning to stderr. |
| `help`, `--help` | Shows the help. |

`C` is `XMSS`, `XMTB`, `XMFD` or `XML2`.

## Portal check

FileMaker Pro pastes a portal child outside the first portal row as an object that you cannot select in Layout mode. So for layout objects (`XML2`), the tool and the app check each portal child before they use the XML:

- In the XML, the bounds of a portal child start at the top left of the portal, not of the layout. The bounds of an object in a group start at the top left of the group.
- The child must be in the portal and in the first row. The row height is the portal height divided by `numOfRows`.
- FileMaker Pro writes -1 for a child on the portal border, so the check allows 1 point outside.

What happens when the check fails:

| Where | Result |
|---|---|
| A copy in FileMaker Pro (the app, `watch`) | The entry is kept as FileMaker Pro wrote it. The app shows a warning. `watch` writes a warning to stderr. |
| `add` | Stops with exit code 1, and adds nothing. `--force` adds the entry anyway. |
| `restore` | Stops with exit code 1, and the clipboard does not change. `--force` puts the entry on the clipboard anyway. |
| **Copy Entry** in the app | The app asks first. **Cancel** leaves the clipboard as it was. **Copy Anyway** copies the entry. |

## JSON

With `--json`, the read commands give an entry or a list of entries. The write commands give the changed entry or folder. `delete` gives the deleted entries. The field names are stable:

| Field | Value |
|---|---|
| `id` | The id of the entry |
| `class` | `XMSS`, `XMTB`, `XMFD` or `XML2` |
| `type` | `Scripts`, `Tables`, `Fields` or `Layout` |
| `title` | The title that the app shows: the name, else the automatic title |
| `autoTitle` | The title from the XML |
| `name` | The name, or `null` |
| `folder` | The folder, or `null` |
| `time` | The time of the last capture, ISO 8601 |
| `sha256` | The hash of the XML |
| `source` | `clipboard`, or `cli` for `add` |
| `bytes` | The size of the XML file |
| `file` | The path of the XML file |
| `canonical` | The SHA-256 of the canonical XML. Two entries with the same class and the same value are the same object. |

A folder is `{"name", "count"}`. `folder rename` also gives `oldName`. `folder delete` gives `{"name", "movedEntries"}`. `settings` gives `{"appearance", "uncategorizedName", "uncategorizedLimit"}`. `settings set` also gives `deletedEntries`. `folder move` gives the list of folders in the new order. `info` gives `{"class", "bytes", "name", "folder"}` for each object. `name` and `folder` are `null` when the clipboard has no `FOPN` or `FOPF` (see [Name and folder from the clipboard](DEVELOPMENT.md#name-and-folder-from-the-clipboard)). `backup` gives `{"file", "entries", "folders", "settings"}`. `import-backup` gives `{"mode": "merge", "added", "skippedDuplicates", "foldersAdded"}`, or `{"mode": "replace", "entries", "folders", "safetyBackup"}`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | Error, for example a folder name that exists, or a file that is not a correct backup |
| 2 | Bad usage, for example an unknown command or class |
| 3 | Not found: an entry, a folder or a file |

The tool writes errors to stderr.

## Examples

```bash
CLI=build/bin/fm-object-clip-cli
$CLI list --folder "Project A" --json
$CLI xml 20261120-180123-0f558176 > fields.xml
$CLI restore 20261120-180123-0f558176
$CLI move 20261120-180123-0f558176 "Project A"
$CLI folder new "Project B"
$CLI add contacts-fields.xml --class XMFD --name "Contact fields" --folder "Project A"
$CLI settings set uncategorized-limit 1000
$CLI backup ~/Desktop/fm-object-clip-backup.json
$CLI import-backup ~/Desktop/fm-object-clip-backup.json --json
```
