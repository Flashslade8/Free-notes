import SwiftUI
import GoogleSignIn

@main
struct FreeNotesApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                // Lets Google Sign-In hand control back to the app after the browser step.
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

/// Shows the login screen until someone signs in (or continues as guest).
struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        if let user = auth.user {
            MainView(userID: user.id, syncEnabled: user.provider == .google)
                .id(user.id)        // fresh note store whenever the account changes
        } else {
            LoginView()
        }
    }
}

/// Creates the note store for the signed-in account and keeps it synced.
struct MainView: View {
    @StateObject private var store: NoteStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("accent") private var accentRaw = AccentOption.blue.rawValue

    init(userID: String, syncEnabled: Bool) {
        _store = StateObject(wrappedValue: NoteStore(userID: userID, syncEnabled: syncEnabled))
    }

    var body: some View {
        HomeView()
            .environmentObject(store)
            .tint((AccentOption(rawValue: accentRaw) ?? .blue).color)
            .task { await store.syncNow() }                       // when the app opens
            .onChange(of: scenePhase) { _, phase in               // when you come back to it
                if phase == .active { Task { await store.syncNow() } }
            }
    }
}
