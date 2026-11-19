import SwiftUI

/// The touch-and-hold menu for a note card: favourite, rename, duplicate, move, delete.
/// Used on the home screen; the Notes screen has the same actions.
private struct NoteContextMenu: ViewModifier {
    @EnvironmentObject var store: NoteStore
    let noteID: UUID

    @State private var showRename = false
    @State private var renameText = ""
    @State private var showMove = false
    @State private var showDelete = false

    func body(content: Content) -> some View {
        content
            .contextMenu { menu }
            .alert("Rename Note", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { rename() }
            }
            .sheet(isPresented: $showMove) { MoveNoteSheet(noteID: noteID) }
            .confirmationDialog("Delete this note?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) {
                    Haptics.warning()
                    store.deleteNote(noteID)
                }
            } message: {
                Text("This can't be undone.")
            }
    }

    @ViewBuilder
    private var menu: some View {
        let favourite: Bool = store.note(noteID)?.isFavorite ?? false
        Button {
            store.toggleFavourite(noteID)
            Haptics.tap()
        } label: {
            Label(favourite ? "Remove Favourite" : "Favourite",
                  systemImage: favourite ? "star.slash" : "star")
        }
        Button {
            renameText = store.note(noteID)?.title ?? ""
            showRename = true
        } label: { Label("Rename", systemImage: "pencil") }
        Button {
            if store.duplicate(noteID) != nil { Haptics.success() }
        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { showMove = true } label: { Label("Move…", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { showDelete = true } label: { Label("Delete", systemImage: "trash") }
    }

    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { store.renameNote(noteID, to: name) }
    }
}

extension View {
    func noteContextMenu(_ noteID: UUID) -> some View {
        modifier(NoteContextMenu(noteID: noteID))
    }
}
