import SwiftUI
import PencilKit

/// PKCanvasView that re-applies its zoom whenever it is laid out.
final class ZoomableCanvas: PKCanvasView {
    var targetZoom: CGFloat = 1

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(zoomScale - targetZoom) > 0.001 {
            zoomScale = targetZoom
        }
    }
}

/// A single handwriting page backed by PencilKit.
/// The canvas is zoomed natively, so ink stays sharp at any zoom level.
struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    let picker: PKToolPicker
    let pencilOnly: Bool
    let becomeActive: Bool
    let zoom: CGFloat

    func makeUIView(context: Context) -> ZoomableCanvas {
        let canvas = ZoomableCanvas()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear      // paper is drawn behind by SwiftUI
        canvas.isOpaque = false
        canvas.isScrollEnabled = false       // the outer ScrollView handles scrolling
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        // Logical (unzoomed) size of the page; zoom is applied on top of this.
        canvas.contentSize = PageMetrics.size
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 4
        canvas.targetZoom = zoom

        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        if becomeActive {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: ZoomableCanvas, context: Context) {
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.targetZoom = zoom
        canvas.setNeedsLayout()
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawingData = canvasView.drawing.dataRepresentation()
        }

        // Move the tool picker to whichever page the user starts writing on.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if !canvasView.isFirstResponder { canvasView.becomeFirstResponder() }
        }
    }
}

/// Paper background (blank / lined / grid). Scales to whatever size it is given.
struct PaperView: View {
    let template: PageTemplate

    var body: some View {
        Canvas { ctx, size in
            guard template != .blank else { return }
            let k = size.width / PageMetrics.size.width
            ctx.scaleBy(x: k, y: k)

            let w = PageMetrics.size.width
            let h = PageMetrics.size.height
            let step: CGFloat = 28

            if template == .dotted {
                var dots = Path()
                var dy = step
                while dy < h {
                    var dx = step
                    while dx < w {
                        dots.addEllipse(in: CGRect(x: dx - 1.4, y: dy - 1.4, width: 2.8, height: 2.8))
                        dx += step
                    }
                    dy += step
                }
                ctx.fill(dots, with: .color(.blue.opacity(0.35)))
                return
            }

            var path = Path()
            var y = step * 2
            while y < h {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
                y += step
            }
            if template == .grid {
                var x = step
                while x < w {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                    x += step
                }
            }
            ctx.stroke(path, with: .color(.blue.opacity(0.18)), lineWidth: 0.7)
        }
        .background(Color.white)
    }
}
