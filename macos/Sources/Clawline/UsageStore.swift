import ClawlineCore
import Combine
import Foundation
import OSLog

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore(appVersion: bundleAppVersion, preferences: .shared)

    private static let claudeLogger = Logger(subsystem: "com.clawstatus", category: "Claude")
    private static let codexLogger = Logger(subsystem: "com.clawstatus", category: "Codex")
    private static let initialPollInterval: UInt64 = 60
    private static let maximumPollInterval: UInt64 = 300

    enum ConnectionState: Equatable {
        case empty
        case loading
        case cached
        case live
        case offline
    }

    enum ProviderState: Equatable {
        case loading
        case live
        case cached
        case unavailable(ProviderIssue)
        case disabled
    }

    struct ProviderIssue: Equatable {
        enum Kind: Equatable {
            case notInstalled
            case authentication
            case unsupportedOutput
            case unavailable
        }

        enum Recovery: Equatable {
            case openTerminal
        }

        let kind: Kind
        let message: String
        let recovery: Recovery?
    }

    struct ProviderRecord: Equatable {
        var snapshot: ProviderUsageSnapshot?
        var state: ProviderState

        var capturedAt: Date? { snapshot?.capturedAt }
        var issue: ProviderIssue? {
            guard case .unavailable(let issue) = state else { return nil }
            return issue
        }
    }

    @Published private(set) var providers: [UsageProvider: ProviderRecord]
    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var isRefreshing = false

    private let client: UsageClient
    private let codexClient: CodexUsageClient
    private let appVersion: String
    private let preferences: UIPreferences
    private var enabledProvidersObserver: AnyCancellable?
    private var pollingTask: Task<Void, Never>?
    private var pollingShutdownTask: Task<Void, Never>?
    private var pollingGate = PollingRequestGate()
    private var pollInterval = initialPollInterval
    private var generations: [UsageProvider: UInt64] = [:]

    init(
        client: UsageClient = UsageClient(),
        codexClient: CodexUsageClient = CodexUsageClient(),
        appVersion: String = "unknown",
        preferences: UIPreferences
    ) {
        self.client = client
        self.codexClient = codexClient
        self.appVersion = appVersion
        self.preferences = preferences

        let cached: [UsageProvider: ProviderUsageSnapshot?] = [
            .claude: SnapshotCache.load()?.providerSnapshot,
            .codex: SnapshotCache.loadCodex()?.providerSnapshot,
        ]
        providers = Dictionary(uniqueKeysWithValues: UsageProvider.supported.map { provider in
            let snapshot = cached[provider] ?? nil
            let enabled = preferences.enabledProviders.contains(provider)
            return (provider, ProviderRecord(
                snapshot: snapshot,
                state: enabled ? (snapshot == nil ? .loading : .cached) : .disabled
            ))
        })
        for provider in UsageProvider.supported { generations[provider] = 0 }
        updateConnectionState()

        enabledProvidersObserver = preferences.$enabledProviders
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] providers in
                self?.applyEnabledProviders(providers)
            }

        restartPollingIfNeeded()
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
        pollingShutdownTask?.cancel()
    }

    var enabledProviders: [UsageProvider] {
        UsageProvider.supported.filter(preferences.enabledProviders.contains)
    }

    var hasEnabledProviders: Bool { !enabledProviders.isEmpty }

    var providersWithTerminalRecovery: [UsageProvider] {
        enabledProviders.filter {
            providers[$0]?.issue?.recovery == .openTerminal
        }
    }

    func record(for provider: UsageProvider) -> ProviderRecord {
        providers[provider] ?? ProviderRecord(snapshot: nil, state: .disabled)
    }

    var menuLabel: String {
        let displayed = ProviderDisplayPolicy.menuProviders(from: enabledProviders)
        return displayed.compactMap { provider in
            guard let metric = providers[provider]?.snapshot?.metrics.first else { return nil }
            return "\(provider.menuSymbol) \(Self.percent(metric.remainingPercentage))"
        }.joined(separator: " · ")
    }

    var newestCapturedAt: Date? {
        enabledProviders.compactMap { providers[$0]?.capturedAt }.max()
    }

    func refresh() async {
        guard hasEnabledProviders else { return }
        pollInterval = Self.initialPollInterval
        restartPollingIfNeeded()
    }

    private enum FetchPayload: Sendable {
        case claude(UsageSnapshot)
        case codex(CodexUsageSnapshot)

        var snapshot: ProviderUsageSnapshot {
            switch self {
            case .claude(let value): value.providerSnapshot
            case .codex(let value): value.providerSnapshot
            }
        }
    }

    private struct FetchResult: Sendable {
        let provider: UsageProvider
        let generation: UInt64
        let result: Result<FetchPayload, UsageError>
    }

    private enum RefreshOutcome {
        case succeeded
        case allFailed
        case skipped
    }

    private func performRefresh(revision: UInt64) async -> RefreshOutcome {
        guard pollingGate.owns(revision), !isRefreshing else { return .skipped }
        let enabled = enabledProviders
        guard !enabled.isEmpty else { return .skipped }
        isRefreshing = true
        for provider in enabled where providers[provider]?.snapshot == nil {
            providers[provider]?.state = .loading
        }
        defer { isRefreshing = false }

        let generationSnapshot = generations
        let client = client
        let codexClient = codexClient
        let appVersion = appVersion
        let results = await withTaskGroup(of: FetchResult.self, returning: [FetchResult].self) { group in
            for provider in enabled {
                let generation = generationSnapshot[provider] ?? 0
                group.addTask {
                    switch provider {
                    case .claude:
                        do {
                            return FetchResult(provider: provider, generation: generation, result: .success(.claude(try await client.fetch())))
                        } catch let error as UsageError {
                            return FetchResult(provider: provider, generation: generation, result: .failure(error))
                        } catch {
                            return FetchResult(provider: provider, generation: generation, result: .failure(.claudeCommandFailed(error.localizedDescription)))
                        }
                    case .codex:
                        do {
                            return FetchResult(provider: provider, generation: generation, result: .success(.codex(try await codexClient.fetch(appVersion: appVersion))))
                        } catch let error as UsageError {
                            return FetchResult(provider: provider, generation: generation, result: .failure(error))
                        } catch {
                            return FetchResult(provider: provider, generation: generation, result: .failure(.codexCommandFailed(error.localizedDescription)))
                        }
                    case .antigravity:
                        return FetchResult(provider: provider, generation: generation, result: .failure(.usageOutputInvalid))
                    }
                }
            }
            var values: [FetchResult] = []
            for await result in group { values.append(result) }
            return values
        }

        var currentSuccesses = 0
        var currentFailures = 0
        for result in results {
            guard pollingGate.owns(revision),
                  preferences.enabledProviders.contains(result.provider),
                  generations[result.provider] == result.generation else {
                continue
            }
            switch result.result {
            case .success(let payload):
                currentSuccesses += 1
                providers[result.provider] = ProviderRecord(snapshot: payload.snapshot, state: .live)
                switch payload {
                case .claude(let snapshot): SnapshotCache.save(snapshot)
                case .codex(let snapshot): SnapshotCache.saveCodex(snapshot)
                }
            case .failure(let error):
                currentFailures += 1
                Self.log(error, provider: result.provider)
                providers[result.provider]?.state = .unavailable(Self.issue(for: error))
            }
        }
        updateConnectionState()
        if currentSuccesses > 0 { return .succeeded }
        if currentFailures == enabledProviders.count { return .allFailed }
        return .skipped
    }

    private func applyEnabledProviders(_ requested: Set<UsageProvider>) {
        let enabled = requested.intersection(UsageProvider.supported)
        let previouslyEnabled = Set(providers.compactMap { provider, record in
            record.state == .disabled ? nil : provider
        })
        guard enabled != previouslyEnabled else { return }

        pollInterval = Self.initialPollInterval
        for provider in UsageProvider.supported {
            generations[provider, default: 0] &+= 1
            if enabled.contains(provider) {
                let snapshot = providers[provider]?.snapshot
                providers[provider] = ProviderRecord(
                    snapshot: snapshot,
                    state: snapshot == nil ? .loading : .cached
                )
            } else {
                providers[provider]?.state = .disabled
            }
        }
        updateConnectionState()
        restartPollingIfNeeded()
    }

    private func restartPollingIfNeeded() {
        let revision = pollingGate.advance()
        let previousTask = pollingTask ?? pollingShutdownTask
        pollingTask?.cancel()
        pollingShutdownTask?.cancel()
        pollingTask = nil
        pollingShutdownTask = nil
        guard hasEnabledProviders else {
            pollingShutdownTask = Task {
                await previousTask?.value
            }
            return
        }
        let replacement = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled,
                  self?.pollingGate.owns(revision) == true,
                  self?.hasEnabledProviders == true else { return }
            await self?.pollContinuously(revision: revision)
        }
        pollingTask = replacement
    }

    private func pollContinuously(revision: UInt64) async {
        let initialOutcome = await performRefresh(revision: revision)
        if pollingGate.owns(revision), case .succeeded = initialOutcome {
            pollInterval = Self.initialPollInterval
        }
        await continuePolling(revision: revision)
    }

    private func continuePolling(revision: UInt64) async {
        while !Task.isCancelled, pollingGate.owns(revision), hasEnabledProviders {
            do {
                try await Task.sleep(for: .seconds(pollInterval))
            } catch {
                return
            }
            switch await performRefresh(revision: revision) {
            case .succeeded:
                if pollingGate.owns(revision) { pollInterval = Self.initialPollInterval }
            case .allFailed:
                if pollingGate.owns(revision) {
                    pollInterval = min(pollInterval * 2, Self.maximumPollInterval)
                }
            case .skipped:
                break
            }
        }
    }

    private func updateConnectionState() {
        let records = enabledProviders.map(record(for:))
        guard !records.isEmpty else {
            connectionState = .empty
            return
        }
        if records.contains(where: { $0.state == .live }) {
            connectionState = .live
        } else if records.contains(where: { $0.snapshot != nil }) {
            connectionState = .cached
        } else if records.contains(where: { $0.state == .loading }) {
            connectionState = .loading
        } else {
            connectionState = .offline
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func issue(for error: UsageError) -> ProviderIssue {
        switch error {
        case .claudeNotInstalled, .codexNotInstalled:
            ProviderIssue(
                kind: .notInstalled,
                message: "Install or sign in from Terminal",
                recovery: .openTerminal
            )
        case .usageOutputInvalid, .codexOutputInvalid:
            ProviderIssue(
                kind: .unsupportedOutput,
                message: "Unsupported output — update Clawstatus",
                recovery: nil
            )
        default:
            ProviderIssue(kind: .unavailable, message: "Usage unavailable", recovery: nil)
        }
    }

    private static func log(_ error: UsageError, provider: UsageProvider) {
        let logger = provider == .claude ? claudeLogger : codexLogger
        let kind: String
        switch error {
        case .claudeNotInstalled, .codexNotInstalled: kind = "not-installed"
        case .claudeCommandFailed, .codexCommandFailed: kind = "command-failed"
        case .usageOutputInvalid, .codexOutputInvalid: kind = "output-invalid"
        }
        logger.error("Usage fetch failed: \(kind, privacy: .public)")
    }
}
