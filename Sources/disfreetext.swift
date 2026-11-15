import SwiftUI
import AppKit
import UniformTypeIdentifiers

// A chapter is either a whole file (folder mode) or a "# Heading" section of one file (file mode).
struct Chapter: Codable {
    var text: String
    var url: URL? = nil   // only set in folder mode
    var edited = false

    var title: String {
        if let url { return url.deletingPathExtension().lastPathComponent }
        let firstLine = text.prefix { $0 != "\n" }
        return firstLine.hasPrefix("# ") ? String(firstLine.dropFirst(2)) : "Untitled"
    }
}

// Unsaved changes, copied to disk every 30 seconds in case the app crashes.
struct Recovery: Codable {
    var path: String
    var chapters: [Chapter]

    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("disfreetext/recovery.json")
}

@MainActor
final class Book: ObservableObject {
    @Published var chapters: [Chapter] = []
    @Published var current = 0
    @Published var unsaved = false
    private var folderURL: URL?  // folder mode
    private var fileURL: URL?    // file mode

    var isOpen: Bool { folderURL != nil || fileURL != nil }

    init() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.writeRecovery() }
        }
    }

    // MARK: Opening

    func openLast() {
        if let path = UserDefaults.standard.string(forKey: "lastPath") {
            open(URL(fileURLWithPath: path))
        }
    }

    func showOpenPanel() {
        guard askToSave() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return }
        UserDefaults.standard.set(url.path, forKey: "lastPath")
        current = 0
        unsaved = false

        if isFolder.boolValue {
            folderURL = url
            fileURL = nil
            let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            chapters = files
                .filter { ["md", "txt"].contains($0.pathExtension.lowercased()) }
                .map { Chapter(text: (try? String(contentsOf: $0, encoding: .utf8)) ?? "", url: $0) }
                .sorted(by: Book.byFileName)
        } else {
            folderURL = nil
            fileURL = url
            chapters = Book.split((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }
        offerRecovery(for: url)
    }

    // MARK: Editing

    // The text of the chapter being edited. Changes stay in memory until you save.
    var text: String {
        get { chapters.indices.contains(current) ? chapters[current].text : "" }
        set {
            guard chapters.indices.contains(current), chapters[current].text != newValue else { return }
            chapters[current].text = newValue
            chapters[current].edited = true
            unsaved = true
        }
    }

    // In file mode, titles are re-read from the text so a newly typed "# Heading" shows up right away.
    var titles: [String] {
        (fileURL != nil ? Book.split(joined) : chapters).map(\.title)
    }

    var words: Int { Book.countWords(text) }
    var totalWords: Int { chapters.reduce(0) { $0 + Book.countWords($1.text) } }

    // A word is any run of non-space characters containing a letter or digit (so "#" doesn't count).
    static func countWords(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    func select(_ index: Int) {
        if fileURL != nil { chapters = Book.split(joined) }
        current = min(index, chapters.count - 1)
    }

    // MARK: Managing chapters

    func newChapter() {
        if let folderURL {
            let name = String(format: "%02d Untitled.md", chapters.count + 1)
            chapters.append(Chapter(text: "", url: folderURL.appendingPathComponent(name), edited: true))
        } else if fileURL != nil {
            chapters = Book.split(joined) + [Chapter(text: "# New chapter\n", edited: true)]
        } else {
            return
        }
        current = chapters.count - 1
        unsaved = true
    }

    // Folder mode: renames the chapter's file. File mode: changes the chapter's "# " heading.
    func renameChapter() {
        guard chapters.indices.contains(current) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename chapter"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = titles[current]
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != titles[current] else { return }

        if let old = chapters[current].url {
            let safeName = name.replacingOccurrences(of: "/", with: "-")
            let new = old.deletingLastPathComponent().appendingPathComponent(safeName).appendingPathExtension(old.pathExtension)
            do {
                // A new chapter that was never saved isn't on disk yet.
                if FileManager.default.fileExists(atPath: old.path) {
                    try FileManager.default.moveItem(at: old, to: new)
                }
                chapters[current].url = new
                chapters.sort(by: Book.byFileName)  // the new name may change the order
                current = chapters.firstIndex { $0.url == new } ?? 0
            } catch {
                NSAlert(error: error).runModal()
            }
        } else {
            chapters = Book.split(joined)
            var lines = chapters[current].text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines[0].hasPrefix("# ") { lines[0] = "# " + name } else { lines.insert("# " + name, at: 0) }
            chapters[current].text = lines.joined(separator: "\n")
            chapters[current].edited = true
            unsaved = true
        }
    }

    // Folder mode: moves the chapter's file to the Trash. File mode: removes the section (on the next save).
    func deleteChapter() {
        guard chapters.indices.contains(current) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(titles[current])”?"
        alert.informativeText = folderURL != nil
            ? "Its file will be moved to the Trash."
            : "It will be removed from the file the next time you save."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if fileURL != nil {
            chapters = Book.split(joined)
            chapters.remove(at: current)
            if chapters.isEmpty { chapters = [Chapter(text: "")] }
            unsaved = true
        } else {
            if let url = chapters[current].url, FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    NSAlert(error: error).runModal()
                    return
                }
            }
            chapters.remove(at: current)
            unsaved = chapters.contains { $0.edited }
        }
        current = max(0, min(current, chapters.count - 1))
    }

    // Called when chapters are dragged to a new place in the list.
    func moveChapters(from source: IndexSet, to destination: Int) {
        if fileURL != nil { chapters = Book.split(joined) }
        var order = Array(chapters.indices)
        order.move(fromOffsets: source, toOffset: destination)
        current = order.firstIndex(of: current) ?? 0
        chapters = order.map { chapters[$0] }

        if fileURL != nil {
            // Every section after the first needs a heading, or it would merge into the one above.
            for i in chapters.indices.dropFirst() where !chapters[i].text.hasPrefix("# ") {
                chapters[i].text = "# Untitled\n" + chapters[i].text
            }
            unsaved = true
        } else {
            renumberFiles()
        }
    }

    // Renames the files to "01 …", "02 …" in the current order. Files first get temporary
    // names so that two of them can never end up with the same name halfway through.
    private func renumberFiles() {
        let files = FileManager.default
        let digits = max(2, String(chapters.count).count)
        do {
            var temporary: [URL?] = []
            for chapter in chapters {
                if let url = chapter.url, files.fileExists(atPath: url.path) {
                    let temp = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
                    try files.moveItem(at: url, to: temp)
                    temporary.append(temp)
                } else {
                    temporary.append(nil)  // not saved yet, nothing on disk
                }
            }
            for i in chapters.indices {
                let old = chapters[i].url!
                let number = String(format: "%0\(digits)d", i + 1)
                let name = Book.withoutNumber(old.deletingPathExtension().lastPathComponent)
                let new = old.deletingLastPathComponent()
                    .appendingPathComponent(name.isEmpty ? number : "\(number) \(name)")
                    .appendingPathExtension(old.pathExtension)
                if let temp = temporary[i] { try files.moveItem(at: temp, to: new) }
                chapters[i].url = new
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // "03 The Road" -> "The Road"
    static func withoutNumber(_ name: String) -> String {
        name.replacingOccurrences(of: #"^\d+[\s._-]*"#, with: "", options: .regularExpression)
    }

    static func byFileName(_ a: Chapter, _ b: Chapter) -> Bool {
        a.url!.lastPathComponent.localizedStandardCompare(b.url!.lastPathComponent) == .orderedAscending
    }

    // MARK: Saving

    func save() {
        do {
            if let fileURL {
                try joined.write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                for i in chapters.indices where chapters[i].edited {
                    try chapters[i].text.write(to: chapters[i].url!, atomically: true, encoding: .utf8)
                }
            }
            for i in chapters.indices { chapters[i].edited = false }
            unsaved = false
            deleteRecovery()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // Returns false if the user cancelled.
    func askToSave() -> Bool {
        guard unsaved else { return true }
        let alert = NSAlert()
        alert.messageText = "Save your changes?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !unsaved
        case .alertSecondButtonReturn: deleteRecovery(); return true
        default: return false
        }
    }

    // MARK: Crash recovery

    private func writeRecovery() {
        guard unsaved, let path = (folderURL ?? fileURL)?.path,
              let data = try? JSONEncoder().encode(Recovery(path: path, chapters: chapters)) else { return }
        try? FileManager.default.createDirectory(at: Recovery.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Recovery.url, options: .atomic)
    }

    private func deleteRecovery() {
        try? FileManager.default.removeItem(at: Recovery.url)
    }

    // If the app closed without saving this book, offer to bring back the lost changes.
    private func offerRecovery(for url: URL) {
        guard let data = try? Data(contentsOf: Recovery.url),
              let recovery = try? JSONDecoder().decode(Recovery.self, from: data),
              recovery.path == url.path else { return }
        let alert = NSAlert()
        alert.messageText = "Restore unsaved changes?"
        alert.informativeText = "disfreetext closed before your last changes to “\(url.lastPathComponent)” were saved."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Discard")
        if alert.runModal() == .alertFirstButtonReturn {
            chapters = recovery.chapters
            unsaved = true
        } else {
            deleteRecovery()
        }
    }

    // MARK: Export

    // The whole book as one Markdown text, with a "# Title" heading for every chapter.
    var manuscript: String {
        if fileURL != nil { return joined }
        return chapters
            .map { $0.text.hasPrefix("# ") ? $0.text : "# \(Book.withoutNumber($0.title))\n\n\($0.text)" }
            .joined(separator: "\n\n")
    }

    func export(asPDF: Bool) {
        guard let book = folderURL ?? fileURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [asPDF ? .pdf : UTType(filenameExtension: "md")!]
        panel.nameFieldStringValue = book.deletingPathExtension().lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if asPDF {
            Book.writePDF(manuscript, to: url)
        } else {
            do { try manuscript.write(to: url, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
        }
    }

    // Lays the text out on A4/Letter pages (whatever the Mac's default paper is) and saves it as a PDF.
    static func writePDF(_ text: String, to url: URL) {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.isVerticallyCentered = false

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 4
        bodyStyle.paragraphSpacing = 8
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacingBefore = 24
        headingStyle.paragraphSpacing = 12
        let body: [NSAttributedString.Key: Any] = [.font: serif(12), .paragraphStyle: bodyStyle, .foregroundColor: NSColor.black]
        let heading: [NSAttributedString.Key: Any] = [.font: serif(20, bold: true), .paragraphStyle: headingStyle, .foregroundColor: NSColor.black]

        let styled = NSMutableAttributedString()
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                styled.append(NSAttributedString(string: line.dropFirst(2) + "\n", attributes: heading))
            } else {
                styled.append(NSAttributedString(string: line + "\n", attributes: body))
            }
        }

        let width = printInfo.paperSize.width - 144
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.appearance = NSAppearance(named: .aqua)  // white page, even in dark mode
        view.drawsBackground = false
        view.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.textStorage?.setAttributedString(styled)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    // MARK: Sections inside one file

    private var joined: String { chapters.map(\.text).joined(separator: "\n") }

    // Splits text into sections, starting a new one at every line beginning with "# ".
    static func split(_ text: String) -> [Chapter] {
        var sections: [[Substring]] = [[]]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# "), !sections[sections.count - 1].isEmpty { sections.append([]) }
            sections[sections.count - 1].append(line)
        }
        return sections.map { Chapter(text: $0.joined(separator: "\n")) }
    }
}

func serif(_ size: CGFloat, bold: Bool = false) -> NSFont {
    let system = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    return NSFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: size)!
}

// A plain NSTextView. In typewriter mode the line with the cursor always stays in the middle of the screen.
struct Editor: NSViewRepresentable {
    @Binding var text: String
    var ink: NSColor
    var fontSize: CGFloat
    var typewriter: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func attributes(_ fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize / 3
        return [.font: serif(fontSize), .paragraphStyle: style]
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true

        // Re-layout when the window is resized.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.layout),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scrollView.documentView as! NSTextView
        let newText = textView.string != text  // a different chapter was selected
        let newSize = (textView.typingAttributes[.font] as? NSFont)?.pointSize != fontSize
        if newText {
            textView.string = text
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.undoManager?.removeAllActions()
        }
        if newText || newSize {
            textView.typingAttributes = Editor.attributes(fontSize)
            textView.textStorage?.setAttributes(textView.typingAttributes,
                                                range: NSRange(location: 0, length: textView.textStorage!.length))
        }
        textView.textColor = ink
        textView.insertionPointColor = ink
        context.coordinator.layout()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Editor
        weak var textView: NSTextView?

        init(_ parent: Editor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            parent.text = textView?.string ?? ""
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Wait until NSTextView has finished its own scrolling.
            DispatchQueue.main.async { self.centerCursor() }
        }

        // A centered column of text (wider for bigger text), with half a screen of space above and
        // below in typewriter mode so even the first and last lines can sit in the middle.
        @objc func layout() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let size = scrollView.contentSize
            let column = 680 * parent.fontSize / 18
            let inset = NSSize(width: max(40, (size.width - column) / 2),
                               height: parent.typewriter ? size.height / 2 : 60)
            if textView.textContainerInset != inset { textView.textContainerInset = inset }
            centerCursor()
        }

        func centerCursor() {
            guard parent.typewriter, let textView, let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)

            let length = (textView.string as NSString).length
            let location = textView.selectedRange().location
            let line: NSRect
            if location >= length, !layoutManager.extraLineFragmentRect.isEmpty {
                line = layoutManager.extraLineFragmentRect  // empty last line
            } else if length > 0 {
                let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
                line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                return
            }

            let y = line.midY + textView.textContainerOrigin.y - scrollView.contentSize.height / 2
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

struct ContentView: View {
    @ObservedObject var book: Book
    @AppStorage("dark") var dark = true
    @AppStorage("showChapters") var showChapters = true
    @AppStorage("typewriter") var typewriter = true
    @AppStorage("fontSize") var fontSize = 18.0
    @State private var typing = false  // hides the chapters and word count until the mouse moves

    var ink: Color { dark ? .white : .black }

    var wordCount: String {
        var parts = ["\(book.words.formatted()) words"]
        if book.chapters.count > 1 { parts.append("\(book.totalWords.formatted()) total") }
        if book.unsaved { parts.insert("Edited", at: 0) }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(spacing: 0) {
            if showChapters && book.isOpen {
                List {
                    ForEach(Array(book.titles.enumerated()), id: \.offset) { index, title in
                        Text(title)
                            .foregroundColor(ink.opacity(index == book.current ? 0.9 : 0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { book.select(index) }
                            .listRowBackground(Color.clear)
                    }
                    .onMove { book.moveChapters(from: $0, to: $1) }  // drag to reorder
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(.vertical, 40)
                .padding(.leading, 12)
                .frame(width: 220)
                .opacity(typing ? 0 : 1)
            }

            if book.chapters.isEmpty {
                Text(book.isOpen ? "⌘N  new chapter" : "⌘O  open a file or a folder")
                    .foregroundColor(ink.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Editor(text: Binding(get: { book.text },
                                     set: { book.text = $0; typing = true; NSCursor.setHiddenUntilMouseMoves(true) }),
                       ink: NSColor(ink.opacity(0.85)),
                       fontSize: fontSize,
                       typewriter: typewriter)
                    .overlay(alignment: .bottomTrailing) {
                        Text(wordCount)
                            .font(.system(size: 11))
                            .foregroundColor(ink.opacity(0.3))
                            .padding(16)
                            .opacity(typing ? 0 : 1)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: typing)
        .onContinuousHover { _ in if typing { typing = false } }
        .background(dark ? Color.black : Color.white)
        .preferredColorScheme(dark ? .dark : .light)
        .ignoresSafeArea()
    }
}

// Opens the last book on launch and asks to save unsaved changes before quitting.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let book = Book()

    func applicationDidFinishLaunching(_ notification: Notification) {
        book.openLast()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        book.askToSave() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DisfreetextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("dark") var dark = true
    @AppStorage("showChapters") var showChapters = true
    @AppStorage("typewriter") var typewriter = true
    @AppStorage("fontSize") var fontSize = 18.0

    var body: some Scene {
        WindowGroup {
            ContentView(book: delegate.book)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { delegate.book.showOpenPanel() }.keyboardShortcut("o")
                Divider()
                Button("New Chapter") { delegate.book.newChapter() }.keyboardShortcut("n")
                Button("Rename Chapter…") { delegate.book.renameChapter() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Delete Chapter…") { delegate.book.deleteChapter() }.keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { delegate.book.save() }.keyboardShortcut("s")
            }
            CommandGroup(replacing: .importExport) {
                Button("Export as Markdown…") { delegate.book.export(asPDF: false) }
                Button("Export as PDF…") { delegate.book.export(asPDF: true) }
            }
            CommandGroup(after: .sidebar) {
                Button("Show / Hide Chapters") { showChapters.toggle() }.keyboardShortcut("1")
                Button("Black / White") { dark.toggle() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Typewriter Mode On / Off") { typewriter.toggle() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Bigger Text") { fontSize = min(fontSize + 2, 40) }.keyboardShortcut("+")
                Button("Smaller Text") { fontSize = max(fontSize - 2, 12) }.keyboardShortcut("-")
                Button("Actual Size") { fontSize = 18 }.keyboardShortcut("0")
            }
        }
    }
}
