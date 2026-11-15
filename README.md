# disfreetext

A distraction-free text editor for the Mac. You get a plain black or white screen, your words, and an optional list of chapters on the left.

## Install

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). The full Xcode app isn't needed.

```sh
./build.sh
mv disfreetext.app /Applications/
```

If you're replacing an older copy, quit disfreetext and delete `/Applications/disfreetext.app` first.

## Writing a book

Open a folder or a single file with **⌘O**. The chapter list on the left works differently for each.

**A folder**
- Every `.md` or `.txt` file in the folder is a chapter.
- Chapters are listed in filename order, so name them `01 Opening.md`, `02 The Road.md` and so on.
- To rename a chapter, press **⇧⌘R**. This renames its file on disk.
- To reorder chapters, drag them in the list. The files are renumbered on disk straight away (`01 …`, `02 …`).
- To delete a chapter, press **⇧⌘⌫**. Its file goes to the Trash, so you can get it back from there.

**A single file**
- Every line that starts with `# ` begins a new chapter:

  ```
  # Chapter One
  It was a dark and stormy night...

  # Chapter Two
  The next morning...
  ```

- If you type a new `# Heading`, it appears in the chapter list straight away.
- To rename a chapter, press **⇧⌘R**. This changes its `# ` heading.
- To reorder chapters, drag them in the list. To delete one, press **⇧⌘⌫**.
- Renaming, reordering and deleting are only written to the file the next time you press ⌘S.

disfreetext reopens whatever you had open last.

## Saving

Nothing is saved until you press **⌘S**. While you have unsaved changes, "Edited" shows next to the word count. If you quit or open something else before saving, disfreetext asks whether to save.

As a safety net, disfreetext keeps a copy of your unsaved changes every 30 seconds. It never touches your own files when doing this. If the app crashes or the Mac shuts down before you save, it offers to restore those changes the next time you open the book.

## Exporting

**File → Export as Markdown…** joins the whole book into one `.md` file, with a `# ` heading for every chapter.

**File → Export as PDF…** makes a PDF of the whole book, ready to print or share.

Both include any changes you haven't saved yet.

## Word count

The bottom-right corner shows how many words are in the current chapter. When the book has more than one chapter, it also shows the total for the whole book.

## While you type

The chapter list, the word count and the mouse pointer fade away as soon as you start typing. Move the mouse to bring them back.

## Typewriter mode

Typewriter mode is on by default: the line you're typing stays in the middle of the screen. Press **⇧⌘T** to turn it off.

## Shortcuts

| Keys | Action                    |
|------|---------------------------|
| ⌘O   | Open a file or folder     |
| ⌘N   | New chapter               |
| ⇧⌘R  | Rename chapter            |
| ⇧⌘⌫  | Delete chapter            |
| ⌘S   | Save                      |
| ⌘1   | Show / hide chapters      |
| ⇧⌘D  | Switch black / white      |
| ⇧⌘T  | Typewriter mode on / off  |
| ⌘+   | Bigger text               |
| ⌘−   | Smaller text              |
| ⌘0   | Normal text size          |
| ⌃⌘F  | Full screen               |

## Code

- `Sources/disfreetext.swift`: the whole app.
- `icon/make_icon.swift`: draws the app icon. Delete `Resources/AppIcon.icns` and run `./build.sh` to redraw it.
- `build.sh`: builds `disfreetext.app`.
