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

public enum UsageError: LocalizedError, Equatable {
    case claudeNotInstalled
    case claudeCommandFailed(String)
    case usageOutputInvalid
    case credentialsMissing
    case credentialsInvalid
    case keychainAccessDenied
    case keychain(OSStatus)
    case unauthorized
    case server(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            "Claude Code is not installed"
        case .claudeCommandFailed:
            "Claude Code could not retrieve usage"
        case .usageOutputInvalid:
            "Claude Code returned an unsupported usage report"
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
