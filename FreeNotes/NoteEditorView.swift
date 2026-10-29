import SwiftUI
import PencilKit
import PDFKit
import UniformTypeIdentifiers

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Owner of undo actions that swap a whole page drawing (used for shapes).
final class UndoTarget: NSObject {
    static let shared = UndoTarget()
}

struct NoteEditorView: View {
    @EnvironmentObject var store: NoteStore
    let noteID: UUID

    @StateObject private var tools = ToolState()
    @State private var pencilOnly = false
    @State private var shareItem: ShareItem?
    @State private var revisions: [UUID: Int] = [:]

    // Zoom
    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var viewportWidth: CGFloat = 0
    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0

    // Delete page
    @State private var pageToDelete: UUID?

    // Insert PDF
    @State private var showImporter = false
    @State private var importError: String?

    // Undo / redo
    @Environment(\.undoManager) private var undoManager
    @State private var undoTick = 0
    private var canUndo: Bool { _ = undoTick; return undoManager?.canUndo ?? false }
    private var canRedo: Bool { _ = undoTick; return undoManager?.canRedo ?? false }

    var body: some View {
        if let idx = store.notes.firstIndex(where: { $0.id == noteID }) {
            editor(idx)
        } else {
            ContentUnavailableView("Note not found", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Editor

    private func editor(_ idx: Int) -> some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: PageMetrics.spacing) {
                    ForEach($store.notes[idx].pages) { $page in
                        pageView(idx: idx, page: $page)
                    }
                }
                .padding(24)
                .frame(minWidth: geo.size.width)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { setZoom(baseZoom * $0.magnification, commit: false) }
                    .onEnded { setZoom(baseZoom * $0.magnification, commit: true) }
            )
            .onAppear {
                viewportWidth = geo.size.width
                // On narrow screens (iPhone) start zoomed out so the page fits.
                if geo.size.width < PageMetrics.size.width + 48 { fitWidth() }
            }
            .onChange(of: geo.size.width) { _, newWidth in viewportWidth = newWidth }
        }
        .background(Color(.systemGray5))
        .safeAreaInset(edge: .bottom) { StationeryBar(tools: tools) }
        .navigationTitle($store.notes[idx].title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(idx) }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                do {
                    try store.insertPDF(from: url, into: noteID)
                    Haptics.success()
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Couldn't insert PDF",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
        .confirmationDialog(deleteTitle,
                            isPresented: Binding(get: { pageToDelete != nil },
                                                 set: { if !$0 { pageToDelete = nil } }),
                            titleVisibility: .visible) {
            Button(deleteButtonLabel, role: .destructive) { deleteSelectedPage() }
            Button("Cancel", role: .cancel) { pageToDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .onDisappear { store.touch(noteID) }
        // Refresh the undo / redo buttons after a stroke, an undo or a redo.
        // (Not NSUndoManagerCheckpoint: checking canRedo posts that one itself, which loops forever.)
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in undoTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in undoTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in undoTick += 1 }
    }

    private func pageView(idx: Int, page: Binding<NotePage>) -> some View {
        let note: Note = store.notes[idx]
        let pageID: UUID = page.wrappedValue.id
        let number: Int = (note.pages.firstIndex { $0.id == pageID } ?? 0) + 1

        return ZStack(alignment: .topTrailing) {
            pageSurface(note: note, page: page)
            pageBadge(number: number, total: note.pages.count, pageID: pageID)
        }
    }

    /// Paper (or PDF page), the ink canvas and, for shape tools, the shape layer.
    private func pageSurface(note: Note, page: Binding<NotePage>) -> some View {
        let value: NotePage = page.wrappedValue
        let width: CGFloat = PageMetrics.size.width * zoom
        let height: CGFloat = PageMetrics.size.height * zoom

        return ZStack {
            backgroundLayer(note: note, page: value)
            canvasLayer(note: note, page: page, value: value)
            shapeLayer(pageID: value.id)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    @ViewBuilder
    private func backgroundLayer(note: Note, page: NotePage) -> some View {
        if page.pdfID != nil {
            PDFPageBackground(page: note.pdfPage(for: page))
        } else {
            PaperView(template: page.template)
        }
    }

    private func canvasLayer(note: Note, page: Binding<NotePage>, value: NotePage) -> some View {
        let isFirst: Bool = value.id == note.pages.first?.id
        let revision: Int = revisions[value.id] ?? 0
        return CanvasView(drawingData: page.drawingData,
                          tool: tools.canvasTool,
                          toolKey: tools.key,
                          pencilOnly: pencilOnly,
                          interactive: !tools.isShape,
                          becomeActive: isFirst,
                          zoom: zoom,
                          revision: revision)
    }

    @ViewBuilder
    private func shapeLayer(pageID: UUID) -> some View {
        if case .shape(let kind) = tools.tool {
            ShapeOverlay(kind: kind,
                         color: tools.color,
                         width: tools.width,
                         zoom: zoom,
                         pencilOnly: pencilOnly,
                         onCommit: { strokes in commitShapes(strokes, pageID: pageID) })
        }
    }

    /// Page number + delete button in the corner of each page.
    private func pageBadge(number: Int, total: Int, pageID: UUID) -> some View {
        HStack(spacing: 10) {
            Text("\(number) / \(total)")
                .font(.caption.monospacedDigit())
            Button(role: .destructive) {
                pageToDelete = pageID
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }

    // MARK: - Shapes

    /// Adds finished shapes to a page's drawing, and makes the change undoable.
    private func commitShapes(_ strokes: [PKStroke], pageID: UUID) {
        guard !strokes.isEmpty,
              let n = store.notes.firstIndex(where: { $0.id == noteID }),
              let p = store.notes[n].pages.firstIndex(where: { $0.id == pageID }) else { return }

        let old = store.notes[n].pages[p].drawingData
        var drawing = (try? PKDrawing(data: old)) ?? PKDrawing()
        drawing.strokes.append(contentsOf: strokes)
        replaceDrawing(pageID: pageID, with: drawing.dataRepresentation(), previous: old)
        Haptics.tap()
    }

    private func replaceDrawing(pageID: UUID, with data: Data, previous: Data) {
        guard let n = store.notes.firstIndex(where: { $0.id == noteID }),
              let p = store.notes[n].pages.firstIndex(where: { $0.id == pageID }) else { return }
        store.notes[n].pages[p].drawingData = data
        revisions[pageID, default: 0] += 1
        // Registering this while undoing makes it the matching redo, and the other way round.
        undoManager?.registerUndo(withTarget: UndoTarget.shared) { _ in
            self.replaceDrawing(pageID: pageID, with: previous, previous: data)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ idx: Int) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!canUndo)
            Button { undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!canRedo)

            Button { setZoom(zoom - 0.25, commit: true) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoom <= minZoom)

            Button("\(Int((zoom * 100).rounded()))%") { fitWidth() }
                .monospacedDigit()

            Button { setZoom(zoom + 0.25, commit: true) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoom >= maxZoom)

            Toggle(isOn: $pencilOnly) { Image(systemName: "applepencil") }
                .toggleStyle(.button)

            Menu {
                Picker("Paper", selection: Binding(
                    get: { store.notes[idx].pages.first(where: { $0.pdfID == nil })?.template ?? .lined },
                    set: { new in
                        for i in store.notes[idx].pages.indices where store.notes[idx].pages[i].pdfID == nil {
                            store.notes[idx].pages[i].template = new
                        }
                    })) {
                    ForEach(PageTemplate.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { Image(systemName: "square.grid.3x3") }

            Menu {
                Button {
                    let template = store.notes[idx].pages.last(where: { $0.pdfID == nil })?.template ?? .lined
                    store.notes[idx].pages.append(NotePage(template: template))
                } label: { Label("Blank Page", systemImage: "doc") }
                Button { showImporter = true } label: {
                    Label("Insert PDF…", systemImage: "doc.richtext")
                }
            } label: { Image(systemName: "plus.rectangle.on.rectangle") }

            Button {
                if let url = PDFExporter.export(store.notes[idx]) {
                    shareItem = ShareItem(url: url)
                }
            } label: { Image(systemName: "square.and.arrow.up") }
        }
    }

    // MARK: - Zoom helpers

    private func setZoom(_ value: CGFloat, commit: Bool) {
        let clamped = min(max(value, minZoom), maxZoom)
        zoom = clamped
        if commit { baseZoom = clamped }
    }

    /// Zoom so the page fills the width of the screen.
    private func fitWidth() {
        guard viewportWidth > 0 else { return }
        setZoom((viewportWidth - 48) / PageMetrics.size.width, commit: true)
    }

    // MARK: - Delete helpers

    private var isOnlyPage: Bool {
        (store.notes.first { $0.id == noteID }?.pages.count ?? 0) <= 1
    }

    private var deleteTitle: String { isOnlyPage ? "Clear this page?" : "Delete this page?" }
    private var deleteButtonLabel: String { isOnlyPage ? "Clear Page" : "Delete Page" }

    private func deleteSelectedPage() {
        Haptics.warning()
        defer { pageToDelete = nil }
        guard let pageID = pageToDelete,
              let n = store.notes.firstIndex(where: { $0.id == noteID }) else { return }

        if store.notes[n].pages.count <= 1 {
            // A note always keeps at least one page, so just wipe it.
            var cleared = store.notes[n].pages[0]
            cleared.drawingData = Data()
            store.notes[n].pages = [cleared]
            revisions[cleared.id, default: 0] += 1
        } else {
            store.notes[n].pages.removeAll { $0.id == pageID }
            store.pruneAttachments(noteID)
        }
    }
}
