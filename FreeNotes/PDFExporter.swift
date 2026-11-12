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
}
