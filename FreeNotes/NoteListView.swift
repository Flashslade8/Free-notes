import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var store: NoteStore
    @State private var search = ""
    @State private var path: [UUID] = []

    private var visibleNotes: [Note] {
        let sorted = store.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        guard !search.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(visibleNotes) { note in
                    NavigationLink(value: note.id) {
                        HStack(spacing: 12) {
                            thumbnail(for: note)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title).font(.headline)
                                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(note.pages.count) page\(note.pages.count == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { store.delete(at: $0, from: visibleNotes) }
            }
            .overlay {
                if store.notes.isEmpty {
                    ContentUnavailableView("No Notes Yet", systemImage: "pencil.and.scribble",
                                           description: Text("Tap + to create your first note."))
                }
            }
            .navigationTitle("Free Notes")
            .searchable(text: $search)
            .toolbar {
                Button {
                    let note = store.addNote()
                    path.append(note.id)
                } label: { Image(systemName: "square.and.pencil") }
            }
            .navigationDestination(for: UUID.self) { id in
                NoteEditorView(noteID: id)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for note: Note) -> some View {
        Group {
            if let image = note.thumbnail {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 62)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
    }
}
