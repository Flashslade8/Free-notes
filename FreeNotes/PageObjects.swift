import SwiftUI
import UIKit

/// The pen and text colours. Kept outside the tool state so exporting can use it too.
enum InkPalette {
    static let colors: [UIColor] = [
        UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),   // black
        UIColor(red: 0.10, green: 0.40, blue: 0.95, alpha: 1),   // blue
        UIColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1),   // red
        UIColor(red: 0.15, green: 0.65, blue: 0.30, alpha: 1),   // green
        UIColor(red: 0.98, green: 0.55, blue: 0.10, alpha: 1),   // orange
        UIColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 1),   // purple
        UIColor(red: 1.00, green: 0.85, blue: 0.10, alpha: 1)    // yellow
    ]

    static let names = ["Black", "Blue", "Red", "Green", "Orange", "Purple", "Yellow"]
}

/// A text box or picture placed on a page. Positions and sizes are in page points.
struct PageObject: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, image }

    var id = UUID()
    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 18
    var colorIndex: Int = 0
    var imageData: Data? = nil

    var uiColor: UIColor {
        InkPalette.colors[min(max(colorIndex, 0), InkPalette.colors.count - 1)]
    }
}

enum ObjectImages {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for object: PageObject) -> UIImage? {
        guard let data = object.imageData else { return nil }
        let key = "\(object.id)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Shrinks a chosen picture so notes stay small enough to save and sync.
    static func prepare(_ data: Data, maxSide: CGFloat = 1600) -> (data: Data, aspect: CGFloat)? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.75) else { return nil }
        return (jpeg, size.width / size.height)
    }
}

/// The text boxes and pictures of one page. They sit under the ink, and can be
/// moved, resized and edited while the Text tool is selected.
struct PageObjectsLayer: View {
    @Binding var objects: [PageObject]
    @Binding var selectedID: UUID?
    let zoom: CGFloat
    let editable: Bool
    let onTapEmpty: (CGPoint) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if editable {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        onTapEmpty(CGPoint(x: location.x / zoom, y: location.y / zoom))
                    }
            }
            ForEach($objects) { $object in
                ObjectBox(object: $object,
                          selected: selectedID == object.id,
                          zoom: zoom,
                          editable: editable,
                          onSelect: { selectedID = object.id },
                          onDelete: { remove(object.id) },
                          onDuplicate: { duplicate(object) })
                    .zIndex(selectedID == object.id ? 1 : 0)
            }
        }
        .coordinateSpace(name: "objectsSpace")
        .frame(width: PageMetrics.size.width * zoom,
               height: PageMetrics.size.height * zoom,
               alignment: .topLeading)
        .allowsHitTesting(editable)
    }

    private func remove(_ id: UUID) {
        objects.removeAll { $0.id == id }
        selectedID = nil
        Haptics.warning()
    }

    private func duplicate(_ object: PageObject) {
        var copy = object
        copy.id = UUID()
        copy.x = min(object.x + 24, PageMetrics.size.width - 40)
        copy.y = min(object.y + 24, PageMetrics.size.height - 40)
        objects.append(copy)
        selectedID = copy.id
        Haptics.tap()
    }
}

private struct ObjectBox: View {
    @Binding var object: PageObject
    let selected: Bool
    let zoom: CGFloat
    let editable: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @FocusState private var focused: Bool
    @State private var moveStart: CGPoint?
    @State private var sizeStart: CGSize?

    private var active: Bool { selected && editable }
    private var color: Color { Color(uiColor: object.uiColor) }

    var body: some View {
        let width: CGFloat = object.width * zoom
        let height: CGFloat = object.height * zoom

        return content(width: width, height: height)
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay {
                if active { Rectangle().stroke(Color.accentColor, lineWidth: 1.5) }
            }
            .overlay(alignment: .bottomTrailing) {
                if active { resizeHandle }
            }
            .overlay(alignment: .top) {
                if active { contextBar.offset(y: -54) }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .offset(x: object.x * zoom, y: object.y * zoom)
    }

    // MARK: Content

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        switch object.kind {
        case .image:
            Group {
                if let image = ObjectImages.image(for: object) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(moveGesture)
        case .text:
            if active {
                TextEditor(text: $object.text)
                    .font(.system(size: object.fontSize * zoom, design: .rounded))
                    .foregroundStyle(color)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .onAppear {
                        if object.text.isEmpty {
                            DispatchQueue.main.async { focused = true }
                        }
                    }
            } else {
                Text(object.text.isEmpty ? " " : object.text)
                    .font(.system(size: object.fontSize * zoom, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: Moving and resizing

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("objectsSpace"))
            .onChanged { value in
                let start = moveStart ?? CGPoint(x: object.x, y: object.y)
                if moveStart == nil {
                    moveStart = start
                    onSelect()
                }
                object.x = min(max(0, start.x + value.translation.width / zoom), PageMetrics.size.width - 20)
                object.y = min(max(0, start.y + value.translation.height / zoom), PageMetrics.size.height - 20)
            }
            .onEnded { _ in moveStart = nil }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .padding(10)                    // a bigger area to grab
            .contentShape(Circle())
            .offset(x: 21, y: 21)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("objectsSpace"))
                    .onChanged { value in
                        let start = sizeStart ?? CGSize(width: object.width, height: object.height)
                        if sizeStart == nil { sizeStart = start }
                        let newWidth = max(40, start.width + value.translation.width / zoom)
                        var newHeight = max(24, start.height + value.translation.height / zoom)
                        if object.kind == .image {
                            newHeight = newWidth / max(start.width / max(start.height, 1), 0.01)   // keep the picture's shape
                        }
                        object.width = min(newWidth, PageMetrics.size.width)
                        object.height = min(newHeight, PageMetrics.size.height)
                    }
                    .onEnded { _ in sizeStart = nil }
            )
            .accessibilityLabel("Resize")
    }

    // MARK: Controls above the selected box

    private var contextBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .accessibilityLabel("Move")

            if object.kind == .text {
                Button { object.fontSize = max(8, object.fontSize - 2) } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .accessibilityLabel("Smaller text")
                Button { object.fontSize = min(96, object.fontSize + 2) } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .accessibilityLabel("Larger text")
                Menu {
                    ForEach(InkPalette.names.indices, id: \.self) { index in
                        Button(InkPalette.names[index]) { object.colorIndex = index }
                    }
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                }
                .accessibilityLabel("Text colour")
            }

            Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                .accessibilityLabel("Duplicate")
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .accessibilityLabel("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .floatingCapsule()
        .fixedSize()
    }
}
