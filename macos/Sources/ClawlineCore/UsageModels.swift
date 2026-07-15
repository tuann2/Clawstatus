import Foundation

public enum UsageProvider: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        }
    }

    public var menuSymbol: String {
        switch self {
        case .claude: "C"
        case .codex: "X"
        case .antigravity: "A"
        }
    }

    /// Antigravity remains reserved until its machine-readable feasibility gate is met.
    public static let supported: [UsageProvider] = [.claude, .codex]
}

public enum ProviderDisplayPolicy {
    public static func menuProviders(from enabled: [UsageProvider]) -> [UsageProvider] {
        enabled.count >= 3 ? Array(enabled.prefix(1)) : enabled
    }
}

public struct PollingRequestGate: Equatable, Sendable {
    private var revision: UInt64 = 0

    public init() {}

    public mutating func advance() -> UInt64 {
        revision &+= 1
        return revision
    }

    public func owns(_ candidate: UInt64) -> Bool {
        revision == candidate
    }
}

public struct ProviderUsageMetric: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var clampedUsedPercent: Double { min(max(usedPercent, 0), 100) }
    public var remainingPercentage: Double { 100 - clampedUsedPercent }
}

public struct ProviderUsageSnapshot: Equatable, Sendable {
    public let metrics: [ProviderUsageMetric]
    public let capturedAt: Date

    public init(metrics: [ProviderUsageMetric], capturedAt: Date) {
        self.metrics = metrics
        self.capturedAt = capturedAt
    }
}

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

public extension UsageSnapshot {
    var providerSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(metrics: [
            .init(id: "five-hour", label: "5-hour", usedPercent: fiveHour.clampedUtilization, resetsAt: fiveHour.resetsAt),
            .init(id: "seven-day", label: "7-day", usedPercent: sevenDay.clampedUtilization, resetsAt: sevenDay.resetsAt),
        ], capturedAt: capturedAt)
    }
}

public struct CodexUsageWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Date?

    public init(id: String, usedPercent: Int, windowDurationMins: Int?, resetsAt: Date?) {
        self.id = id
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var clampedUsedPercent: Int { min(max(usedPercent, 0), 100) }
    public var remainingPercentage: Int { 100 - clampedUsedPercent }

    public var durationLabel: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "Usage" }
        if minutes % (24 * 60) == 0 { return "\(minutes / (24 * 60))-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-min"
    }
}

public struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    public let windows: [CodexUsageWindow]
    public let planType: String?
    public let capturedAt: Date

    public init(windows: [CodexUsageWindow], planType: String?, capturedAt: Date) {
        self.windows = windows
        self.planType = planType
        self.capturedAt = capturedAt
    }
}


public extension CodexUsageSnapshot {
    var providerSnapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            metrics: windows.map {
                .init(
                    id: $0.id,
                    label: $0.durationLabel,
                    usedPercent: Double($0.clampedUsedPercent),
                    resetsAt: $0.resetsAt
                )
            },
            capturedAt: capturedAt
        )
    }
}

public enum UsageTimestampFormatter {
    public static func updatedText(capturedAt: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(capturedAt)))
        if seconds < 2 { return "Updated now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        if seconds < 60 * 60 { return "Updated \(seconds / 60)m ago" }
        return "Updated \(seconds / (60 * 60))h ago"
    }
}

public enum UsageError: LocalizedError, Equatable, Sendable {
    case claudeNotInstalled
    case claudeCommandFailed(String)
    case usageOutputInvalid
    case codexNotInstalled
    case codexCommandFailed(String)
    case codexOutputInvalid

    public var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            "Claude Code is not installed"
        case .claudeCommandFailed:
            "Claude Code could not retrieve usage"
        case .usageOutputInvalid:
            "Claude Code returned an unsupported usage report"
        case .codexNotInstalled:
            "Codex CLI is not installed"
        case .codexCommandFailed:
            "Codex CLI could not retrieve usage"
        case .codexOutputInvalid:
            "Codex CLI returned an unsupported usage report"
        }
    }
}
