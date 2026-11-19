import SwiftUI
import PDFKit

/// A template you made yourself: a page with its paper, text boxes, pictures and writing.
struct CustomTemplate: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var page: NotePage
    var pdfData: Data? = nil        // a one-page PDF, when the template sits on a PDF

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? { "That file couldn't be turned into a template." }
    }

    /// Saves a page of a note as a template.
    static func make(name: String, from page: NotePage, in note: Note) -> CustomTemplate {
        var snapshot = page
        snapshot.id = UUID()
        snapshot.objects = page.objects?.map { object in
            var o = object
            o.id = UUID()
            return o
        }
        var pdf: Data? = nil
        if let pdfPage = note.pdfPage(for: page) { pdf = singlePagePDF(pdfPage) }
        snapshot.pdfID = nil
        snapshot.pdfPageIndex = pdf == nil ? nil : 0
        return CustomTemplate(name: name, page: snapshot, pdfData: pdf)
    }

    /// Makes a template from the first page of a PDF.
    static func fromPDF(_ url: URL) throws -> CustomTemplate {
        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(data: data), !document.isLocked,
              let first = document.page(at: 0),
              let single = singlePagePDF(first) else { throw Failure.unreadable }
        var page = NotePage(template: .blank)
        page.pdfPageIndex = 0
        return CustomTemplate(name: url.deletingPathExtension().lastPathComponent,
                              page: page, pdfData: single)
    }

    /// Makes a template with a photo filling the page.
    static func fromPhoto(_ data: Data) throws -> CustomTemplate {
        guard let prepared = ObjectImages.prepare(data) else { throw Failure.unreadable }
        let aspect = max(prepared.aspect, 0.01)
        var width = PageMetrics.size.width
        var height = width / aspect
        if height > PageMetrics.size.height {
            height = PageMetrics.size.height
            width = height * aspect
        }
        let picture = PageObject(kind: .image,
                                 x: (PageMetrics.size.width - width) / 2,
                                 y: (PageMetrics.size.height - height) / 2,
                                 width: width, height: height, imageData: prepared.data)
        var page = NotePage(template: .blank)
        page.objects = [picture]
        return CustomTemplate(name: "Photo template", page: page)
    }

    private static func singlePagePDF(_ page: PDFPage) -> Data? {
        let document = PDFDocument()
        guard let copy = page.copy() as? PDFPage else { return nil }
        document.insert(copy, at: 0)
        return document.dataRepresentation()
    }

    /// A fresh page (and the PDF behind it, if any) ready to go into a note.
    func instantiate() -> (page: NotePage, attachment: PDFAttachment?) {
        var fresh = page
        fresh.id = UUID()
        fresh.objects = page.objects?.map { object in
            var o = object
            o.id = UUID()
            return o
        }
        var attachment: PDFAttachment? = nil
        if let pdfData {
            let a = PDFAttachment(id: UUID(), data: pdfData)
            attachment = a
            fresh.pdfID = a.id
            fresh.pdfPageIndex = 0
        } else {
            fresh.pdfID = nil
            fresh.pdfPageIndex = nil
        }
        return (fresh, attachment)
    }

    /// A small picture of the template. The ids are fixed so pictures can be remembered.
    func preview(width: CGFloat = 220) -> UIImage {
        var shown = page
        shown.id = id
        var note = Note()
        if let pdfData {
            note.pdfs = [PDFAttachment(id: id, data: pdfData)]
            shown.pdfID = id
            shown.pdfPageIndex = 0
        }
        return PageRenderer.thumbnail(note: note, page: shown, width: width)
    }
}

/// Your templates, kept on this device.
@MainActor
final class CustomTemplateStore: ObservableObject {
    static let shared = CustomTemplateStore()

    @Published private(set) var templates: [CustomTemplate] = []

    private let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("custom-templates.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([CustomTemplate].self, from: data) {
            templates = saved
        }
    }

    func add(_ template: CustomTemplate) {
        templates.insert(template, at: 0)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        if let i = templates.firstIndex(where: { $0.id == id }) {
            templates[i].name = name
            save()
        }
    }

    func delete(_ id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(templates) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension NoteStore {
    /// A new note that starts from one of your templates.
    @discardableResult
    func addNote(in folder: UUID?, custom template: CustomTemplate) -> Note {
        var note = Note()
        note.folderID = folder
        note.title = template.name
        let made = template.instantiate()
        note.pages = [made.page]
        if let attachment = made.attachment { note.pdfs = [attachment] }
        notes.insert(note, at: 0)
        return note
    }

    /// Adds a page made from one of your templates to the end of a note.
    func addPage(from template: CustomTemplate, to noteID: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let made = template.instantiate()
        var note = notes[i]
        if let attachment = made.attachment { note.pdfs.append(attachment) }
        note.pages.append(made.page)
        notes[i] = note
    }
}
