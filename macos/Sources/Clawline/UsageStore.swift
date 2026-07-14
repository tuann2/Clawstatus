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
    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var isRefreshing = false

    private let client: UsageClient
    private var pollingTask: Task<Void, Never>?

    init(client: UsageClient = UsageClient()) {
        self.client = client
        snapshot = SnapshotCache.load()
        if snapshot != nil {
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
        guard let snapshot else { return "—%" }
        return Self.percent(snapshot.fiveHour.remainingPercentage)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let freshSnapshot = try await client.fetch()
            snapshot = freshSnapshot
            connectionState = .live
            SnapshotCache.save(freshSnapshot)
        } catch UsageError.claudeNotInstalled {
            connectionState = .authentication("Install Claude Code, then sign in")
        } catch UsageError.claudeCommandFailed {
            connectionState = .authentication("Open Claude Code and sign in")
        } catch UsageError.usageOutputInvalid {
            connectionState = .offline("Claude Code usage format changed")
        } catch {
            connectionState = .offline("Offline — retrying")
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

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
