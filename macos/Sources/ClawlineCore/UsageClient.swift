import Foundation
import Security

public enum CredentialReader {
    public static func credentialsURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let customDirectory = environment["CLAUDE_CONFIG_DIR"], !customDirectory.isEmpty {
            return URL(fileURLWithPath: customDirectory, isDirectory: true)
                .appendingPathComponent(".credentials.json")
        }

        return homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json")
    }

    public static func readAccessToken() throws -> String {
        let url = credentialsURL()

        if let keychainData = try readKeychainCredential() {
            return try accessToken(from: keychainData)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageError.credentialsMissing
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try accessToken(from: data)
    }

    public static func accessToken(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.credentialsInvalid
        }

        let oauth = root["claudeAiOauth"] as? [String: Any]
        let token = (oauth?["accessToken"] as? String)
            ?? (root["accessToken"] as? String)

        guard let token, !token.isEmpty else {
            throw UsageError.credentialsInvalid
        }

        return token
    }

    private static func readKeychainCredential() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw UsageError.credentialsInvalid
            }
            return data
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw UsageError.keychainAccessDenied
        default:
            throw UsageError.keychain(status)
        }
    }
}

public struct UsageClient: Sendable {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let token = try CredentialReader.readAccessToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            let payload = try JSONDecoder().decode(UsageAPIResponse.self, from: data)
            return try payload.snapshot()
        case 401, 403:
            throw UsageError.unauthorized
        default:
            throw UsageError.server(http.statusCode)
        }
    }
}

public enum SnapshotCache {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawline", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    public static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public static func save(_ snapshot: UsageSnapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The cache contains convenience data only. Polling continues if it cannot be saved.
        }
    }
}
