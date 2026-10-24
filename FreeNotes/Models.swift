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

struct NotePage: Identifiable, Codable, Equatable {
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

/// Remembers that a note was deleted, so syncing doesn't bring it back.
struct Tombstone: Codable {
    var id: UUID
    var date: Date
}

/// What is saved on disk, and what is stored in Google Drive.
struct StoreFile: Codable {
    var notes: [Note]
    var deleted: [Tombstone]
}

/// Keeps notes on disk and, for Google accounts, syncs them through Google Drive.
@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = [] {
        didSet { notesDidChange(from: oldValue) }
    }
    @Published private(set) var syncStatus = ""

    let syncEnabled: Bool

    private var tombstones: [Tombstone] = []
    private var applyingExternalChange = false
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false

    /// Each account gets its own file. "guest" keeps using the original notes.json.
    init(userID: String = "guest", syncEnabled: Bool = false) {
        self.syncEnabled = syncEnabled
        let name = userID == "guest" ? "notes.json" : "notes-\(userID).json"
        fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        load()
    }

    // MARK: - Editing

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

    /// Runs after every change: records deletions, stamps edited notes, then saves and syncs.
    private func notesDidChange(from old: [Note]) {
        guard !applyingExternalChange else { return }

        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIDs = Set(notes.map(\.id))

        for id in oldByID.keys where !newIDs.contains(id) {
            tombstones.append(Tombstone(id: id, date: Date()))
        }

        var updated = notes
        var stamped = false
        for i in updated.indices {
            if let before = oldByID[updated[i].id],
               before.title != updated[i].title || before.pages != updated[i].pages {
                updated[i].modifiedAt = Date()
                stamped = true
            }
        }
        if stamped {
            applyingExternalChange = true
            notes = updated
            applyingExternalChange = false
        }

        scheduleSave()
        scheduleSync()
    }

    // MARK: - Saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        applyingExternalChange = true
        defer { applyingExternalChange = false }
        if let file = try? decoder.decode(StoreFile.self, from: data) {
            notes = file.notes
            tombstones = file.deleted
        } else if let legacy = try? decoder.decode([Note].self, from: data) {
            notes = legacy    // older versions saved a plain list of notes
        }
    }

    /// Debounced so we don't write to disk on every pen stroke.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            let file = StoreFile(notes: self.notes, deleted: self.tombstones)
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }

    // MARK: - Google Drive sync

    private func scheduleSync() {
        guard syncEnabled else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Downloads the copy in Google Drive, merges it with this device, and uploads the result.
    func syncNow() async {
        guard syncEnabled, !isSyncing else { return }
        isSyncing = true
        syncStatus = "Syncing…"
        defer { isSyncing = false }

        do {
            let token = try await DriveClient.accessToken()
            let fileID = try await DriveClient.findFile(token: token)

            var remote = StoreFile(notes: [], deleted: [])
            if let fileID {
                let data = try await DriveClient.download(fileID: fileID, token: token)
                remote = try JSONDecoder().decode(StoreFile.self, from: data)
            }

            // Merge using the notes as they are *now*, with no waiting in between,
            // so edits made while downloading are never lost.
            let local = StoreFile(notes: notes, deleted: tombstones)
            let merged = Self.merge(local, remote)

            if !Self.sameContent(merged, local) {
                applyingExternalChange = true
                notes = merged.notes
                tombstones = merged.deleted
                applyingExternalChange = false
                scheduleSave()
            }

            if fileID == nil || !Self.sameContent(merged, remote) {
                let body = try JSONEncoder().encode(merged)
                try await DriveClient.uploadSyncFile(body, fileID: fileID, token: token)
            }

            // Keep a readable PDF copy of every note in the visible "Free Notes" folder.
            // A problem here shouldn't stop the main sync from counting as done.
            var folderNote = ""
            do {
                try await syncPDFCopies(merged, token: token)
            } catch {
                folderNote = " (Drive folder: " + error.localizedDescription + ")"
            }
            syncStatus = "Synced " + Date().formatted(date: .omitted, time: .shortened) + folderNote
        } catch {
            syncStatus = "Sync failed: " + error.localizedDescription
        }
    }

    /// Uploads a PDF for every new or changed note, and removes the PDF of deleted notes.
    private func syncPDFCopies(_ merged: StoreFile, token: String) async throws {
        guard DriveClient.hasScope(DriveClient.fileScope) else {
            throw SyncError.missingFolderPermission
        }
        let folderID = try await DriveClient.findOrCreateFolder(token: token)
        let existing = try await DriveClient.listPDFs(folderID: folderID, token: token)

        var byNote: [String: DriveClient.RemotePDF] = [:]
        for pdf in existing {
            if let id = pdf.noteID { byNote[id] = pdf }
        }

        for note in merged.notes {
            let stamp = String(Int(note.modifiedAt.timeIntervalSince1970 * 1000))
            let current = byNote[note.id.uuidString]
            if current?.stamp == stamp { continue }          // already up to date

            guard let url = PDFExporter.export(note),
                  let data = try? Data(contentsOf: url) else { continue }
            try? FileManager.default.removeItem(at: url)

            var metadata: [String: Any] = [
                "name": DriveClient.pdfName(for: note.title),
                "appProperties": ["noteID": note.id.uuidString, "stamp": stamp]
            ]
            if current == nil { metadata["parents"] = [folderID] }
            try await DriveClient.upload(data, mimeType: "application/pdf", metadata: metadata,
                                         fileID: current?.id, token: token)
        }

        let liveIDs = Set(merged.notes.map { $0.id.uuidString })
        for gone in merged.deleted {
            let id = gone.id.uuidString
            if !liveIDs.contains(id), let pdf = byNote[id] {
                try await DriveClient.trash(fileID: pdf.id, token: token)
            }
        }
    }

    /// For each note the newest copy wins. A deletion wins unless the note was edited afterwards.
    private static func merge(_ a: StoreFile, _ b: StoreFile) -> StoreFile {
        var deletedAt: [UUID: Date] = [:]
        for t in a.deleted + b.deleted {
            deletedAt[t.id] = max(deletedAt[t.id] ?? .distantPast, t.date)
        }

        var newest: [UUID: Note] = [:]
        for n in a.notes + b.notes {
            if let existing = newest[n.id], existing.modifiedAt >= n.modifiedAt { continue }
            newest[n.id] = n
        }

        let kept = newest.values.filter { note in
            guard let d = deletedAt[note.id] else { return true }
            return d < note.modifiedAt
        }

        let cutoff = Date().addingTimeInterval(-60 * 24 * 3600)   // forget deletions after 60 days
        let tombs = deletedAt.filter { $0.value > cutoff }.map { Tombstone(id: $0.key, date: $0.value) }
        return StoreFile(notes: Array(kept), deleted: tombs)
    }

    private static func sameContent(_ a: StoreFile, _ b: StoreFile) -> Bool {
        guard a.notes.count == b.notes.count else { return false }
        let bTimes = Dictionary(b.notes.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: { x, _ in x })
        for n in a.notes where bTimes[n.id] != n.modifiedAt { return false }
        return Set(a.deleted.map(\.id)) == Set(b.deleted.map(\.id))
    }
}
