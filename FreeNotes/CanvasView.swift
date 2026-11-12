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

/// A single handwriting page. PencilKit draws the ink; the toolbar picks the tool.
/// The canvas is zoomed natively, so ink stays sharp at any zoom level.
struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    let tool: PKTool
    let toolKey: String
    let pencilOnly: Bool
    let interactive: Bool       // false while a shape tool is selected
    let becomeActive: Bool
    let zoom: CGFloat
    let revision: Int           // changes when the drawing is replaced from outside (shapes, undo)

    func makeUIView(context: Context) -> ZoomableCanvas {
        let canvas = ZoomableCanvas()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear      // paper is drawn behind by SwiftUI
        canvas.isOpaque = false
        canvas.isScrollEnabled = false       // the outer ScrollView handles scrolling
        canvas.overrideUserInterfaceStyle = .light   // paper is always white, so ink must look right on it
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        // Logical (unzoomed) size of the page; zoom is applied on top of this.
        canvas.contentSize = PageMetrics.size
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 4
        canvas.targetZoom = zoom
        canvas.tool = tool
        canvas.isUserInteractionEnabled = interactive

        context.coordinator.toolKey = toolKey
        context.coordinator.revision = revision
        if becomeActive {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: ZoomableCanvas, context: Context) {
        let coordinator = context.coordinator
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.targetZoom = zoom
        canvas.setNeedsLayout()
        canvas.isUserInteractionEnabled = interactive

        if coordinator.toolKey != toolKey {
            canvas.tool = tool
            coordinator.toolKey = toolKey
        }
        if coordinator.revision != revision {
            coordinator.revision = revision
            if let drawing = try? PKDrawing(data: drawingData) {
                canvas.drawing = drawing
            }
        }
        coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        var toolKey = ""
        var revision = 0
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawingData = canvasView.drawing.dataRepresentation()
        }
    }
}
