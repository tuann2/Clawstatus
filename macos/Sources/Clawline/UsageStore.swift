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

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var codexSnapshot: CodexUsageSnapshot?
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
        return [claude, codex].compactMap { $0 }.joined(separator: " · ").isEmpty ? "—%" : [claude, codex].compactMap { $0 }.joined(separator: " · ")
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
            SnapshotCache.save(freshSnapshot)
        case .failure(let error): failures.append(error)
        }
        switch codex {
        case .success(let freshSnapshot):
            codexSnapshot = freshSnapshot
            SnapshotCache.saveCodex(freshSnapshot)
        case .failure(let error): failures.append(error)
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
}
