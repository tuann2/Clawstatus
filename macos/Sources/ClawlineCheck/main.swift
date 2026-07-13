import ClawlineCore
import Foundation

enum CheckFailure: Error {
    case unexpected(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.unexpected(message) }
}

do {
    let usageData = Data(
        """
        {
          "five_hour": {
            "utilization": 68.4,
            "resets_at": "2026-07-13T18:00:00.000Z"
          },
          "seven_day": {
            "utilization": 42,
            "resets_at": "2026-07-20T02:00:00Z"
          }
        }
        """.utf8
    )
    let response = try JSONDecoder().decode(UsageAPIResponse.self, from: usageData)
    let snapshot = try response.snapshot(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
    try require(snapshot.fiveHour.utilization == 68.4, "5-hour usage was not decoded")
    try require(snapshot.sevenDay.utilization == 42, "7-day usage was not decoded")
    try require(snapshot.fiveHour.resetsAt != nil, "fractional reset timestamp was not decoded")
    try require(UsageWindow(utilization: 120, resetsAt: nil).clampedUtilization == 100, "usage was not clamped")

    let credentialData = Data(
        """
        {"claudeAiOauth":{"accessToken":"test-token","refreshToken":"ignored"}}
        """.utf8
    )
    let accessToken = try CredentialReader.accessToken(from: credentialData)
    try require(accessToken == "test-token", "access token was not extracted")

    do {
        _ = try CredentialReader.accessToken(from: Data("{}".utf8))
        throw CheckFailure.unexpected("missing access token was accepted")
    } catch UsageError.credentialsInvalid {
        // Expected.
    }

    print("Clawline checks passed")
} catch {
    FileHandle.standardError.write(Data("Clawline check failed: \(error)\n".utf8))
    exit(1)
}
