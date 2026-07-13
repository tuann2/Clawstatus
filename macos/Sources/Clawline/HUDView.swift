import AppKit
import ClawlineCore
import SwiftUI

struct HUDView: View {
    @ObservedObject var store: UsageStore

    private let coral = Color(red: 1.0, green: 0.47, blue: 0.42)
    private let graphite = Color(red: 0.075, green: 0.082, blue: 0.094)

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 17) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let snapshot = store.snapshot {
                        UsageMeter(
                            label: "5-hour",
                            window: snapshot.fiveHour,
                            now: context.date,
                            tint: coral
                        )
                        UsageMeter(
                            label: "7-day",
                            window: snapshot.sevenDay,
                            now: context.date,
                            tint: .secondary
                        )
                    } else {
                        emptyMeters
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)

            footer
        }
        .frame(width: 310)
        .background(graphite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(coral)

            Text("Clawline")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            statusLabel
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.connectionState {
        case .loading:
            ProgressView().controlSize(.small)
        case .live:
            Label("Live", systemImage: "circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.green)
                .labelStyle(CompactStatusLabelStyle())
        case .authentication:
            Button(action: openClaudeSignIn) {
                Label("Sign in", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(coral)
                    .labelStyle(CompactStatusLabelStyle())
            }
            .buttonStyle(.plain)
            .help("Open Claude Code sign-in in Terminal")
        case .offline:
            Label("Offline", systemImage: "wifi.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(CompactStatusLabelStyle())
        }
    }

    private var emptyMeters: some View {
        VStack(spacing: 15) {
            PlaceholderMeter(label: "5-hour")
            PlaceholderMeter(label: "7-day")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(footerText(now: context.date))
                    .font(.system(size: 10))
                    .foregroundStyle(footerColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(store.isRefreshing ? .degrees(180) : .zero)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Refresh now")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Clawline")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private var footerColor: Color {
        switch store.connectionState {
        case .authentication:
            coral
        default:
            .secondary
        }
    }

    private func footerText(now: Date) -> String {
        switch store.connectionState {
        case .loading:
            return "Loading usage…"
        case .authentication(let message), .offline(let message):
            return message
        case .live:
            guard let capturedAt = store.snapshot?.capturedAt else { return "Live" }
            let seconds = max(0, Int(now.timeIntervalSince(capturedAt)))
            return seconds < 2 ? "Updated now" : "Updated \(seconds)s ago"
        }
    }

    private func openClaudeSignIn() {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/claude").path,
        ]

        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            if let docs = URL(string: "https://docs.anthropic.com/en/docs/claude-code/getting-started") {
                NSWorkspace.shared.open(docs)
            }
            return
        }

        let escaped = executable
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

private struct UsageMeter: View {
    let label: String
    let window: UsageWindow
    let now: Date
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.clampedUtilization.rounded()))%")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: window.clampedUtilization, total: 100)
                .progressViewStyle(.linear)
                .tint(tint)

            HStack {
                Text("Resets")
                Spacer()
                Text(resetText)
                    .monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) usage \(Int(window.clampedUtilization.rounded())) percent, resets \(resetText)")
    }

    private var resetText: String {
        guard let reset = window.resetsAt else { return "Unknown" }
        let seconds = max(0, Int(reset.timeIntervalSince(now)))
        if seconds == 0 { return "Now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 {
            return reset.formatted(date: .abbreviated, time: .shortened)
        }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}

private struct PlaceholderMeter: View {
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text("—%")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            ProgressView(value: 0, total: 100)
        }
    }
}

private struct CompactStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}
