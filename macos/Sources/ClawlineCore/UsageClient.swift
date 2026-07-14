import Foundation
import Security

public struct UsageClient: Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let output = try await ClaudeUsageCommand.run()
        do {
            return try ClaudeUsageParser.snapshot(from: output)
        } catch UsageError.usageOutputInvalid {
            // Claude Code 2.1.83 and earlier do not support `/usage` in print
            // mode. Read the current credential only for this compatibility
            // path; modern Claude Code versions never take this branch.
            return try await OAuthUsageClient.fetch()
        }
    }
}

enum OAuthUsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async throws -> UsageSnapshot {
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
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 401 || http.statusCode == 403
                ? UsageError.unauthorized
                : UsageError.server(http.statusCode)
        }
        return try JSONDecoder().decode(UsageAPIResponse.self, from: data).snapshot()
    }
}

enum CredentialReader {
    static func readAccessToken() throws -> String {
        if let keychainData = try readKeychainCredential() {
            return try accessToken(from: keychainData)
        }

        let url = credentialsURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageError.credentialsMissing
        }
        return try accessToken(from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    private static func credentialsURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let directory = environment["CLAUDE_CONFIG_DIR"], !directory.isEmpty {
            return URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(".credentials.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json")
    }

    private static func accessToken(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.credentialsInvalid
        }
        let oauth = root["claudeAiOauth"] as? [String: Any]
        let token = (oauth?["accessToken"] as? String) ?? (root["accessToken"] as? String)
        guard let token, !token.isEmpty else { throw UsageError.credentialsInvalid }
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
            guard let data = result as? Data else { throw UsageError.credentialsInvalid }
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

enum ClaudeUsageCommand {
    private static let candidates = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path,
    ]

    static func run() async throws -> String {
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw UsageError.claudeNotInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                let error = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = ["-p", "--no-session-persistence", "/usage"]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = output
                process.standardError = error

                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdout = output.fileHandleForReading.readDataToEndOfFile()
                    let stderr = error.fileHandleForReading.readDataToEndOfFile()

                    guard process.terminationStatus == 0 else {
                        let message = String(decoding: stderr, as: UTF8.self)
                        continuation.resume(throwing: UsageError.claudeCommandFailed(message))
                        return
                    }

                    continuation.resume(returning: String(decoding: stdout, as: UTF8.self))
                } catch {
                    continuation.resume(throwing: UsageError.claudeCommandFailed(error.localizedDescription))
                }
            }
        }
    }
}

public enum ClaudeUsageParser {
    public static func snapshot(from report: String, now: Date = Date()) throws -> UsageSnapshot {
        guard let fiveHour = window(prefix: "Current session:", in: report, now: now),
              let sevenDay = window(prefix: "Current week (all models):", in: report, now: now) else {
            throw UsageError.usageOutputInvalid
        }

        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, capturedAt: now)
    }

    private static func window(prefix: String, in report: String, now: Date) -> UsageWindow? {
        guard let line = report.split(whereSeparator: \.isNewline).first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }), let percentage = percentage(in: String(line)) else {
            return nil
        }

        return UsageWindow(utilization: percentage, resetsAt: resetDate(in: String(line), now: now))
    }

    private static func percentage(in line: String) -> Double? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let remainder = line[line.index(after: colon)...]
        guard let percent = remainder.firstIndex(of: "%") else { return nil }
        return Double(remainder[..<percent].trimmingCharacters(in: .whitespaces))
    }

    private static func resetDate(in line: String, now: Date) -> Date? {
        guard let resetRange = line.range(of: "resets ") else { return nil }
        let afterReset = line[resetRange.upperBound...]
        let value = afterReset.split(separator: "(", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let formats = ["MMM d, h:mma", "MMM d, ha"]
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)

        for candidateYear in [year, year + 1] {
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = "yyyy " + format
                guard let date = formatter.date(from: "\(candidateYear) \(value)") else { continue }
                if date >= now.addingTimeInterval(-24 * 60 * 60) {
                    return date
                }
            }
        }
        return nil
    }
}

public struct UsageAPIResponse: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let utilization: Double?
        public let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    public func snapshot(capturedAt: Date = Date()) throws -> UsageSnapshot {
        guard let fiveHour, let sevenDay,
              let fiveHourValue = fiveHour.utilization,
              let sevenDayValue = sevenDay.utilization else {
            throw UsageError.invalidResponse
        }

        return UsageSnapshot(
            fiveHour: UsageWindow(
                utilization: fiveHourValue,
                resetsAt: Self.parseDate(fiveHour.resetsAt)
            ),
            sevenDay: UsageWindow(
                utilization: sevenDayValue,
                resetsAt: Self.parseDate(sevenDay.resetsAt)
            ),
            capturedAt: capturedAt
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
