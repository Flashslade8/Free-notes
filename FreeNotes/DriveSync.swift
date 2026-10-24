import Foundation
import GoogleSignIn

enum SyncError: LocalizedError {
    case notSignedIn
    case missingPermission
    case missingFolderPermission
    case badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in with Google."
        case .missingPermission:
            return "Google Drive permission is missing. Sign out, then sign in again and allow access."
        case .missingFolderPermission:
            return "The Free Notes folder needs permission. Sign out, then sign in again and allow access."
        case .badResponse:
            return "Google sent a response the app couldn't read."
        case .http(let code, let body):
            if body.contains("accessNotConfigured") || body.contains("has not been used") {
                return "The Google Drive API isn't enabled in your Google Cloud project."
            }
            return "Google Drive returned error \(code)."
        }
    }
}

/// Talks to Google Drive.
/// - A hidden app-only file keeps the editable notes in sync between devices.
/// - A visible "Free Notes" folder holds a PDF copy of every note.
enum DriveClient {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"      // hidden sync file
    static let fileScope = "https://www.googleapis.com/auth/drive.file"      // visible folder + PDFs
    private static let fileName = "freenotes-sync.json"
    private static let folderName = "Free Notes"

    struct RemotePDF {
        let id: String
        let noteID: String?
        let stamp: String?
    }

    private struct FileList: Decodable {
        struct Item: Decodable {
            let id: String
            let appProperties: [String: String]?
        }
        let files: [Item]
    }

    // MARK: Auth

    static func accessToken() async throws -> String {
        var user = GIDSignIn.sharedInstance.currentUser
        if user == nil {
            user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
        }
        guard let user else { throw SyncError.notSignedIn }
        if let granted = user.grantedScopes, !granted.contains(scope) {
            throw SyncError.missingPermission
        }
        let fresh = try await user.refreshTokensIfNeeded()
        return fresh.accessToken.tokenString
    }

    static func hasScope(_ wanted: String) -> Bool {
        GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(wanted) ?? false
    }

    // MARK: Hidden sync file

    static func findFile(token: String) async throws -> String? {
        let items = try await list(query: "name = '\(fileName)' and trashed = false",
                                   fields: "files(id)", space: "appDataFolder", pageSize: 10, token: token)
        return items.first?.id
    }

    static func download(fileID: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request).0
    }

    static func uploadSyncFile(_ body: Data, fileID: String?, token: String) async throws {
        let metadata: [String: Any] = fileID == nil ? ["name": fileName, "parents": ["appDataFolder"]] : [:]
        try await upload(body, mimeType: "application/json", metadata: metadata, fileID: fileID, token: token)
    }

    // MARK: Visible folder with PDF copies

    static func findOrCreateFolder(token: String) async throws -> String {
        let found = try await list(
            query: "name = '\(folderName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
            fields: "files(id)", space: nil, pageSize: 10, token: token)
        if let first = found.first { return first.id }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])
        let (data, _) = try await send(request)
        struct Created: Decodable { let id: String }
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    static func listPDFs(folderID: String, token: String) async throws -> [RemotePDF] {
        let items = try await list(
            query: "'\(folderID)' in parents and mimeType = 'application/pdf' and trashed = false",
            fields: "files(id,appProperties)", space: nil, pageSize: 1000, token: token)
        return items.map {
            RemotePDF(id: $0.id, noteID: $0.appProperties?["noteID"], stamp: $0.appProperties?["stamp"])
        }
    }

    static func trash(fileID: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"trashed\":true}".utf8)
        _ = try await send(request)
    }

    /// A readable file name for a note, e.g. "Maths homework.pdf".
    static func pdfName(for title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Untitled Note" : cleaned) + ".pdf"
    }

    // MARK: Shared helpers

    private static func list(query: String, fields: String, space: String?,
                             pageSize: Int, token: String) async throws -> [FileList.Item] {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        if let space { items.append(URLQueryItem(name: "spaces", value: space)) }
        comps.queryItems = items
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await send(request)
        return try JSONDecoder().decode(FileList.self, from: data).files
    }

    /// Creates a file (fileID == nil) or replaces an existing one.
    /// Uses Google's "resumable" upload, which has no small size limit.
    static func upload(_ body: Data, mimeType: String, metadata: [String: Any],
                       fileID: String?, token: String) async throws {
        var start: URLRequest
        if let fileID {
            start = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=resumable")!)
            start.httpMethod = "PATCH"
        } else {
            start = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!)
            start.httpMethod = "POST"
        }
        start.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        start.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")

        let (_, response) = try await send(start)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else { throw SyncError.badResponse }

        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.httpBody = body
        put.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        _ = try await send(put)
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }
}
