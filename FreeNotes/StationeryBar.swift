import SwiftUI
import PencilKit

enum ToolbarDock: String, CaseIterable, Identifiable {
    case bottom, top, leading, trailing
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .leading: return "Left"
        case .trailing: return "Right"
        }
    }

    var axis: Axis { (self == .bottom || self == .top) ? .horizontal : .vertical }

    var alignment: Alignment {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

/// The tools that can be shown or hidden on the toolbar.
enum BarTool: String, CaseIterable, Identifiable {
    case ballpoint, fountain, pencil, highlighter, eraser, lasso, shapes, text, image, ruler, presets
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ballpoint: return "Ballpoint pen"
        case .fountain: return "Fountain pen"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .lasso: return "Select"
        case .shapes: return "Shapes"
        case .text: return "Text boxes"
        case .image: return "Insert image"
        case .ruler: return "Ruler"
        case .presets: return "Pen presets"
        }
    }
}

/// The writing toolbar. It floats above the page, can be dragged to any edge,
/// collapsed to a single button, and its tools can be chosen.
struct FloatingToolbar: View {
    @ObservedObject var tools: ToolState
    var onAddImage: () -> Void = {}
    @AppStorage("toolbarDock") private var dockRaw = ToolbarDock.bottom.rawValue
    @AppStorage("toolbarHidden") private var hiddenRaw = ""
    @AppStorage("toolbarCollapsed") private var collapsed = false
    @AppStorage("penPresets") private var presetsRaw = ""

    @State private var drag: CGSize = .zero
    @State private var showCustomise = false

    private var dock: ToolbarDock { ToolbarDock(rawValue: dockRaw) ?? .bottom }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
    private func show(_ tool: BarTool) -> Bool { !hidden.contains(tool.rawValue) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    if collapsed {
                        collapsedButton
                    } else {
                        expandedBar(in: geo.size)
                    }
                }
                .offset(drag)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dock.alignment)
                .padding(12)
            }
            .coordinateSpace(name: "toolbarArea")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: dockRaw)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: collapsed)
        .sheet(isPresented: $showCustomise) {
            ToolbarCustomiseSheet(hiddenRaw: $hiddenRaw, dockRaw: $dockRaw)
        }
    }

    // MARK: Layout

    private func stack(_ axis: Axis, spacing: CGFloat = 6) -> AnyLayout {
        axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
    }

    private func expandedBar(in size: CGSize) -> some View {
        let axis = dock.axis
        return stack(axis, spacing: 4) {
            grip(axis: axis, size: size)

            // If everything fits it just sits there; on small screens it scrolls.
            ViewThatFits(in: axis == .horizontal ? .horizontal : .vertical) {
                toolRow(axis)
                ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                    toolRow(axis)
                }
            }

            Button {
                collapsed = true
                Haptics.tap()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Collapse toolbar")
        }
        .padding(6)
        .floatingPanel(cornerRadius: 30)
        .contextMenu {
            Picker("Move to", selection: $dockRaw) {
                ForEach(ToolbarDock.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Button { collapsed = true } label: { Label("Collapse", systemImage: "minus.circle") }
            Button { showCustomise = true } label: {
                Label("Customise Tools…", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func toolRow(_ axis: Axis) -> some View {
        stack(axis) {
            if show(.ballpoint) { toolButton(.ballpoint, symbol: "pencil.tip", label: "Ballpoint pen") }
            if show(.fountain) { toolButton(.fountain, symbol: "pencil.tip.crop.circle", label: "Fountain pen") }
            if show(.pencil) { toolButton(.pencil, symbol: "pencil", label: "Pencil") }
            if show(.highlighter) { toolButton(.highlighter, symbol: "highlighter", label: "Highlighter") }
            if show(.eraser) { eraserMenu }
            if show(.lasso) { toolButton(.lasso, symbol: "lasso", label: "Select") }
            if show(.shapes) { shapeMenu }
            if show(.text) { toolButton(.objects, symbol: "textformat", label: "Text boxes") }
            if show(.image) {
                Button { onAddImage() } label: { icon("photo", selected: false) }
                    .accessibilityLabel("Insert image")
            }
            if show(.ruler) {
                Button {
                    tools.rulerOn.toggle()
                    Haptics.tap()
                } label: { icon("ruler", selected: tools.rulerOn) }
                .accessibilityLabel("Ruler")
            }
            if show(.presets) { presetsMenu }

            if tools.usesColor {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: axis == .horizontal ? 1 : 26, height: axis == .horizontal ? 26 : 1)
                    .padding(axis == .horizontal ? .horizontal : .vertical, 6)
                ForEach(ToolState.palette.indices, id: \.self) { index in colorDot(index) }
                customColorWell
                Slider(value: $tools.width, in: 1...24)
                    .frame(width: 110)
                    .padding(axis == .horizontal ? .leading : .top, 8)
                    .accessibilityLabel("Thickness")
            }
        }
    }

    private func grip(axis: Axis, size: CGSize) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: axis == .horizontal ? 4 : 26, height: axis == .horizontal ? 26 : 4)
            .padding(10)
            .contentShape(Rectangle())
            .gesture(dragGesture(in: size))
            .accessibilityLabel("Move toolbar")
    }

    /// Dragging the grip and letting go snaps the toolbar to the nearest edge.
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("toolbarArea"))
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let p = value.location
                let distances: [(ToolbarDock, CGFloat)] = [
                    (.top, p.y), (.bottom, size.height - p.y),
                    (.leading, p.x), (.trailing, size.width - p.x)
                ]
                let nearest = distances.min { $0.1 < $1.1 }?.0 ?? .bottom
                if nearest.rawValue != dockRaw { Haptics.tap() }
                dockRaw = nearest.rawValue
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { drag = .zero }
            }
    }

    // MARK: Collapsed

    private var currentSymbol: String {
        switch tools.tool {
        case .ballpoint: return "pencil.tip"
        case .fountain: return "pencil.tip.crop.circle"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .eraserStroke, .eraserPixel: return "eraser"
        case .lasso: return "lasso"
        case .shape(let kind): return kind.symbol
        case .objects: return "textformat"
        }
    }

    private var collapsedButton: some View {
        Button {
            collapsed = false
            Haptics.tap()
        } label: {
            Image(systemName: currentSymbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 54, height: 54)
        }
        .floatingCapsule()
        .accessibilityLabel("Show toolbar")
    }

    // MARK: Buttons

    private func icon(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .frame(width: 44, height: 40)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
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

    /// Any colour at all, from the system colour picker.
    private var customColorWell: some View {
        ColorPicker("Custom colour", selection: Binding(
            get: { Color(uiColor: tools.color) },
            set: {
                tools.customColor = UIColor($0)
                Haptics.tap()
            }), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 34, height: 34)
    }

    // MARK: Pen presets

    private var presets: [PenPreset] {
        (try? JSONDecoder().decode([PenPreset].self, from: Data(presetsRaw.utf8))) ?? []
    }

    private func store(_ list: [PenPreset]) {
        if let data = try? JSONEncoder().encode(list), let text = String(data: data, encoding: .utf8) {
            presetsRaw = text
        }
    }

    private var currentPenName: String? {
        switch tools.tool {
        case .ballpoint: return "ballpoint"
        case .fountain: return "fountain"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        default: return nil
        }
    }

    private func title(for preset: PenPreset) -> String {
        preset.tool.capitalized + " · " + Int(preset.width).description + " pt"
    }

    private func apply(_ preset: PenPreset) {
        switch preset.tool {
        case "fountain": tools.tool = .fountain
        case "pencil": tools.tool = .pencil
        case "highlighter": tools.tool = .highlighter
        default: tools.tool = .ballpoint
        }
        tools.customColor = UIColor(red: preset.red, green: preset.green, blue: preset.blue, alpha: 1)
        tools.width = CGFloat(preset.width)
        Haptics.tap()
    }

    private func saveCurrentPreset() {
        guard let name = currentPenName else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tools.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var list = presets
        list.append(PenPreset(tool: name, red: Double(r), green: Double(g), blue: Double(b), width: Double(tools.width)))
        store(Array(list.suffix(12)))
        Haptics.success()
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button(title(for: preset)) { apply(preset) }
            }
            if !presets.isEmpty {
                Menu("Remove Preset") {
                    ForEach(presets) { preset in
                        Button(title(for: preset), role: .destructive) {
                            store(presets.filter { $0.id != preset.id })
                        }
                    }
                }
                Divider()
            }
            Button { saveCurrentPreset() } label: { Label("Save Current Pen", systemImage: "plus") }
                .disabled(currentPenName == nil)
        } label: {
            icon("bookmark", selected: false)
        }
        .accessibilityLabel("Pen presets")
    }

    private func colorDot(_ index: Int) -> some View {
        let selected = tools.customColor == nil && tools.colorIndex == index
        return Circle()
            .fill(Color(uiColor: ToolState.palette[index]))
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-4))
            .padding(4)
            .onTapGesture {
                tools.customColor = nil
                tools.colorIndex = index
                Haptics.tap()
            }
            .accessibilityLabel("Colour \(index + 1)")
    }
}

/// Choose where the toolbar lives and which tools it shows.
struct ToolbarCustomiseSheet: View {
    @Binding var hiddenRaw: String
    @Binding var dockRaw: String
    @Environment(\.dismiss) private var dismiss

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    Picker("Dock", selection: $dockRaw) {
                        ForEach(ToolbarDock.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Tools") {
                    ForEach(BarTool.allCases) { tool in
                        Toggle(tool.title, isOn: Binding(
                            get: { !hidden.contains(tool.rawValue) },
                            set: { visible in
                                var updated = hidden
                                if visible {
                                    updated.remove(tool.rawValue)
                                } else if updated.count < BarTool.allCases.count - 1 {
                                    updated.insert(tool.rawValue)     // always keep at least one tool
                                }
                                hiddenRaw = updated.sorted().joined(separator: ",")
                            }))
                    }
                }
                Section {
                    Button("Reset to Default", role: .destructive) {
                        hiddenRaw = ""
                        dockRaw = ToolbarDock.bottom.rawValue
                    }
                }
            }
            .navigationTitle("Customise Toolbar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}


/// A saved pen: which tool, colour and thickness.
struct PenPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var tool: String
    var red: Double
    var green: Double
    var blue: Double
    var width: Double
}
