import SwiftUI
import PencilKit

// MARK: - Shapes

enum ShapeBuilder {
    /// The corner points of a shape dragged from `s` to `e`.
    static func outline(_ kind: ShapeKind, from s: CGPoint, to e: CGPoint, headLength: CGFloat) -> [CGPoint] {
        let minX = min(s.x, e.x), maxX = max(s.x, e.x)
        let minY = min(s.y, e.y), maxY = max(s.y, e.y)

        switch kind {
        case .line:
            return [s, e]
        case .arrow:
            let angle = atan2(e.y - s.y, e.x - s.x)
            let spread = CGFloat.pi / 7
            func head(_ delta: CGFloat) -> CGPoint {
                CGPoint(x: e.x - headLength * cos(angle + delta),
                        y: e.y - headLength * sin(angle + delta))
            }
            return [s, e, head(spread), e, head(-spread)]
        case .rectangle:
            return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                    CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY),
                    CGPoint(x: minX, y: minY)]
        case .triangle:
            let top = CGPoint(x: (minX + maxX) / 2, y: minY)
            return [top, CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY), top]
        case .ellipse:
            let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let rx = (maxX - minX) / 2, ry = (maxY - minY) / 2
            return (0...72).map { i in
                let a = CGFloat(i) / 72 * 2 * CGFloat.pi
                return CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a))
            }
        }
    }

    /// Turns a shape into a real PencilKit stroke, so it can be erased, selected and moved
    /// just like handwriting.
    static func strokes(_ kind: ShapeKind, from s: CGPoint, to e: CGPoint,
                        color: UIColor, width: CGFloat) -> [PKStroke] {
        let corners = outline(kind, from: s, to: e, headLength: max(14, width * 4))
        let points = densify(corners, spacing: 3)
        guard points.count > 1 else { return [] }

        var controlPoints: [PKStrokePoint] = []
        var time: TimeInterval = 0
        for p in points {
            controlPoints.append(PKStrokePoint(location: p, timeOffset: time,
                                               size: CGSize(width: width, height: width),
                                               opacity: 1, force: 1,
                                               azimuth: 0, altitude: .pi / 2))
            time += 0.002
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        return [PKStroke(ink: PKInk(.pen, color: color), path: path)]
    }

    private static func densify(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for p in points.dropFirst() {
            let dx = p.x - last.x, dy = p.y - last.y
            let steps = max(1, Int(hypot(dx, dy) / spacing))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                result.append(CGPoint(x: last.x + dx * t, y: last.y + dy * t))
            }
            last = p
        }
        return result
    }
}

/// Sits on top of a page while a shape tool is selected and turns a drag into a shape.
struct ShapeOverlay: UIViewRepresentable {
    let kind: ShapeKind
    let color: UIColor
    let width: CGFloat
    let zoom: CGFloat
    let pencilOnly: Bool
    let onCommit: ([PKStroke]) -> Void

    func makeUIView(context: Context) -> ShapeCaptureView { ShapeCaptureView() }

    func updateUIView(_ view: ShapeCaptureView, context: Context) {
        view.kind = kind
        view.color = color
        view.lineWidth = width
        view.zoom = zoom
        view.onCommit = onCommit
        view.setPencilOnly(pencilOnly)
    }
}

final class ShapeCaptureView: UIView {
    var kind: ShapeKind = .rectangle
    var color: UIColor = .black
    var lineWidth: CGFloat = 4
    var zoom: CGFloat = 1
    var onCommit: (([PKStroke]) -> Void)?

    private var origin: CGPoint?
    private let preview = CAShapeLayer()
    private let pan = UIPanGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        preview.fillColor = nil
        preview.lineCap = .round
        preview.lineJoin = .round
        layer.addSublayer(preview)

        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1      // two fingers still scroll the page
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPencilOnly(_ on: Bool) {
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
        let pointer = NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        pan.allowedTouchTypes = on ? [pencil] : [finger, pencil, pointer]
    }

    // The pan recognizer only reports where the finger is after it has moved a little,
    // so the exact starting point is taken from the first touch.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first { origin = touch.location(in: self) }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let start = origin else { return }
        let end = gesture.location(in: self)

        switch gesture.state {
        case .began, .changed:
            showPreview(from: start, to: end)
        case .ended:
            preview.path = nil
            origin = nil
            guard hypot(end.x - start.x, end.y - start.y) > 6 else { return }
            let z = max(zoom, 0.01)
            let strokes = ShapeBuilder.strokes(kind,
                                               from: CGPoint(x: start.x / z, y: start.y / z),
                                               to: CGPoint(x: end.x / z, y: end.y / z),
                                               color: color, width: lineWidth)
            onCommit?(strokes)
        default:
            preview.path = nil
            origin = nil
        }
    }

    private func showPreview(from s: CGPoint, to e: CGPoint) {
        let corners = ShapeBuilder.outline(kind, from: s, to: e,
                                           headLength: max(14, lineWidth * 4) * zoom)
        let path = UIBezierPath()
        for (index, point) in corners.enumerated() {
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        preview.path = path.cgPath
        preview.strokeColor = color.cgColor
        preview.lineWidth = lineWidth * zoom
    }
}
