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

    var body: some View {
        if let idx = store.notes.firstIndex(where: { $0.id == noteID }) {
            editor(idx)
        } else {
            ContentUnavailableView("Note not found", systemImage: "questionmark.folder")
        }
    }

    private func editor(_ idx: Int) -> some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: PageMetrics.spacing) {
                ForEach($store.notes[idx].pages) { $page in
                    ZStack {
                        PaperView(template: page.template)
                        CanvasView(drawingData: $page.drawingData,
                                   picker: picker,
                                   pencilOnly: pencilOnly,
                                   becomeActive: page.id == store.notes[idx].pages.first?.id)
                    }
                    .frame(width: PageMetrics.size.width, height: PageMetrics.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
            }
            .padding(24)
        }
        .background(Color(.systemGray5))
        .navigationTitle($store.notes[idx].title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $pencilOnly) {
                    Image(systemName: "applepencil")
                }
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
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .onDisappear { store.touch(noteID) }
    }
}
