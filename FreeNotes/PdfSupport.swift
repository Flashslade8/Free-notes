import SwiftUI
import PDFKit
import PencilKit

/// A PDF stored inside a note. Pages of the note point at it by id.
struct PDFAttachment: Identifiable, Codable {
    var id: UUID
    var data: Data
}

/// Opening a PDF is slow, so each one is opened once and remembered.
enum PDFCache {
    private static let cache = NSCache<NSString, PDFDocument>()

    static func document(for attachment: PDFAttachment) -> PDFDocument? {
        let key = attachment.id.uuidString as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let document = PDFDocument(data: attachment.data) else { return nil }
        cache.setObject(document, forKey: key)
        return document
    }
}

extension Note {
    /// The PDF page behind a note page, if it has one.
    func pdfPage(for page: NotePage) -> PDFPage? {
        guard let pdfID = page.pdfID,
              let index = page.pdfPageIndex,
              let attachment = pdfs.first(where: { $0.id == pdfID }),
              let document = PDFCache.document(for: attachment),
              index >= 0, index < document.pageCount else { return nil }
        return document.page(at: index)
    }
}

enum PDFBackground {
    /// Draws a PDF page, scaled to fit and centred, into a context whose origin is top-left
    /// (the normal UIKit kind). It stays sharp at any size because the PDF is drawn as vectors.
    static func draw(_ page: PDFPage, into ctx: CGContext, size: CGSize) {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return }
        let scale = min(size.width / box.width, size.height / box.height)
        let width = box.width * scale
        let height = box.height * scale

        ctx.saveGState()
        ctx.translateBy(x: (size.width - width) / 2, y: (size.height - height) / 2 + height)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
    }
}

/// Renders ink as it looks on white paper, even when the device is in dark mode.
func lightImage(of drawing: PKDrawing, in rect: CGRect, scale: CGFloat) -> UIImage {
    var image = UIImage()
    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
        image = drawing.image(from: rect, scale: scale)
    }
    return image
}

final class PDFBackgroundView: UIView {
    var page: PDFPage? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        contentMode = .redraw       // redraw sharply whenever the zoom changes
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        UIColor.white.setFill()
        ctx.fill(bounds)
        if let page { PDFBackground.draw(page, into: ctx, size: bounds.size) }
    }
}

struct PDFPageBackground: UIViewRepresentable {
    let page: PDFPage?

    func makeUIView(context: Context) -> PDFBackgroundView {
        let view = PDFBackgroundView()
        view.page = page
        return view
    }

    func updateUIView(_ view: PDFBackgroundView, context: Context) {
        view.page = page
    }
}

enum PDFImport {
    struct Imported {
        var title: String
        var attachment: PDFAttachment
        var pages: [NotePage]
    }

    enum Failure: LocalizedError {
        case unreadable, locked, empty, tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file couldn't be opened as a PDF."
            case .locked: return "Password-protected PDFs can't be imported."
            case .empty: return "That PDF has no pages."
            case .tooLarge: return "That PDF is over 40 MB, which is too big to store and sync."
            }
        }
    }

    static func read(_ url: URL) throws -> Imported {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard data.count <= 40_000_000 else { throw Failure.tooLarge }
        guard let document = PDFDocument(data: data) else { throw Failure.unreadable }
        guard !document.isLocked else { throw Failure.locked }
        guard document.pageCount > 0 else { throw Failure.empty }

        let attachment = PDFAttachment(id: UUID(), data: data)
        let pages = (0..<document.pageCount).map {
            NotePage(template: .blank, pdfID: attachment.id, pdfPageIndex: $0)
        }
        return Imported(title: url.deletingPathExtension().lastPathComponent,
                        attachment: attachment, pages: pages)
    }
}
