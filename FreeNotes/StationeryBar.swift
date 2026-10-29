import SwiftUI
import PencilKit

// MARK: - Toolbar

struct StationeryBar: View {
    @ObservedObject var tools: ToolState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                toolButton(.ballpoint, symbol: "pencil.tip", label: "Ballpoint pen")
                toolButton(.fountain, symbol: "pencil.tip.crop.circle", label: "Fountain pen")
                toolButton(.pencil, symbol: "pencil", label: "Pencil")
                toolButton(.highlighter, symbol: "highlighter", label: "Highlighter")
                eraserMenu
                toolButton(.lasso, symbol: "lasso", label: "Select")
                shapeMenu

                if tools.usesColor {
                    Divider().frame(height: 28).padding(.horizontal, 6)
                    ForEach(ToolState.palette.indices, id: \.self) { index in
                        colorDot(index)
                    }
                    Slider(value: $tools.width, in: 1...24)
                        .frame(width: 110)
                        .padding(.leading, 8)
                        .accessibilityLabel("Thickness")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func icon(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .frame(width: 44, height: 40)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
    }

    private func toolButton(_ tool: Stationery, symbol: String, label: String) -> some View {
        Button { tools.select(tool) } label: {
            icon(symbol, selected: tools.tool == tool)
        }
        .accessibilityLabel(label)
    }

    private var eraserMenu: some View {
        Menu {
            Button { tools.select(.eraserStroke) } label: {
                Label("Stroke Eraser", systemImage: "eraser")
            }
            Button { tools.select(.eraserPixel) } label: {
                Label("Pixel Eraser", systemImage: "eraser.fill")
            }
        } label: {
            icon(tools.tool == .eraserPixel ? "eraser.fill" : "eraser", selected: tools.isEraser)
        } primaryAction: {
            tools.selectLastEraser()
        }
        .accessibilityLabel("Eraser")
    }

    private var shapeMenu: some View {
        Menu {
            ForEach(ShapeKind.allCases) { kind in
                Button { tools.select(.shape(kind)) } label: {
                    Label(kind.label, systemImage: kind.symbol)
                }
            }
        } label: {
            if case .shape(let kind) = tools.tool {
                icon(kind.symbol, selected: true)
            } else {
                icon("square.on.circle", selected: false)
            }
        } primaryAction: {
            tools.selectLastShape()
        }
        .accessibilityLabel("Shapes")
    }

    private func colorDot(_ index: Int) -> some View {
        let selected = tools.colorIndex == index
        return Circle()
            .fill(Color(uiColor: ToolState.palette[index]))
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-4))
            .padding(4)
            .onTapGesture {
                tools.colorIndex = index
                Haptics.tap()
            }
            .accessibilityLabel("Colour \(index + 1)")
    }
}
