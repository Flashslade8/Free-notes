import UIKit
import PencilKit

enum PDFExporter {
    /// Renders every page (paper + ink) into a PDF in the temp directory.
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
                    drawPaper(page.template, in: rect, ctx: ctx.cgContext)
                    if let drawing = try? PKDrawing(data: page.drawingData) {
                        drawing.image(from: rect, scale: 2).draw(in: rect)
                    }
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawPaper(_ template: PageTemplate, in rect: CGRect, ctx: CGContext) {
        guard template != .blank else { return }
        let step: CGFloat = 28

        if template == .dotted {
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.35).cgColor)
            var y = step
            while y < rect.height {
                var x = step
                while x < rect.width {
                    ctx.fillEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
                    x += step
                }
                y += step
            }
            return
        }

        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(0.7)
        var y = step * 2
        while y < rect.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        if template == .grid {
            var x = step
            while x < rect.width {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: rect.height))
                x += step
            }
        }
        ctx.strokePath()
    }
}
