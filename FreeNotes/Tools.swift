import SwiftUI
import PencilKit

enum ShapeKind: String, CaseIterable, Identifiable {
    case line, arrow, rectangle, ellipse, triangle
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .triangle: return "triangle"
        }
    }
}

/// Everything on the toolbar.
enum Stationery: Hashable {
    case ballpoint, fountain, pencil, highlighter
    case eraserStroke, eraserPixel
    case lasso
    case shape(ShapeKind)
}

/// The selected tool, colour and thickness.
@MainActor
final class ToolState: ObservableObject {
    @Published var tool: Stationery = .ballpoint
    @Published var colorIndex = 0
    @Published var width: CGFloat = 4
    private(set) var lastEraser: Stationery = .eraserStroke
    private(set) var lastShape: ShapeKind = .rectangle

    static let palette: [UIColor] = [
        UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),   // black
        UIColor(red: 0.10, green: 0.40, blue: 0.95, alpha: 1),   // blue
        UIColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1),   // red
        UIColor(red: 0.15, green: 0.65, blue: 0.30, alpha: 1),   // green
        UIColor(red: 0.98, green: 0.55, blue: 0.10, alpha: 1),   // orange
        UIColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 1),   // purple
        UIColor(red: 1.00, green: 0.85, blue: 0.10, alpha: 1)    // yellow
    ]

    var color: UIColor { Self.palette[colorIndex] }

    var isEraser: Bool { tool == .eraserStroke || tool == .eraserPixel }

    var isShape: Bool {
        if case .shape = tool { return true }
        return false
    }

    var usesColor: Bool {
        switch tool {
        case .eraserStroke, .eraserPixel, .lasso: return false
        default: return true
        }
    }

    /// Changes whenever the canvas needs to be given a new tool.
    var key: String { "\(tool)-\(colorIndex)-\(Int(width * 10))" }

    var canvasTool: PKTool {
        switch tool {
        case .ballpoint: return PKInkingTool(.pen, color: color, width: width)
        case .fountain: return PKInkingTool(.fountainPen, color: color, width: width)
        case .pencil: return PKInkingTool(.pencil, color: color, width: width)
        case .highlighter: return PKInkingTool(.marker, color: color, width: max(10, width * 2.5))
        case .eraserStroke: return PKEraserTool(.vector)
        case .eraserPixel: return PKEraserTool(.bitmap)
        case .lasso: return PKLassoTool()
        case .shape: return PKInkingTool(.pen, color: color, width: width)   // not used while drawing shapes
        }
    }

    func select(_ newTool: Stationery) {
        tool = newTool
        switch newTool {
        case .eraserStroke, .eraserPixel: lastEraser = newTool
        case .shape(let kind): lastShape = kind
        default: break
        }
        Haptics.tap()
    }

    func selectLastShape() { select(.shape(lastShape)) }
    func selectLastEraser() { select(lastEraser) }
}
