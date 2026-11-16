import SwiftUI
import PencilKit
import PDFKit

// MARK: - Page thumbnails

enum PageRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    /// A small picture of a whole page: paper or PDF, text boxes, pictures and ink.
    static func thumbnail(note: Note, page: NotePage, width: CGFloat = 112) -> UIImage {
        let key = "\(page.id)-\(page.drawingData.count)-\(page.objects?.count ?? 0)-\(page.template.rawValue)-\(page.pdfID?.uuidString ?? "-")-\(page.pdfPageIndex ?? -1)-\(Int(width))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let scale = width / PageMetrics.size.width
        let size = CGSize(width: width, height: PageMetrics.size.height * scale)
        let image = UIGraphicsImageRenderer(size: size).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            let ctx = renderer.cgContext

            if let pdf = note.pdfPage(for: page) {
                PDFBackground.draw(pdf, into: ctx, size: size)
            } else {
                TemplateRenderer.draw(page.template, in: ctx, size: size)
            }
            if let objects = page.objects {
                ctx.saveGState()
                ctx.scaleBy(x: scale, y: scale)
                PDFExporter.drawObjects(objects)
                ctx.restoreGState()
            }
            if let drawing = try? PKDrawing(data: page.drawingData), !drawing.strokes.isEmpty {
                lightImage(of: drawing, in: CGRect(origin: .zero, size: PageMetrics.size), scale: max(scale * 2, 0.25))
                    .draw(in: CGRect(origin: .zero, size: size))
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Page operations

extension NoteStore {
    func movePages(_ noteID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var pages = notes[i].pages
        pages.move(fromOffsets: source, toOffset: destination)
        notes[i].pages = pages
    }

    func duplicatePage(_ noteID: UUID, pageID: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }),
              let p = notes[i].pages.firstIndex(where: { $0.id == pageID }) else { return }
        var copy = notes[i].pages[p]
        copy.id = UUID()
        copy.objects = copy.objects?.map { object in
            var o = object
            o.id = UUID()
            return o
        }
        notes[i].pages.insert(copy, at: p + 1)
    }

    func insertBlankPage(_ noteID: UUID, after pageID: UUID?) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let template = notes[i].pages.last(where: { $0.pdfID == nil })?.template ?? .lined
        let page = NotePage(template: template)
        if let pageID, let p = notes[i].pages.firstIndex(where: { $0.id == pageID }) {
            notes[i].pages.insert(page, at: p + 1)
        } else {
            notes[i].pages.append(page)
        }
    }

    func deletePage(_ noteID: UUID, pageID: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }), notes[i].pages.count > 1 else { return }
        notes[i].pages.removeAll { $0.id == pageID }
        pruneAttachments(noteID)
    }
}

/// Every page as a thumbnail. Drag to reorder, tap to jump, touch the ••• for more.
struct PagesSheet: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID
    let onSelect: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let note = store.note(noteID) {
                    ForEach(Array(note.pages.enumerated()), id: \.element.id) { index, page in
                        row(note: note, page: page, number: index + 1)
                    }
                    .onMove { store.movePages(noteID, from: $0, to: $1) }
                }
            }
            .environment(\.editMode, .constant(.active))      // shows the drag handles
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.insertBlankPage(noteID, after: nil)
                        Haptics.success()
                    } label: { Label("Add Page", systemImage: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(note: Note, page: NotePage, number: Int) -> some View {
        HStack(spacing: 14) {
            Image(uiImage: PageRenderer.thumbnail(note: note, page: page))
                .resizable()
                .scaledToFit()
                .frame(width: 58)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                .softShadow(radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Page \(number)").font(.body.weight(.semibold))
                Text(subtitle(page)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Button {
                    store.duplicatePage(noteID, pageID: page.id)
                    Haptics.success()
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button {
                    store.insertBlankPage(noteID, after: page.id)
                    Haptics.success()
                } label: { Label("Insert Blank Page After", systemImage: "doc.badge.plus") }
                Divider()
                Button(role: .destructive) {
                    store.deletePage(noteID, pageID: page.id)
                    Haptics.warning()
                } label: { Label("Delete Page", systemImage: "trash") }
                .disabled(note.pages.count <= 1)
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(page.id)
            dismiss()
        }
    }

    private func subtitle(_ page: NotePage) -> String {
        if let index = page.pdfPageIndex { return "PDF page \(index + 1)" }
        return page.template.rawValue
    }
}

// MARK: - Find in a note

struct FindMatch: Identifiable {
    enum Source { case pdf, textBox }
    let id = UUID()
    let pageID: UUID
    let source: Source
    let rects: [CGRect]          // where it is on a PDF page, in PDF coordinates
}

enum FindEngine {
    /// Finds the words in a note's PDF pages and text boxes, in page order.
    static func matches(for query: String, in note: Note, limit: Int = 500) -> [FindMatch] {
        var result: [FindMatch] = []
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        for page in note.pages {
            if let pdfPage = note.pdfPage(for: page), let text = pdfPage.string {
                let ns = text as NSString
                var range = NSRange(location: 0, length: ns.length)
                while range.length > 0, result.count < limit {
                    let found = ns.range(of: query, options: options, range: range)
                    if found.location == NSNotFound { break }
                    if let selection = pdfPage.selection(for: found) {
                        let lines = selection.selectionsByLine().map { $0.bounds(for: pdfPage) }
                        result.append(FindMatch(pageID: page.id, source: .pdf,
                                                rects: lines.isEmpty ? [selection.bounds(for: pdfPage)] : lines))
                    }
                    let next = found.location + max(found.length, 1)
                    range = NSRange(location: next, length: ns.length - next)
                }
            }

            for object in page.objects ?? [] where object.kind == .text {
                let ns = object.text as NSString
                var range = NSRange(location: 0, length: ns.length)
                while range.length > 0, result.count < limit {
                    let found = ns.range(of: query, options: options, range: range)
                    if found.location == NSNotFound { break }
                    result.append(FindMatch(pageID: page.id, source: .textBox, rects: []))
                    let next = found.location + max(found.length, 1)
                    range = NSRange(location: next, length: ns.length - next)
                }
            }
        }
        return result
    }
}

/// The floating search bar with previous and next buttons.
struct FindBar: View {
    @Binding var query: String
    let count: Int
    let index: Int
    let onStep: (Int) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in note", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { onStep(1) }
                .frame(width: 190)

            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 62, alignment: .trailing)

            Button { onStep(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(count == 0)
                .accessibilityLabel("Previous match")
            Button { onStep(1) } label: { Image(systemName: "chevron.down") }
                .disabled(count == 0)
                .accessibilityLabel("Next match")
            Button(action: onClose) { Image(systemName: "xmark") }
                .accessibilityLabel("Close find")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .floatingCapsule()
        .onAppear { focused = true }
    }

    private var label: String {
        if query.trimmingCharacters(in: .whitespaces).count < 2 { return "" }
        return count == 0 ? "No matches" : "\(index + 1) of \(count)"
    }
}

// MARK: - Searching every note

/// Remembers the words inside each note (text boxes, PDF text, transcripts)
/// so searching the library stays quick.
enum NoteIndex {
    private static var noteCache: [String: String] = [:]
    private static let pdfCache = NSCache<NSString, NSString>()

    static func contains(_ note: Note, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return false }
        return text(for: note).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func text(for note: Note) -> String {
        let key = "\(note.id)-\(note.modifiedAt.timeIntervalSince1970)"
        if let hit = noteCache[key] { return hit }

        var parts: [String] = []
        for page in note.pages {
            for object in page.objects ?? [] where object.kind == .text { parts.append(object.text) }
        }
        for recording in note.recordings {
            for segment in recording.transcript ?? [] { parts.append(segment.text) }
        }
        for attachment in note.pdfs { parts.append(pdfText(attachment)) }

        let joined = parts.joined(separator: "\n")
        if noteCache.count > 200 { noteCache.removeAll() }
        noteCache[key] = joined
        return joined
    }

    private static func pdfText(_ attachment: PDFAttachment) -> String {
        let key = attachment.id.uuidString as NSString
        if let hit = pdfCache.object(forKey: key) { return hit as String }
        let text = PDFCache.document(for: attachment)?.string ?? ""
        pdfCache.setObject(text as NSString, forKey: key)
        return text
    }
}
