import Foundation

public struct UsageClient: Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let report = try await ClaudeUsageCommand.run()
        return try ClaudeUsageParser.snapshot(from: report)
    }
}

public struct CodexUsageClient: Sendable {
    public init() {}

    public func fetch(appVersion: String = "unknown") async throws -> CodexUsageSnapshot {
        let response = try await CodexUsageCommand.run(appVersion: appVersion)
        return try CodexUsageParser.snapshot(from: response)
    }
}

enum CodexUsageCommand {
    private static let candidates = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
    ]

    static func run(appVersion: String) async throws -> String {
        guard let executable = CLIProcessRunner.firstExecutable(in: candidates) else {
            throw UsageError.codexNotInstalled
        }
        let initialize = try requestData([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "clawstatus", "version": appVersion],
                "capabilities": ["experimentalApi": true],
            ],
        ])
        let decoder = CodexStreamDecoder()
        do {
            let result = try await CLIProcessRunner.runStreaming(.init(
                executable: executable,
                arguments: ["app-server", "--stdio"],
                standardInput: initialize,
                timeout: 12
            )) { data, session in
                decoder.handle(data, session: session)
            }
            return String(decoding: result.stdout, as: UTF8.self)
        } catch CLIProcessRunner.RunnerError.timedOut {
            throw UsageError.codexCommandFailed("Timed out waiting for Codex CLI")
        } catch CLIProcessRunner.RunnerError.exited(let status) {
            throw UsageError.codexCommandFailed("Codex exited (status \(status))")
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.codexCommandFailed(error.localizedDescription)
        }
    }

    fileprivate static func requestData(_ request: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(10)
        return data
    }
}

private final class CodexStreamDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var initialized = false

    func handle(_ data: Data, session: CLIProcessRunner.Session) {
        lock.lock()
        buffer.append(data)
        var lines = buffer.split(separator: 10, omittingEmptySubsequences: true)
        buffer = buffer.last == 10 ? Data() : Data(lines.popLast().map(Array.init) ?? [])
        lock.unlock()

        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            if object["error"] != nil {
                session.fail(with: UsageError.codexCommandFailed("Codex app-server returned an error"))
                return
            }
            if id == 1, object["result"] != nil {
                lock.lock()
                let shouldSend = !initialized
                initialized = true
                lock.unlock()
                guard shouldSend else { continue }
                do {
                    let initialized = try CodexUsageCommand.requestData(["method": "initialized"])
                    let request = try CodexUsageCommand.requestData([
                        "id": 2,
                        "method": "account/rateLimits/read",
                        "params": NSNull(),
                    ])
                    session.send(initialized + request)
                } catch {
                    session.fail(with: UsageError.codexCommandFailed(error.localizedDescription))
                }
            } else if id == 2 {
                guard object["result"] != nil else {
                    session.fail(with: UsageError.codexOutputInvalid)
                    return
                }
                session.succeed(with: Data(line))
            }
        }
    }
}

public enum CodexUsageParser {
    public static func snapshot(from response: String, now: Date = Date()) throws -> CodexUsageSnapshot {
        guard let data = response.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = envelope["result"] as? [String: Any] else { throw UsageError.codexOutputInvalid }
        let limits = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
            ?? result["rateLimits"] as? [String: Any]
        guard let limits else { throw UsageError.codexOutputInvalid }
        let windows = [("primary", limits["primary"]), ("secondary", limits["secondary"])].compactMap { id, value -> CodexUsageWindow? in
            guard let value = value as? [String: Any], let used = value["usedPercent"] as? Int else { return nil }
            let duration = value["windowDurationMins"] as? Int
            let reset = (value["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                ?? (value["resetsAt"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return CodexUsageWindow(id: id, usedPercent: used, windowDurationMins: duration, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw UsageError.codexOutputInvalid }
        return CodexUsageSnapshot(windows: windows, planType: limits["planType"] as? String, capturedAt: now)
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
        guard let executable = CLIProcessRunner.firstExecutable(in: candidates) else {
            throw UsageError.claudeNotInstalled
        }
        let runtimeDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("Clawstatus", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            let inputTrigger = ClaudeInputTrigger()
            let result = try await CLIProcessRunner.runStreaming(.init(
                executable: executable,
                arguments: [
                    "-p",
                    "--safe-mode",
                    "/usage",
                ],
                currentDirectoryURL: runtimeDirectory,
                environmentOverrides: [
                    "CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1",
                    "NO_COLOR": "1",
                ],
                timeout: 30
            )) { _, session in
                inputTrigger.respondIfNeeded(session: session)
            }
            return String(decoding: result.stdout, as: UTF8.self)
        } catch CLIProcessRunner.RunnerError.timedOut {
            throw UsageError.claudeCommandFailed("Timed out")
        } catch CLIProcessRunner.RunnerError.exited(let status) {
            throw UsageError.claudeCommandFailed("Claude exited (status \(status))")
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.claudeCommandFailed(error.localizedDescription)
        }
    }
}

private final class ClaudeInputTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResponded = false

    func respondIfNeeded(session: CLIProcessRunner.Session) {
        lock.lock()
        guard !hasResponded else { lock.unlock(); return }
        hasResponded = true
        lock.unlock()
        session.send(Data([10]))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            session.closeStandardInput()
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

        return UsageWindow(
            utilization: percentage,
            resetsAt: resetDate(in: String(line), now: now)
        )
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
        let pieces = afterReset.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false)
        let rawValue = pieces.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeZone = pieces.count > 1
            ? TimeZone(identifier: String(pieces[1].prefix(while: { $0 != ")" }))) ?? .current
            : .current
        let value = rawValue.replacingOccurrences(of: " at ", with: ", ")

        let formats = ["MMM d, h:mma", "MMM d, ha"]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let year = calendar.component(.year, from: now)

        for candidateYear in [year, year + 1] {
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.timeZone = timeZone
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

public enum SnapshotCache {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawstatus", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    public static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public static func save(_ snapshot: UsageSnapshot) {
        save(snapshot, to: fileURL)
    }

    public static func loadCodex() -> CodexUsageSnapshot? {
        load(CodexUsageSnapshot.self, from: fileURL.deletingLastPathComponent().appendingPathComponent("codex-state.json"))
    }

    public static func saveCodex(_ snapshot: CodexUsageSnapshot) {
        save(snapshot, to: fileURL.deletingLastPathComponent().appendingPathComponent("codex-state.json"))
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ snapshot: T, to url: URL) {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // The cache contains convenience data only. Polling continues if it cannot be saved.
        }
    }
}
