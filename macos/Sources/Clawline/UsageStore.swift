import Foundation
import ClawlineCore
import OSLog

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore(appVersion: bundleAppVersion)

    private static let claudeLogger = Logger(subsystem: "com.clawstatus", category: "Claude")
    private static let codexLogger = Logger(subsystem: "com.clawstatus", category: "Codex")
    private static let initialPollInterval: UInt64 = 60
    private static let maximumPollInterval: UInt64 = 300

    enum ConnectionState: Equatable {
        case loading
        case cached
        case live
        case authentication(String)
        case offline(String)
    }

    enum ProviderState: Equatable {
        case loading
        case live
        case unavailable(String)
    }

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var codexSnapshot: CodexUsageSnapshot?
    @Published private(set) var claudeState: ProviderState = .loading
    @Published private(set) var codexState: ProviderState = .loading
    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var isRefreshing = false

    private let client: UsageClient
    private let codexClient: CodexUsageClient
    private let appVersion: String
    private var pollingTask: Task<Void, Never>?
    private var pollInterval = initialPollInterval
    private var hasFetchedSuccessfully = false

    init(
        client: UsageClient = UsageClient(),
        codexClient: CodexUsageClient = CodexUsageClient(),
        appVersion: String = "unknown"
    ) {
        self.client = client
        self.codexClient = codexClient
        self.appVersion = appVersion
        snapshot = SnapshotCache.load()
        codexSnapshot = SnapshotCache.loadCodex()
        if snapshot != nil || codexSnapshot != nil {
            connectionState = .cached
            claudeState = snapshot == nil ? .loading : .live
            codexState = codexSnapshot == nil ? .loading : .live
        }

        pollingTask = Task { [weak self] in
            await self?.pollContinuously()
        }
    }

    private static var bundleAppVersion: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !version.isEmpty else {
            return "unknown"
        }
        return version
    }

    deinit {
        pollingTask?.cancel()
    }

    var menuLabel: String {
        let claude = snapshot.map { "C \(Self.percent($0.fiveHour.remainingPercentage))" }
        let codex = codexSnapshot?.windows.first.map { "X \($0.remainingPercentage)%" }
        let labels = [claude, codex].compactMap { $0 }
        return labels.isEmpty ? "—%" : labels.joined(separator: " · ")
    }

    var newestCapturedAt: Date? {
        [snapshot?.capturedAt, codexSnapshot?.capturedAt].compactMap { $0 }.max()
    }

    var availabilityMessage: String? {
        [claudeState, codexState].compactMap { state in
            if case .unavailable(let message) = state { return message }
            return nil
        }.joined(separator: " · ").nilIfEmpty
    }

    func refresh() async {
        pollInterval = Self.initialPollInterval
        guard !isRefreshing else { return }
        pollingTask?.cancel()
        pollingTask = nil
        _ = await performRefresh()
        guard !Task.isCancelled else { return }
        pollingTask = Task { [weak self] in
            await self?.continuePolling()
        }
    }

    private enum RefreshOutcome {
        case succeeded
        case allFailed
        case skipped
    }

    private func performRefresh() async -> RefreshOutcome {
        guard !isRefreshing else { return .skipped }
        isRefreshing = true
        defer { isRefreshing = false }

        async let claudeResult: Result<UsageSnapshot, UsageError> = fetchClaudeResult()
        async let codexResult: Result<CodexUsageSnapshot, UsageError> = fetchCodexResult()

        let claude = await claudeResult
        let codex = await codexResult
        var failures: [UsageError] = []
        switch claude {
        case .success(let freshSnapshot):
            snapshot = freshSnapshot
            claudeState = .live
            SnapshotCache.save(freshSnapshot)
        case .failure(let error):
            failures.append(error)
            Self.log(error, logger: Self.claudeLogger)
            claudeState = .unavailable(Self.message(for: error, provider: "Claude"))
        }
        switch codex {
        case .success(let freshSnapshot):
            codexSnapshot = freshSnapshot
            codexState = .live
            SnapshotCache.saveCodex(freshSnapshot)
        case .failure(let error):
            failures.append(error)
            Self.log(error, logger: Self.codexLogger)
            codexState = .unavailable(Self.message(for: error, provider: "Codex"))
        }

        let anySuccess = failures.count < 2
        if anySuccess {
            hasFetchedSuccessfully = true
        }
        if hasFetchedSuccessfully, snapshot != nil || codexSnapshot != nil {
            connectionState = .live
        } else if snapshot != nil || codexSnapshot != nil {
            connectionState = .cached
        } else if failures.contains(.claudeNotInstalled) || failures.contains(.codexNotInstalled) {
            connectionState = .authentication("Install and sign in to Claude Code or Codex")
        } else {
            connectionState = .offline("Usage unavailable — retrying")
        }
        return anySuccess ? .succeeded : .allFailed
    }

    private func pollContinuously() async {
        let initialOutcome = await performRefresh()
        if case .succeeded = initialOutcome {
            pollInterval = Self.initialPollInterval
        }

        await continuePolling()
    }

    private func continuePolling() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(pollInterval))
            } catch {
                return
            }
            switch await performRefresh() {
            case .succeeded:
                pollInterval = Self.initialPollInterval
            case .allFailed:
                pollInterval = min(pollInterval * 2, Self.maximumPollInterval)
            case .skipped:
                break
            }
        }
    }

    private func fetchClaudeResult() async -> Result<UsageSnapshot, UsageError> {
        do { return .success(try await client.fetch()) }
        catch let error as UsageError { return .failure(error) }
        catch { return .failure(.claudeCommandFailed(error.localizedDescription)) }
    }

    private func fetchCodexResult() async -> Result<CodexUsageSnapshot, UsageError> {
        do { return .success(try await codexClient.fetch(appVersion: appVersion)) }
        catch let error as UsageError { return .failure(error) }
        catch { return .failure(.codexCommandFailed(error.localizedDescription)) }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func message(for error: UsageError, provider: String) -> String {
        switch error {
        case .claudeNotInstalled, .codexNotInstalled:
            "\(provider) unavailable — install and sign in"
        case .usageOutputInvalid, .codexOutputInvalid:
            "\(provider) output format changed — update Clawstatus"
        default:
            "\(provider) unavailable"
        }
    }

    private static func log(_ error: UsageError, logger: Logger) {
        let kind: String
        switch error {
        case .claudeNotInstalled:
            kind = "not-installed"
        case .claudeCommandFailed:
            kind = "command-failed"
        case .usageOutputInvalid:
            kind = "output-invalid"
        case .codexNotInstalled:
            kind = "not-installed"
        case .codexCommandFailed:
            kind = "command-failed"
        case .codexOutputInvalid:
            kind = "output-invalid"
        }
        logger.error("Usage fetch failed: \(kind, privacy: .public)")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
