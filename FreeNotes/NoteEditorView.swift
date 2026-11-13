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
    @State private var viewportHeight: CGFloat = 0
    @State private var autoFit = true      // false once you zoom by hand
    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0

    // Delete page
    @State private var pageToDelete: UUID?

    // Insert PDF
    @State private var showImporter = false
    @State private var showPageTemplates = false

    // Page turning
    @State private var pageMode = false         // one page at a time, with a page-turn animation
    @State private var pageIndex = 0
    @State private var flipForward = true

    // Audio
    @StateObject private var recorder = AudioRecorderController()
    @StateObject private var player = AudioPlayerController()
    @State private var showRecordings = false
    @State private var syncMode = false         // tap writing to hear what was being said
    @State private var audioAlert: String?
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
            Group {
                if pageMode {
                    pagedContent(idx: idx)
                } else {
                    scrollContent(idx: idx, width: geo.size.width)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: pageMode)
            .onAppear {
                viewportWidth = geo.size.width
                viewportHeight = geo.size.height
                applyFit()
            }
            .onChange(of: geo.size) { _, newSize in
                viewportWidth = newSize.width
                viewportHeight = newSize.height
                applyFit()
            }
            .onChange(of: pageMode) { _, isPaged in
                if !isPaged { autoFit = true }
                pageIndex = min(pageIndex, max(0, (store.note(noteID)?.pages.count ?? 1) - 1))
                applyFit()
            }
        }
        .background(Color(.systemGray5))
        .overlay { FloatingToolbar(tools: tools) }          // floats over the page; can be moved
        .overlay(alignment: .bottomTrailing) { pagerOverlay(idx) }
        .overlay(alignment: .top) { audioBars }
        .navigationTitle($store.notes[idx].title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(idx) }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $showRecordings) {
            RecordingsSheet(player: player, noteID: noteID)
        }
        .alert("Audio",
               isPresented: Binding(get: { audioAlert != nil || recorder.errorMessage != nil },
                                    set: { if !$0 { audioAlert = nil; recorder.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(audioAlert ?? recorder.errorMessage ?? "") }
        .sheet(isPresented: $showPageTemplates) {
            TemplatePickerSheet { template in addPage(template) }
        }
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
        .onDisappear {
            finishRecording()       // a recording still running is saved, not lost
            player.close()
            store.touch(noteID)
        }
        // Refresh the undo / redo buttons after a stroke, an undo or a redo.
        // (Not NSUndoManagerCheckpoint: checking canRedo posts that one itself, which loops forever.)
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in undoTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in undoTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in undoTick += 1 }
    }

    private func scrollContent(idx: Int, width: CGFloat) -> some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 10) {
                ForEach($store.notes[idx].pages) { $page in
                    pageView(idx: idx, page: $page, showBadge: true)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)      // keeps the last page clear of the toolbar
            .frame(minWidth: width)
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { setZoom(baseZoom * $0.magnification, commit: false) }
                .onEnded { setZoom(baseZoom * $0.magnification, commit: true) }
        )
    }

    /// One page fills the screen; changing page turns it like a book.
    private func pagedContent(idx: Int) -> some View {
        let pages: [NotePage] = store.notes[idx].pages
        let index: Int = min(max(pageIndex, 0), max(pages.count - 1, 0))

        return ZStack {
            if pages.indices.contains(index) {
                pageView(idx: idx, page: $store.notes[idx].pages[index], showBadge: false)
                    .id(pages[index].id)
                    .transition(flipForward ? .flipForward : .flipBackward)
                    .zIndex(-Double(index))     // the earlier page always lies on top, like a book
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pagerOverlay(_ idx: Int) -> some View {
        if pageMode {
            let count: Int = store.notes[idx].pages.count
            HStack(spacing: 4) {
                Button { goToPage(pageIndex - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                .disabled(pageIndex <= 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Previous page")

                Text("\(min(pageIndex, count - 1) + 1) / \(count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 52)

                Button { goToPage(pageIndex + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(pageIndex >= count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityLabel("Next page")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .floatingCapsule()
            .padding(.trailing, 16)
            .padding(.bottom, 96)
        }
    }

    private func goToPage(_ target: Int) {
        let count = store.note(noteID)?.pages.count ?? 0
        guard target >= 0, target < count, target != pageIndex else { return }
        flipForward = target > pageIndex
        Haptics.tap()
        // Let the new direction apply first, then turn the page.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.55)) { pageIndex = target }
        }
    }

    private func addPage(_ template: PageTemplate) {
        guard let n = store.notes.firstIndex(where: { $0.id == noteID }) else { return }
        store.notes[n].pages.append(NotePage(template: template))
        Haptics.success()
        if pageMode { goToPage(store.notes[n].pages.count - 1) }
    }

    private func pageView(idx: Int, page: Binding<NotePage>, showBadge: Bool) -> some View {
        let note: Note = store.notes[idx]
        let pageID: UUID = page.wrappedValue.id
        let number: Int = (note.pages.firstIndex { $0.id == pageID } ?? 0) + 1

        return ZStack(alignment: .topTrailing) {
            pageSurface(note: note, page: page)
            if showBadge {
                pageBadge(number: number, total: note.pages.count, pageID: pageID)
            }
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
            audioTapLayer(pageID: value.id)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: pageMode ? Theme.Radius.small : 0, style: .continuous))
        .softShadow(radius: pageMode ? 18 : 0, y: pageMode ? 8 : 0)
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
                          interactive: !tools.isShape && !syncMode,
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

    /// A small page number in the corner. Tap it for page actions.
    private func pageBadge(number: Int, total: Int, pageID: UUID) -> some View {
        Menu {
            Button(role: .destructive) {
                pageToDelete = pageID
            } label: {
                Label(total <= 1 ? "Clear Page" : "Delete Page", systemImage: "trash")
            }
        } label: {
            Text("\(number) / \(total)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        }
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

            Button { Task { await toggleRecording() } } label: {
                Image(systemName: recorder.state == .idle ? "mic" : "mic.fill")
                    .foregroundStyle(recorder.state == .idle ? Color.accentColor : Color.red)
            }
            .accessibilityLabel(recorder.state == .idle ? "Start recording" : "Stop recording")

            if hasRecordings {
                Button { showRecordings = true } label: { Image(systemName: "waveform") }
                    .accessibilityLabel("Recordings")
                Toggle(isOn: $syncMode) { Image(systemName: "hand.tap") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Tap writing to hear it")
            }

            moreMenu(idx)
        }
    }

    /// Everything that isn't needed every minute lives here, so the top bar stays calm.
    private func moreMenu(_ idx: Int) -> some View {
        Menu {
            Section("View") {
                Picker("Layout", selection: $pageMode) {
                    Label("Continuous Scroll", systemImage: "rectangle.split.1x2").tag(false)
                    Label("One Page at a Time", systemImage: "book").tag(true)
                }
                if !pageMode {
                    Button { setZoom(zoom + 0.25, commit: true) } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .disabled(zoom >= maxZoom)
                    Button { setZoom(zoom - 0.25, commit: true) } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .disabled(zoom <= minZoom)
                    Button { fitWidth() } label: {
                        Label("Fit to Width (\(Int((zoom * 100).rounded()))%)",
                              systemImage: "arrow.left.and.right")
                    }
                }
            }

            Section("Pages") {
                Button { addPage(store.notes[idx].pages.last(where: { $0.pdfID == nil })?.template ?? .lined) } label: {
                    Label("Add Blank Page", systemImage: "doc.badge.plus")
                }
                Button { showPageTemplates = true } label: {
                    Label("Page from Template…", systemImage: "doc.text.image")
                }
                Button { showImporter = true } label: {
                    Label("Insert PDF…", systemImage: "doc.richtext")
                }
                Menu {
                    Picker("Paper", selection: Binding(
                        get: { store.notes[idx].pages.first(where: { $0.pdfID == nil })?.template ?? .lined },
                        set: { new in
                            for i in store.notes[idx].pages.indices where store.notes[idx].pages[i].pdfID == nil {
                                store.notes[idx].pages[i].template = new
                            }
                        })) {
                        ForEach(PageTemplate.basic) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Paper", systemImage: "square.grid.3x3") }
                if pageMode, let current = currentPageID(idx) {
                    Button(role: .destructive) { pageToDelete = current } label: {
                        Label("Delete This Page", systemImage: "trash")
                    }
                }
            }

            Section {
                Toggle(isOn: $pencilOnly) { Label("Apple Pencil Only", systemImage: "applepencil") }
                Button {
                    if let url = PDFExporter.export(store.notes[idx]) { shareItem = ShareItem(url: url) }
                } label: { Label("Export as PDF…", systemImage: "square.and.arrow.up") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    private func currentPageID(_ idx: Int) -> UUID? {
        let pages = store.notes[idx].pages
        guard pages.indices.contains(pageIndex) else { return pages.last?.id }
        return pages[pageIndex].id
    }

    // MARK: - Audio

    private var hasRecordings: Bool {
        !(store.note(noteID)?.recordings.isEmpty ?? true)
    }

    @ViewBuilder
    private var audioBars: some View {
        VStack(spacing: 8) {
            if recorder.state != .idle {
                RecorderPill(recorder: recorder, onStop: finishRecording)
            }
            if player.current != nil {
                PlayerPill(player: player)
            }
            if syncMode {
                Text("Tap any writing to hear what was being said")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func audioTapLayer(pageID: UUID) -> some View {
        if syncMode {
            TapOverlay(zoom: zoom) { point in handleAudioTap(pageID: pageID, point: point) }
        }
    }

    private func toggleRecording() async {
        if recorder.state == .idle {
            await recorder.start()
        } else {
            finishRecording()
        }
    }

    private func finishRecording() {
        guard let recording = recorder.stop() else { return }
        store.addRecording(recording, to: noteID)
        Haptics.success()
    }

    /// Finds the writing under a tap, works out when it was written, and plays the audio from then.
    private func handleAudioTap(pageID: UUID, point: CGPoint) {
        guard let note = store.note(noteID),
              let page = note.pages.first(where: { $0.id == pageID }),
              let drawing = try? PKDrawing(data: page.drawingData),
              let stroke = AudioSync.nearestStroke(in: drawing, to: point, maxDistance: 16) else { return }

        let written = stroke.path.creationDate
        guard let recording = note.recordings.first(where: { $0.offset(for: written) != nil }),
              let offset = recording.offset(for: written) else {
            audioAlert = "That writing wasn't made while a recording was running."
            return
        }
        do {
            // Start a couple of seconds early so the sentence being written is heard in full.
            try player.open(recording, at: max(0, offset - 2), play: true)
            Haptics.tap()
        } catch {
            audioAlert = error.localizedDescription
        }
    }

    // MARK: - Zoom helpers

    private func setZoom(_ value: CGFloat, commit: Bool) {
        let clamped = min(max(value, minZoom), maxZoom)
        zoom = clamped
        autoFit = false
        if commit { baseZoom = clamped }
    }

    /// Fits the page to the screen for whichever layout is on.
    private func applyFit() {
        if pageMode {
            fitWholePage()
        } else if autoFit {
            fitWidth()
        }
    }

    /// One-page mode: the whole page is visible at once.
    private func fitWholePage() {
        guard viewportWidth > 0, viewportHeight > 0 else { return }
        let fit = min(viewportWidth / PageMetrics.size.width,
                      (viewportHeight - 32) / PageMetrics.size.height)
        zoom = max(0.3, fit)
        baseZoom = zoom
    }

    /// Zoom so the page fills the width of the screen.
    private func fitWidth() {
        guard viewportWidth > 0 else { return }
        setZoom(viewportWidth / PageMetrics.size.width, commit: true)
        autoFit = true
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
            pageIndex = min(pageIndex, max(0, store.notes[n].pages.count - 1))
        }
    }
}
