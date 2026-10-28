import SwiftUI
import UIKit

/// Accent colours the user can choose; folders use the same palette.
enum AccentOption: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, green, teal
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        }
    }
}

extension Folder {
    var color: Color { AccentOption(rawValue: colorName)?.color ?? .blue }
}

/// Small physical taps for key actions.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Drawing a thumbnail is slow, so each one is made once and remembered.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for note: Note) -> UIImage? {
        let key = "\(note.id.uuidString)-\(note.modifiedAt.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = note.thumbnail else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct NoteThumbnail: View {
    let note: Note

    var body: some View {
        ZStack {
            Color.white
            if let image = ThumbnailCache.image(for: note) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "scribble").font(.title).foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(PageMetrics.size.width / PageMetrics.size.height, contentMode: .fit)
    }
}

struct AccountMenu: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var store: NoteStore

    var body: some View {
        Menu {
            if let user = auth.user {
                Text(user.name)
                if let email = user.email { Text(email) }
                if store.syncEnabled {
                    Text(store.syncStatus.isEmpty ? "Google Drive sync on" : store.syncStatus)
                    Button("Sync Now") { Task { await store.syncNow() } }
                }
                Divider()
                Button(user.provider == .guest ? "Sign In" : "Sign Out",
                       role: user.provider == .guest ? nil : .destructive) {
                    auth.signOut()
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
    }
}

struct SettingsView: View {
    @AppStorage("accent") private var accentRaw = AccentOption.blue.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Accent colour") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 16) {
                        ForEach(AccentOption.allCases) { option in
                            Circle()
                                .fill(option.color)
                                .frame(width: 38, height: 38)
                                .overlay {
                                    if accentRaw == option.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    accentRaw = option.rawValue
                                    Haptics.tap()
                                }
                                .accessibilityLabel(option.rawValue.capitalized)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Storage") {
                    Text("Notes are saved on this device. When you're signed in with Google, they also sync through your Google Drive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
