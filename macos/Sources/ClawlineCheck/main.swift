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

    let commaReport = report.replacingOccurrences(of: " at ", with: ", ")
    let commaSnapshot = try ClaudeUsageParser.snapshot(from: commaReport, now: now)
    try require(commaSnapshot.fiveHour.resetsAt != nil, "comma reset timestamp was not decoded")

    do {
        _ = try ClaudeUsageParser.snapshot(from: "Usage: unknown", now: now)
        throw CheckFailure.unexpected("invalid usage report was accepted")
    } catch UsageError.usageOutputInvalid {
        // Expected.
    }

    print("Clawline checks passed")
} catch {
    FileHandle.standardError.write(Data("Clawline check failed: \(error)\n".utf8))
    exit(1)
}
