import Foundation
import GoogleSignIn

enum SyncError: LocalizedError {
    case notSignedIn
    case missingPermission
    case badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in with Google."
        case .missingPermission:
            return "Google Drive permission is missing. Sign out, then sign in again and allow access."
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

/// Talks to Google Drive's hidden per-app storage ("appDataFolder").
/// Only this app can see these files, and they don't show up in the user's Drive.
enum DriveClient {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    private static let fileName = "freenotes-sync.json"

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

    // MARK: Files

    static func findFile(token: String) async throws -> String? {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name = '\(fileName)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "10")
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await send(request)

        struct Listing: Decodable {
            struct Item: Decodable { let id: String }
            let files: [Item]
        }
        return try JSONDecoder().decode(Listing.self, from: data).files.first?.id
    }

    static func download(fileID: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request).0
    }

    /// Creates the file (fileID == nil) or replaces its contents.
    /// Uses Google's "resumable" upload, which has no small size limit.
    static func upload(_ body: Data, fileID: String?, token: String) async throws {
        var start: URLRequest
        if let fileID {
            start = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=resumable")!)
            start.httpMethod = "PATCH"
            start.httpBody = Data("{}".utf8)
        } else {
            start = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!)
            start.httpMethod = "POST"
            start.httpBody = Data("{\"name\":\"\(fileName)\",\"parents\":[\"appDataFolder\"]}".utf8)
        }
        start.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "X-Upload-Content-Type")

        let (_, response) = try await send(start)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else { throw SyncError.badResponse }

        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.httpBody = body
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(put)
    }

    // MARK: Networking

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }
}
