import SwiftUI
import UniformTypeIdentifiers

/// The home screen: today's date, quick actions, and your latest notes.
struct DashboardView: View {
    @EnvironmentObject var store: NoteStore
    @Binding var selection: SidebarItem?
    @Binding var path: NavigationPath

    @State private var showImporter = false
    @State private var importError: String?
    @State private var showTemplates = false
    @State private var showNewFolder = false
    @State private var folderName = ""

    private var recents: [Note] {
        Array(store.notes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
    }

    private var favourites: [Note] {
        Array(store.notes.filter(\.isFavorite).sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 34) {
                hero
                quickActions
                VStack(alignment: .leading, spacing: 30) {
                    notesSection("Continue writing", notes: recents,
                                 emptyText: "Your notes will show up here. Tap New to start writing.")
                    if !favourites.isEmpty {
                        notesSection("Favourites", notes: favourites, emptyText: "")
                    }
                }
            }
            .frame(maxWidth: 960)
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { newMenu }
        }
        .sheet(isPresented: $showTemplates) {
            TemplatePickerSheet { template in
                let note = store.addNote(in: nil, template: template)
                Haptics.success()
                path.append(note.id)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                do {
                    let note = try store.importPDF(from: url, into: nil)
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
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    store.addFolder(name: name, parentID: nil)
                    Haptics.success()
                }
            }
        }
    }

    // MARK: Pieces

    private var hero: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)

            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
            ActionCard(title: "New note", symbol: "square.and.pencil", tint: .accentColor) {
                newNote()
            }
            ActionCard(title: "New folder", symbol: "folder.badge.plus", tint: .orange) {
                folderName = ""
                showNewFolder = true
            }
            ActionCard(title: "Import a PDF", symbol: "square.and.arrow.down", tint: .indigo) {
                showImporter = true
            }
            ActionCard(title: "Find a template", symbol: "doc.text.image", tint: .gray) {
                showTemplates = true
            }
        }
    }

    private var newMenu: some View {
        Menu {
            Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
            Button { folderName = ""; showNewFolder = true } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Button { showImporter = true } label: {
                Label("Import PDF…", systemImage: "square.and.arrow.down")
            }
            Button { showTemplates = true } label: {
                Label("Choose Template…", systemImage: "doc.text.image")
            }
        } label: {
            Label("New", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
        }
    }

    private func notesSection(_ title: String, notes: [Note], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Spacer()
                if !notes.isEmpty {
                    Button("See all") { selection = title == "Favourites" ? .favourites : .notes }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if notes.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(notes) { RecentCard(note: $0) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func newNote() {
        let note = store.addNote(in: nil)
        Haptics.tap()
        path.append(note.id)
    }
}

/// One of the big rounded tiles on the home screen.
private struct ActionCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 30))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct RecentCard: View {
    let note: Note

    var body: some View {
        NavigationLink(value: note.id) {
            VStack(alignment: .leading, spacing: 8) {
                NoteThumbnail(note: note)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160)
        }
        .buttonStyle(.plain)
    }
}
