import SwiftUI

enum SidebarItem: Hashable {
    case home
    case favourites
    case folder(UUID)
}

/// Sidebar + content, the way native iPad apps are laid out.
struct HomeView: View {
    @EnvironmentObject var store: NoteStore
    @State private var selection: SidebarItem? = .home
    @State private var path = NavigationPath()
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Home", systemImage: "house").tag(SidebarItem.home)
                    Label("Favourites", systemImage: "star").tag(SidebarItem.favourites)
                }
                Section("Folders") {
                    OutlineGroup(store.folderTree(), children: \.children) { node in
                        Label {
                            Text(node.folder.name)
                        } icon: {
                            Image(systemName: "folder.fill").foregroundStyle(node.folder.color)
                        }
                        .tag(SidebarItem.folder(node.id))
                    }
                }
            }
            .navigationTitle("Free Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
        } detail: {
            NavigationStack(path: $path) {
                LibraryView(scope: selection ?? .home, selection: $selection, path: $path)
                    .navigationDestination(for: UUID.self) { NoteEditorView(noteID: $0) }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
