import SwiftUI
import PencilKit

/// A single handwriting page backed by PKCanvasView.
struct CanvasView: UIViewRepresentable {
    @Binding var drawingData: Data
    let picker: PKToolPicker
    let pencilOnly: Bool
    let becomeActive: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear      // paper is drawn behind by SwiftUI
        canvas.isOpaque = false
        canvas.isScrollEnabled = false       // the outer ScrollView handles scrolling
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        if becomeActive {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
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

/// Paper background (blank / lined / grid) drawn behind the canvas.
struct PaperView: View {
    let template: PageTemplate

    var body: some View {
        Canvas { ctx, size in
            guard template != .blank else { return }
            let step: CGFloat = 28
            var path = Path()
            var y = step * 2
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            if template == .grid {
                var x = step
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
            }
            ctx.stroke(path, with: .color(.blue.opacity(0.18)), lineWidth: 0.7)
        }
        .background(Color.white)
    }
}
