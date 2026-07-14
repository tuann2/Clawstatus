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

    public var remainingPercentage: Double {
        100 - clampedUtilization
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

    public var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            "Claude Code is not installed"
        case .claudeCommandFailed:
            "Claude Code could not retrieve usage"
        case .usageOutputInvalid:
            "Claude Code returned an unsupported usage report"
        }
    }
}
