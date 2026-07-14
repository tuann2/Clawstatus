import Foundation
import ClawlineCore

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    enum ConnectionState: Equatable {
        case loading
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
    private var pollingTask: Task<Void, Never>?

    init(client: UsageClient = UsageClient(), codexClient: CodexUsageClient = CodexUsageClient()) {
        self.client = client
        self.codexClient = codexClient
        snapshot = SnapshotCache.load()
        codexSnapshot = SnapshotCache.loadCodex()
        if snapshot != nil || codexSnapshot != nil {
            connectionState = .live
            claudeState = snapshot == nil ? .loading : .live
            codexState = codexSnapshot == nil ? .loading : .live
        }

        pollingTask = Task { [weak self] in
            await self?.pollContinuously()
        }
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
        guard !isRefreshing else { return }
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
            claudeState = .unavailable(Self.message(for: error, provider: "Claude"))
        }
        switch codex {
        case .success(let freshSnapshot):
            codexSnapshot = freshSnapshot
            codexState = .live
            SnapshotCache.saveCodex(freshSnapshot)
        case .failure(let error):
            failures.append(error)
            codexState = .unavailable(Self.message(for: error, provider: "Codex"))
        }
        if snapshot != nil || codexSnapshot != nil {
            connectionState = .live
        } else if failures.contains(.claudeNotInstalled) || failures.contains(.codexNotInstalled) {
            connectionState = .authentication("Install and sign in to Claude Code or Codex")
        } else {
            connectionState = .offline("Usage unavailable — retrying")
        }
    }

    private func pollContinuously() async {
        await refresh()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            await refresh()
        }
    }

    private func fetchClaudeResult() async -> Result<UsageSnapshot, UsageError> {
        do { return .success(try await client.fetch()) }
        catch let error as UsageError { return .failure(error) }
        catch { return .failure(.claudeCommandFailed(error.localizedDescription)) }
    }

    private func fetchCodexResult() async -> Result<CodexUsageSnapshot, UsageError> {
        do { return .success(try await codexClient.fetch()) }
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
        default:
            "\(provider) unavailable"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
