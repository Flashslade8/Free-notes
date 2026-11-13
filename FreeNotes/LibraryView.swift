import SwiftUI
import UniformTypeIdentifiers

enum SortOrder: String, CaseIterable, Identifiable {
    case edited = "Last Edited", created = "Date Created", name = "Name"
    var id: String { rawValue }
}

struct IDBox: Identifiable {
    let id: UUID
}

enum LibraryPrompt {
    case newFolder(parent: UUID?)
    case renameNote(UUID)
    case renameFolder(UUID)
}

/// Shows the folders and notes for whatever is selected in the sidebar.
struct LibraryView: View {
    @EnvironmentObject var store: NoteStore
    let scope: SidebarItem
    @Binding var selection: SidebarItem?
    @Binding var path: NavigationPath
    let searchText: String

    @AppStorage("viewMode") private var viewMode = "grid"
    @AppStorage("sortOrder") private var sortRaw = SortOrder.edited.rawValue

    @State private var prompt: LibraryPrompt?
    @State private var promptText = ""
    @State private var showPrompt = false
    @State private var movingNote: IDBox?
    @State private var deletingNote: IDBox?
    @State private var deletingFolder: IDBox?
    @State private var showImporter = false
    @State private var importError: String?

    // MARK: Data

    private var currentFolderID: UUID? {
        if case .folder(let id) = scope { return id }
        return nil
    }

    private var title: String {
        switch scope {
        case .home, .notes: return "Notes"
        case .favourites: return "Favourites"
        case .folder(let id): return store.folders.first { $0.id == id }?.name ?? "Folder"
        }
    }

    private var searching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .edited }

    private func sorted(_ list: [Note]) -> [Note] {
        switch sort {
        case .edited: return list.sorted { $0.modifiedAt > $1.modifiedAt }
        case .created: return list.sorted { $0.createdAt > $1.createdAt }
        case .name: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private var visibleFolders: [Folder] {
        if searching { return [] }
        switch scope {
        case .home, .notes: return store.subfolders(of: nil)
        case .favourites: return []
        case .folder(let id): return store.subfolders(of: id)
        }
    }

    private var visibleNotes: [Note] {
        if searching {
            return sorted(store.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) })
        }
        switch scope {
        case .home, .notes: return sorted(store.notesInFolder(nil))
        case .favourites: return sorted(store.notes.filter(\.isFavorite))
        case .folder(let id): return sorted(store.notesInFolder(id))
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !visibleFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        header("Folders")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                            ForEach(visibleFolders) { folderCard($0) }
                        }
                    }
                }

                if !visibleNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        header(searching ? "Results" : "Notes")
                        if viewMode == "grid" {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 18)], spacing: 22) {
                                ForEach(visibleNotes) { gridCard($0) }
                            }
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleNotes) { note in
                                    listRow(note)
                                    Divider()
                                }
                            }
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }

                if visibleFolders.isEmpty && visibleNotes.isEmpty {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(searching ? "Search" : title)
        .toolbar { toolbarContent }
        .alert(promptTitle, isPresented: $showPrompt) {
            TextField("Name", text: $promptText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitPrompt() }
        }
        .sheet(item: $movingNote) { MoveNoteSheet(noteID: $0.id) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                do {
                    let note = try store.importPDF(from: url, into: currentFolderID)
                    Haptics.success()
                    path.append(note.id)
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Couldn't import PDF",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
        .confirmationDialog("Delete this note?",
                            isPresented: Binding(get: { deletingNote != nil },
                                                 set: { if !$0 { deletingNote = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingNote) { box in
            Button("Delete Note", role: .destructive) {
                Haptics.warning()
                store.deleteNote(box.id)
            }
        } message: { _ in Text("This can't be undone.") }
        .confirmationDialog("Delete this folder?",
                            isPresented: Binding(get: { deletingFolder != nil },
                                                 set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingFolder) { box in
            Button("Delete Folder", role: .destructive) {
                Haptics.warning()
                if selection == .folder(box.id) { selection = .home }
                store.deleteFolder(box.id)
            }
        } message: { _ in Text("Notes inside move up one level. Nothing else is deleted.") }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("View as", selection: $viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    Label("List", systemImage: "list.bullet").tag("list")
                }
            } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            .accessibilityLabel("Sort and view")

            Menu {
                Button {
                    let note = store.addNote(in: currentFolderID)
                    Haptics.tap()
                    path.append(note.id)
                } label: { Label("New Note", systemImage: "square.and.pencil") }
                if scope != .favourites {
                    Button { ask(.newFolder(parent: currentFolderID)) } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
                Button { showImporter = true } label: {
                    Label("Import PDF…", systemImage: "doc.richtext")
                }
            } label: { Image(systemName: "plus") }
            .accessibilityLabel("New")
        }
    }

    // MARK: Pieces

    private func header(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        Group {
            if scope == .favourites {
                ContentUnavailableView("No Favourites", systemImage: "star",
                                       description: Text("Touch and hold a note, then choose Favourite."))
            } else if searching {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView("Nothing Here Yet", systemImage: "pencil.and.scribble",
                                       description: Text("Tap the pencil button to start a note."))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func gridCard(_ note: Note) -> some View {
        NavigationLink(value: note.id) {
            VStack(alignment: .leading, spacing: 8) {
                NoteThumbnail(note: note)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .overlay(alignment: .topTrailing) {
                        if note.isFavorite {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).padding(6)
                        }
                    }
                    .softShadow(radius: 5, y: 2)
                Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(note.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .noteTransitionSource(note.id)
        .contextMenu { noteMenu(note) }
    }

    private func listRow(_ note: Note) -> some View {
        NavigationLink(value: note.id) {
            HStack(spacing: 14) {
                NoteThumbnail(note: note)
                    .frame(width: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title).font(.body.weight(.medium)).lineLimit(1)
                    Text("\(note.pages.count) page\(note.pages.count == 1 ? "" : "s") · "
                         + note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if note.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noteTransitionSource(note.id)
        .contextMenu { noteMenu(note) }
    }

    private func folderCard(_ folder: Folder) -> some View {
        let noteCount = store.notesInFolder(folder.id).count
        let folderCount = store.subfolders(of: folder.id).count
        return Button {
            Haptics.tap()
            selection = .folder(folder.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(folder.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(noteCount) note\(noteCount == 1 ? "" : "s")"
                         + (folderCount > 0 ? " · \(folderCount) folder\(folderCount == 1 ? "" : "s")" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { ask(.renameFolder(folder.id), text: folder.name) } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { ask(.newFolder(parent: folder.id)) } label: {
                Label("New Folder Inside", systemImage: "folder.badge.plus")
            }
            Menu {
                ForEach(AccentOption.allCases) { option in
                    Button(option.rawValue.capitalized) {
                        store.setFolderColor(folder.id, to: option.rawValue)
                    }
                }
            } label: { Label("Colour", systemImage: "paintpalette") }
            Divider()
            Button(role: .destructive) { deletingFolder = IDBox(id: folder.id) } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func noteMenu(_ note: Note) -> some View {
        Button {
            store.toggleFavourite(note.id)
            Haptics.tap()
        } label: {
            Label(note.isFavorite ? "Remove Favourite" : "Favourite",
                  systemImage: note.isFavorite ? "star.slash" : "star")
        }
        Button { ask(.renameNote(note.id), text: note.title) } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            if store.duplicate(note.id) != nil { Haptics.success() }
        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { movingNote = IDBox(id: note.id) } label: {
            Label("Move…", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) { deletingNote = IDBox(id: note.id) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Name prompts

    private var promptTitle: String {
        guard let prompt else { return "" }
        switch prompt {
        case .newFolder: return "New Folder"
        case .renameNote: return "Rename Note"
        case .renameFolder: return "Rename Folder"
        }
    }

    private func ask(_ newPrompt: LibraryPrompt, text: String = "") {
        prompt = newPrompt
        promptText = text
        showPrompt = true
    }

    private func commitPrompt() {
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prompt, !name.isEmpty else { return }
        switch prompt {
        case .newFolder(let parent):
            store.addFolder(name: name, parentID: parent)
            Haptics.success()
        case .renameNote(let id):
            store.renameNote(id, to: name)
        case .renameFolder(let id):
            store.renameFolder(id, to: name)
        }
    }
}

/// Lets you pick a folder to move a note into.
struct MoveNoteSheet: View {
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    var body: some View {
        NavigationStack {
            List {
                Button { move(to: nil) } label: { Label("Home", systemImage: "house") }
                ForEach(store.flattenedFolders(), id: \.folder.id) { item in
                    Button { move(to: item.folder.id) } label: {
                        Label {
                            Text(item.folder.name)
                        } icon: {
                            Image(systemName: "folder.fill").foregroundStyle(item.folder.color)
                        }
                        .padding(.leading, CGFloat(item.depth) * 20)
                    }
                }
            }
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(to folder: UUID?) {
        store.move(noteID, to: folder)
        Haptics.success()
        dismiss()
    }
}
