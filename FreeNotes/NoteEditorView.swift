import SwiftUI
import PencilKit

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

struct NoteEditorView: View {
    @EnvironmentObject var store: NoteStore
    let noteID: UUID

    @State private var picker = PKToolPicker()
    @State private var pencilOnly = false
    @State private var shareItem: ShareItem?

    // Zoom
    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var viewportWidth: CGFloat = 0
    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0

    // Delete
    @State private var pageToDelete: UUID?

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
        .navigationTitle($store.notes[idx].title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(idx) }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
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
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerCheckpoint)) { _ in
            undoTick += 1       // refreshes the undo / redo buttons
        }
    }

    private func pageView(idx: Int, page: Binding<NotePage>) -> some View {
        let pages = store.notes[idx].pages
        let number = (pages.firstIndex { $0.id == page.wrappedValue.id } ?? 0) + 1

        return ZStack(alignment: .topTrailing) {
            ZStack {
                PaperView(template: page.wrappedValue.template)
                CanvasView(drawingData: page.drawingData,
                           picker: picker,
                           pencilOnly: pencilOnly,
                           becomeActive: page.wrappedValue.id == pages.first?.id,
                           zoom: zoom)
            }
            .frame(width: PageMetrics.size.width * zoom,
                   height: PageMetrics.size.height * zoom)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)

            // Page number + delete button
            HStack(spacing: 10) {
                Text("\(number) / \(pages.count)")
                    .font(.caption.monospacedDigit())
                Button(role: .destructive) {
                    pageToDelete = page.wrappedValue.id
                } label: {
                    Image(systemName: "trash")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)
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
                    get: { store.notes[idx].pages.first?.template ?? .lined },
                    set: { new in
                        for i in store.notes[idx].pages.indices {
                            store.notes[idx].pages[i].template = new
                        }
                    })) {
                    ForEach(PageTemplate.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { Image(systemName: "square.grid.3x3") }

            Button {
                let template = store.notes[idx].pages.last?.template ?? .lined
                store.notes[idx].pages.append(NotePage(template: template))
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
            let template = store.notes[n].pages.first?.template ?? .lined
            store.notes[n].pages = [NotePage(template: template)]
        } else {
            store.notes[n].pages.removeAll { $0.id == pageID }
        }
    }
}
