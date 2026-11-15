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
    case objects            // text boxes and pictures
}

/// The selected tool, colour and thickness.
@MainActor
final class ToolState: ObservableObject {
    @Published var tool: Stationery = .ballpoint
    @Published var colorIndex = 0
    @Published var width: CGFloat = 4
    @Published var customColor: UIColor? = nil     // chosen with the colour picker
    @Published var rulerOn = false
    private(set) var lastEraser: Stationery = .eraserStroke
    private(set) var lastShape: ShapeKind = .rectangle

    static let palette: [UIColor] = InkPalette.colors

    var color: UIColor { customColor ?? Self.palette[colorIndex] }

    var isEraser: Bool { tool == .eraserStroke || tool == .eraserPixel }

    var isShape: Bool {
        if case .shape = tool { return true }
        return false
    }

    var usesColor: Bool {
        switch tool {
        case .eraserStroke, .eraserPixel, .lasso, .objects: return false
        default: return true
        }
    }

    /// Changes whenever the canvas needs to be given a new tool.
    var key: String { "\(tool)-\(colorIndex)-\(customColor?.description ?? "-")-\(Int(width * 10))" }

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
        case .objects: return PKInkingTool(.pen, color: color, width: width)  // not used while editing text boxes
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
