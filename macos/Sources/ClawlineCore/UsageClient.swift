import Foundation

public struct UsageClient: Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let report = try await ClaudeUsageCommand.run()
        return try ClaudeUsageParser.snapshot(from: report)
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
