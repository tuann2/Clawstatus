import ClawlineCore
import Foundation

enum CheckFailure: Error {
    case unexpected(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.unexpected(message) }
}

do {
    let report = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 32% used · resets Jul 14 at 3:29pm (Asia/Saigon)
    Current week (all models): 39% used · resets Jul 17 at 10am (Asia/Saigon)
    Current week (Fable): 54% used · resets Jul 17 at 10am (Asia/Saigon)
    """
    let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 7, day: 14, hour: 12
    ))!
    let snapshot = try ClaudeUsageParser.snapshot(from: report, now: now)
    try require(snapshot.fiveHour.utilization == 32, "5-hour usage was not decoded")
    try require(snapshot.sevenDay.utilization == 39, "7-day usage was not decoded")
    try require(snapshot.fiveHour.resetsAt != nil, "reset timestamp was not decoded")
    try require(snapshot.sevenDay.resetsAt != nil, "minuteless reset timestamp was not decoded")
    try require(UsageWindow(utilization: 120, resetsAt: nil).clampedUtilization == 100, "usage was not clamped")
    try require(snapshot.fiveHour.remainingPercentage == 68, "5-hour remaining usage was incorrect")
    try require(UsageWindow(utilization: 120, resetsAt: nil).remainingPercentage == 0, "remaining usage was not clamped")

    let commaReport = report.replacingOccurrences(of: " at ", with: ", ")
    let commaSnapshot = try ClaudeUsageParser.snapshot(from: commaReport, now: now)
    try require(commaSnapshot.fiveHour.resetsAt != nil, "comma reset timestamp was not decoded")

    let resetOmittedReport = """
    Current session: 0% used
    Current week (all models): 39% used · resets Jul 17 at 10am (Asia/Saigon)
    """
    let resetOmittedSnapshot = try ClaudeUsageParser.snapshot(from: resetOmittedReport, now: now)
    try require(
        resetOmittedSnapshot.fiveHour.utilization == 0
            && resetOmittedSnapshot.fiveHour.resetsAt == nil,
        "Claude usage without a session reset was not decoded"
    )

    let timezoneNow = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!
    let timezoneReport = """
    Current session: 1% used · resets Jul 14 at 3:29pm (Pacific/Honolulu)
    Current week (all models): 2% used · resets Jul 17 at 10am (Pacific/Honolulu)
    """
    let timezoneSnapshot = try ClaudeUsageParser.snapshot(from: timezoneReport, now: timezoneNow)
    let expectedHonoluluReset = ISO8601DateFormatter().date(from: "2026-07-15T01:29:00Z")!
    try require(
        timezoneSnapshot.fiveHour.resetsAt == expectedHonoluluReset,
        "reset timestamp ignored the report timezone"
    )

    let recencyNow = Date(timeIntervalSince1970: 10_000)
    try require(
        UsageTimestampFormatter.updatedText(capturedAt: recencyNow, now: recencyNow) == "Updated now",
        "current timestamp was not formatted as now"
    )
    try require(
        UsageTimestampFormatter.updatedText(
            capturedAt: recencyNow.addingTimeInterval(-59), now: recencyNow
        ) == "Updated 59s ago",
        "seconds timestamp was not formatted correctly"
    )
    try require(
        UsageTimestampFormatter.updatedText(
            capturedAt: recencyNow.addingTimeInterval(-60), now: recencyNow
        ) == "Updated 1m ago",
        "minutes timestamp was not formatted correctly"
    )
    try require(
        UsageTimestampFormatter.updatedText(
            capturedAt: recencyNow.addingTimeInterval(-7_200), now: recencyNow
        ) == "Updated 2h ago",
        "hours timestamp was not formatted correctly"
    )

    do {
        _ = try ClaudeUsageParser.snapshot(from: "Usage: unknown", now: now)
        throw CheckFailure.unexpected("invalid usage report was accepted")
    } catch UsageError.usageOutputInvalid {
        // Expected.
    }

    let codexResponse = """
    {"id":2,"result":{"rateLimitsByLimitId":{"codex":{"planType":"plus","primary":{"usedPercent":24,"windowDurationMins":300,"resetsAt":1784000000},"secondary":{"usedPercent":130,"windowDurationMins":10080,"resetsAt":1784500000}}}}}
    """
    let codex = try CodexUsageParser.snapshot(from: codexResponse, now: now)
    try require(codex.windows.count == 2, "Codex primary and secondary windows were not decoded")
    try require(codex.windows[0].remainingPercentage == 76, "Codex remaining usage was incorrect")
    try require(codex.windows[1].remainingPercentage == 0, "Codex percentage was not clamped")
    try require(codex.windows[0].durationLabel == "5-hour", "Codex hourly duration label was incorrect")
    try require(codex.windows[1].durationLabel == "7-day", "Codex weekly duration label was incorrect")
    try require(codex.planType == "plus", "Codex plan type was not decoded from rate limits")
    try require(
        codex.providerSnapshot.metrics.map(\.label) == ["5-hour", "7-day"],
        "Codex provider snapshot labels were not normalized"
    )
    try require(
        snapshot.providerSnapshot.metrics.first?.usedPercent == 32,
        "Claude provider snapshot was not normalized"
    )
    try require(
        UsageProvider.supported == [.claude, .codex],
        "an unsupported provider was exposed"
    )
    try require(
        ProviderDisplayPolicy.menuProviders(from: [.claude, .codex]) == [.claude, .codex],
        "two-provider menu policy changed"
    )
    try require(
        ProviderDisplayPolicy.menuProviders(from: [.claude, .codex, .antigravity]) == [.claude],
        "three-provider menu policy did not remain compact"
    )
    var pollingGate = PollingRequestGate()
    let stalePollingOwner = pollingGate.advance()
    let currentPollingOwner = pollingGate.advance()
    try require(!pollingGate.owns(stalePollingOwner), "stale polling owner was accepted")
    try require(pollingGate.owns(currentPollingOwner), "current polling owner was rejected")

    let cacheDecoder = JSONDecoder()
    cacheDecoder.dateDecodingStrategy = .iso8601
    let legacyClaudeCache = Data(#"{"fiveHour":{"utilization":32,"resetsAt":"2026-07-14T08:29:00Z"},"sevenDay":{"utilization":39,"resetsAt":"2026-07-17T03:00:00Z"},"capturedAt":"2026-07-14T05:00:00Z"}"#.utf8)
    let decodedClaudeCache = try cacheDecoder.decode(UsageSnapshot.self, from: legacyClaudeCache)
    try require(decodedClaudeCache.fiveHour.utilization == 32, "legacy Claude cache shape changed")

    let legacyCodexCache = Data(#"{"windows":[{"id":"primary","usedPercent":24,"windowDurationMins":300,"resetsAt":"2026-07-14T08:29:00Z"}],"planType":"plus","capturedAt":"2026-07-14T05:00:00Z"}"#.utf8)
    let decodedCodexCache = try cacheDecoder.decode(CodexUsageSnapshot.self, from: legacyCodexCache)
    try require(decodedCodexCache.windows.first?.usedPercent == 24, "legacy Codex cache shape changed")

    let primaryOnly = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":47,"windowDurationMins":10080}}}}
    """
    let weekly = try CodexUsageParser.snapshot(from: primaryOnly, now: now)
    try require(weekly.windows.count == 1, "primary-only Codex response produced a fake window")
    try require(weekly.windows[0].durationLabel == "7-day", "primary-only weekly label was incorrect")

    do {
        _ = try CodexUsageParser.snapshot(from: "{\"id\":2,\"result\":{}}", now: now)
        throw CheckFailure.unexpected("invalid Codex response was accepted")
    } catch UsageError.codexOutputInvalid {
        // Expected.
    }

    let output = try await CLIProcessRunner.run(.init(
        executable: "/usr/bin/printf",
        arguments: ["runner-ok"],
        timeout: 1
    ))
    try require(
        String(decoding: output.stdout, as: UTF8.self) == "runner-ok",
        "CLI runner did not collect stdout"
    )

    let standardInputOutput = try await CLIProcessRunner.run(.init(
        executable: "/bin/cat",
        arguments: [],
        standardInput: Data("stdin-ok".utf8),
        timeout: 1
    ))
    try require(
        String(decoding: standardInputOutput.stdout, as: UTF8.self) == "stdin-ok",
        "CLI runner did not send standard input"
    )

    let streamingOutput = try await CLIProcessRunner.runStreaming(.init(
        executable: "/bin/sh",
        arguments: ["-c", "printf ready; read line; printf \"%s\" \"$line\""],
        timeout: 1
    )) { _, session in
        session.send(Data("stream-ok\n".utf8))
        session.closeStandardInput()
    }
    try require(
        String(decoding: streamingOutput.stdout, as: UTF8.self) == "readystream-ok",
        "CLI runner streaming input handshake failed"
    )

    let environmentOutput = try await CLIProcessRunner.run(.init(
        executable: "/usr/bin/printenv",
        arguments: ["CLAWSTATUS_RUNNER_CHECK"],
        environmentOverrides: ["CLAWSTATUS_RUNNER_CHECK": "environment-ok"],
        timeout: 1
    ))
    try require(
        String(decoding: environmentOutput.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "environment-ok",
        "CLI runner did not apply an environment override"
    )

    do {
        _ = try await CLIProcessRunner.run(.init(
            executable: "/usr/bin/false",
            arguments: [],
            timeout: 1
        ))
        throw CheckFailure.unexpected("CLI runner accepted a non-zero exit")
    } catch CLIProcessRunner.RunnerError.exited {
        // Expected.
    }

    do {
        _ = try await CLIProcessRunner.run(.init(
            executable: "/bin/sleep",
            arguments: ["2"],
            timeout: 0.05
        ))
        throw CheckFailure.unexpected("CLI runner timeout did not fire")
    } catch CLIProcessRunner.RunnerError.timedOut {
        // Expected.
    }

    let cancelled = Task {
        try await CLIProcessRunner.run(.init(
            executable: "/bin/sleep",
            arguments: ["2"],
            timeout: 1
        ))
    }
    cancelled.cancel()
    do {
        _ = try await cancelled.value
        throw CheckFailure.unexpected("CLI runner ignored cancellation")
    } catch is CancellationError {
        // Expected.
    }

    if CommandLine.arguments.contains("--live-claude") {
        let liveSnapshot = try await UsageClient().fetch()
        try require(
            liveSnapshot.fiveHour.utilization >= 0 && liveSnapshot.sevenDay.utilization >= 0,
            "live Claude usage contained an invalid percentage"
        )
        print("Live Claude usage check passed")
    }

    print("Clawstatus checks passed")
} catch {
    FileHandle.standardError.write(Data("Clawstatus check failed: \(error)\n".utf8))
    exit(1)
}
