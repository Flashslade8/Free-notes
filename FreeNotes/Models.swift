import SwiftUI
import PencilKit

enum PageTemplate: String, Codable, CaseIterable, Identifiable {
    case blank = "Blank", lined = "Lined", grid = "Grid"
    var id: String { rawValue }
}

/// Logical page size (US Letter in points). Used by the editor and the PDF exporter.
enum PageMetrics {
    static let size = CGSize(width: 612, height: 792)
    static let spacing: CGFloat = 24
}

struct NotePage: Identifiable, Codable {
    var id = UUID()
    var drawingData = Data()
    var template: PageTemplate = .lined
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var title = "Untitled Note"
    var createdAt = Date()
    var modifiedAt = Date()
    var pages: [NotePage] = [NotePage()]

    var thumbnail: UIImage? {
        guard let data = pages.first?.drawingData,
              let drawing = try? PKDrawing(data: data) else { return nil }
        let rect = CGRect(origin: .zero, size: PageMetrics.size)
        return drawing.image(from: rect, scale: 0.4)
    }
}

/// Persists notes as JSON in the app's Documents directory.
@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = [] {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    /// Each account gets its own file. "guest" keeps using the original notes.json.
    init(userID: String = "guest") {
        let name = userID == "guest" ? "notes.json" : "notes-\(userID).json"
        fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        load()
    }

    func addNote() -> Note {
        let note = Note()
        notes.insert(note, at: 0)
        return note
    }

    func delete(at offsets: IndexSet, from visible: [Note]) {
        let ids = offsets.map { visible[$0].id }
        notes.removeAll { ids.contains($0.id) }
    }

    func touch(_ id: UUID) {
        if let i = notes.firstIndex(where: { $0.id == id }) {
            notes[i].modifiedAt = Date()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
    }

    /// Debounced so we don't write to disk on every pen stroke.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [notes, fileURL] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(notes) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
