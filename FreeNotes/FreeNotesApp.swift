import SwiftUI

@main
struct FreeNotesApp: App {
    @StateObject private var store = NoteStore()

    var body: some Scene {
        WindowGroup {
            NoteListView()
                .environmentObject(store)
        }
    }
}

