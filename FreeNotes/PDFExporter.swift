import UIKit
import PencilKit
import PDFKit

enum PDFExporter {
    /// Renders every page (PDF or paper template, plus ink) into a PDF in the temp directory.
    static func export(_ note: Note) -> URL? {
        let rect = CGRect(origin: .zero, size: PageMetrics.size)
        let name = note.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: rect)

        do {
            try renderer.writePDF(to: url) { ctx in
                for page in note.pages {
                    ctx.beginPage()
                    UIColor.white.setFill()
                    ctx.fill(rect)
                    if let pdfPage = note.pdfPage(for: page) {
                        PDFBackground.draw(pdfPage, into: ctx.cgContext, size: rect.size)
                    } else {
                        TemplateRenderer.draw(page.template, in: ctx.cgContext, size: rect.size)
                    }
                    if let objects = page.objects { drawObjects(objects) }
                    if let drawing = try? PKDrawing(data: page.drawingData), !drawing.strokes.isEmpty {
                        lightImage(of: drawing, in: rect, scale: 2).draw(in: rect)
                    }
                }
            }
            return url
        } catch {
            return nil
        }
    }

    /// Text boxes and pictures sit under the ink, like on screen.
    private static func drawObjects(_ objects: [PageObject]) {
        for object in objects {
            let rect = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            switch object.kind {
            case .image:
                if let image = ObjectImages.image(for: object) {
                    image.draw(in: rect)
                }
            case .text:
                let base = UIFont.systemFont(ofSize: object.fontSize)
                let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: object.fontSize) } ?? base
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: object.uiColor]
                (object.text as NSString).draw(in: rect.insetBy(dx: 5, dy: 8), withAttributes: attributes)
            }
        }
    }
}
