import SwiftUI

enum SidebarItem: Hashable {
    case home
    case notes
    case favourites
    case folder(UUID)
}

/// Sidebar + content, the way native iPad apps are laid out.
struct HomeView: View {
    @EnvironmentObject var store: NoteStore
    @State private var selection: SidebarItem? = .home
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    private var searching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: UUID.self) { NoteEditorView(noteID: $0) }
            }
        }
        .onChange(of: selection) { _, _ in path = NavigationPath() }   // leave an open note
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    store.addFolder(name: name, parentID: nil)
                    Haptics.success()
                }
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Label("Home", systemImage: "house").tag(SidebarItem.home)
            Label("Notes", systemImage: "note.text").tag(SidebarItem.notes)
            Label("Favourites", systemImage: "star").tag(SidebarItem.favourites)

            HStack {
                Text("Folders")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Image(systemName: "plus").font(.body.weight(.medium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("New folder")
            }
            .padding(.top, 18)

            OutlineGroup(store.folderTree(), children: \.children) { node in
                HStack(spacing: 12) {
                    Circle().fill(node.folder.color).frame(width: 14, height: 14)
                    Text(node.folder.name)
                }
                .tag(SidebarItem.folder(node.id))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { searchField }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var detailRoot: some View {
        if searching {
            LibraryView(scope: .notes, selection: $selection, path: $path, searchText: search)
        } else if (selection ?? .home) == .home {
            DashboardView(selection: $selection, path: $path)
        } else {
            LibraryView(scope: selection ?? .notes, selection: $selection, path: $path, searchText: "")
        }
    }
}
