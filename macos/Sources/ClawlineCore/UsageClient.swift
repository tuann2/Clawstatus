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

    public func fetch(appVersion: String = "0.4.0") async throws -> CodexUsageSnapshot {
        let response = try await CodexUsageCommand.run(appVersion: appVersion)
        return try CodexUsageParser.snapshot(from: response)
    }
}

private final class CodexProcessState: @unchecked Sendable {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    let continuation: CheckedContinuation<String, Error>
    private let lock = NSLock()
    private var completed = false
    private var buffer = Data()

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }
        continuation.resume(with: result)
    }

    private func sendUnlocked(_ request: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: request)
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data("\n".utf8))
    }

    private func sendIfActive(_ requests: [[String: Any]]) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { throw CancellationError() }
        for request in requests {
            try sendUnlocked(request)
        }
    }

    func start(executable: String, appVersion: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { throw CancellationError() }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        try sendUnlocked([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "clawstatus", "version": appVersion],
                "capabilities": ["experimentalApi": true],
            ],
        ])
    }

    func handleOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines = buffer.split(separator: 10, omittingEmptySubsequences: true)
        buffer = buffer.last == 10 ? Data() : Data(lines.popLast().map(Array.init) ?? [])
        lock.unlock()
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            if object["error"] != nil {
                finish(.failure(UsageError.codexCommandFailed("Codex app-server returned an error")))
                return
            }
            if id == 1, object["result"] != nil {
                do {
                    try sendIfActive([
                        ["method": "initialized"],
                        ["id": 2, "method": "account/rateLimits/read", "params": NSNull()],
                    ])
                } catch { finish(.failure(UsageError.codexCommandFailed(error.localizedDescription))) }
            } else if id == 2 {
                guard object["result"] != nil,
                      let text = String(data: Data(line), encoding: .utf8) else {
                    finish(.failure(UsageError.codexOutputInvalid)); return
                }
                finish(.success(text))
            }
        }
    }
}

private final class CodexProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: CodexProcessState?
    private var cancelled = false

    func install(_ state: CodexProcessState) -> Bool {
        lock.lock()
        self.state = state
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { state.finish(.failure(CancellationError())) }
        return !shouldCancel
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let state = state
        lock.unlock()
        state?.finish(.failure(CancellationError()))
    }
}

enum CodexUsageCommand {
    private static let candidates = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
    ]

    static func run(appVersion: String) async throws -> String {
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw UsageError.codexNotInstalled
        }

        let box = CodexProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let state = CodexProcessState(continuation)
                    guard box.install(state) else { return }
                    state.output.fileHandleForReading.readabilityHandler = { state.handleOutput($0.availableData) }
                    // Consume stderr as the server runs; leaving this pipe unread can deadlock a child process.
                    state.error.fileHandleForReading.readabilityHandler = { handle in
                        _ = handle.availableData
                    }

                    do {
                        try state.start(executable: executable, appVersion: appVersion)
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12) {
                            state.finish(.failure(UsageError.codexCommandFailed("Timed out waiting for Codex CLI")))
                        }
                    } catch {
                        state.finish(.failure(UsageError.codexCommandFailed(error.localizedDescription)))
                    }
                }
            }
        } onCancel: {
            box.cancel()
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
                process.arguments = [
                    "-p",
                    "--no-session-persistence",
                    "--tools", "",
                    "--strict-mcp-config",
                    "--mcp-config", #"{"mcpServers":{}}"#,
                    "--setting-sources", "",
                    "/usage",
                ]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = output
                process.standardError = error

                do {
                    let runtimeDirectory = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    )[0]
                        .appendingPathComponent("Clawstatus", isDirectory: true)
                        .appendingPathComponent("Runtime", isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: runtimeDirectory,
                        withIntermediateDirectories: true
                    )
                    process.currentDirectoryURL = runtimeDirectory
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
        }), let percentage = percentage(in: String(line)),
              let reset = resetDate(in: String(line), now: now) else {
            return nil
        }

        return UsageWindow(utilization: percentage, resetsAt: reset)
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
        let rawValue = afterReset.split(separator: "(", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = rawValue.replacingOccurrences(of: " at ", with: ", ")

        let formats = ["MMM d, h:mma", "MMM d, ha"]
        let year = Calendar.current.component(.year, from: now)

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
