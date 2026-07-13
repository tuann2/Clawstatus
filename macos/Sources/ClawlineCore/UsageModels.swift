import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public var clampedUtilization: Double {
        min(max(utilization, 0), 100)
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
    public let capturedAt: Date

    public init(fiveHour: UsageWindow, sevenDay: UsageWindow, capturedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.capturedAt = capturedAt
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
        if let date = fractional.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

public enum UsageError: LocalizedError, Equatable {
    case credentialsMissing
    case credentialsInvalid
    case keychainAccessDenied
    case keychain(OSStatus)
    case unauthorized
    case server(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            "Claude Code is not signed in"
        case .credentialsInvalid:
            "Claude Code credentials are invalid"
        case .keychainAccessDenied:
            "Keychain access was not allowed"
        case .keychain(let status):
            "Keychain returned status \(status)"
        case .unauthorized:
            "Claude Code sign-in expired"
        case .server(let status):
            "Usage service returned HTTP \(status)"
        case .invalidResponse:
            "Usage service returned an unexpected response"
        }
    }
}
