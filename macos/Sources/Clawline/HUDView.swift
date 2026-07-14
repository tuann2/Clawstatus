import AppKit
import ClawlineCore
import SwiftUI

struct HUDView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: UIPreferences

    private let coral = Color(red: 1.0, green: 0.47, blue: 0.42)
    private let graphite = Color(red: 0.075, green: 0.082, blue: 0.094)

    var body: some View {
        Group {
            if preferences.isCompact {
                compactCard
            } else {
                fullCard
            }
        }
        .background(graphite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .opacity(preferences.opacity)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                preferences.toggleCompact()
            }
        )
        .contextMenu { cardMenu }
        .animation(.easeInOut(duration: 0.18), value: preferences.isCompact)
        .animation(.easeInOut(duration: 0.12), value: preferences.opacity)
        .preferredColorScheme(.dark)
    }

    private var fullCard: some View {
        VStack(spacing: 0) {
            header
            meters(showsReset: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 17)
            footer
        }
        .frame(width: 310)
    }

    private var compactCard: some View {
        meters(showsReset: false)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(width: 170)
    }

    @ViewBuilder
    private func meters(showsReset: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: showsReset ? 17 : 12) {
                if let snapshot = store.snapshot {
                    ProviderLabel(name: "Claude", showsReset: showsReset)
                    UsageMeter(
                        label: showsReset ? "5-hour" : "5h",
                        window: snapshot.fiveHour,
                        now: context.date,
                        tint: coral,
                        showsReset: showsReset
                    )
                    UsageMeter(
                        label: showsReset ? "7-day" : "7d",
                        window: snapshot.sevenDay,
                        now: context.date,
                        tint: .secondary,
                        showsReset: showsReset
                    )
                }
                if let codex = store.codexSnapshot {
                    ProviderLabel(name: "Codex", showsReset: showsReset)
                    ForEach(codex.windows) { window in
                        CodexUsageMeter(window: window, now: context.date, tint: .blue, showsReset: showsReset)
                    }
                }
                if store.snapshot == nil && store.codexSnapshot == nil {
                    PlaceholderMeter(label: showsReset ? "5-hour" : "5h")
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(coral)

            Text("Clawstatus")
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
            Button(action: openTerminal) {
                Label("Sign in", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(coral)
                    .labelStyle(CompactStatusLabelStyle())
            }
            .buttonStyle(.plain)
            .help("Open Terminal, then run claude or codex login to sign in")
        case .offline:
            Label("Offline", systemImage: "wifi.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(CompactStatusLabelStyle())
        }
    }

    @ViewBuilder
    private var cardMenu: some View {
        Button {
            preferences.toggleCompact()
        } label: {
            Label(
                preferences.isCompact ? "Full size" : "Compact size",
                systemImage: preferences.isCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
            )
        }

        Menu("Opacity") {
            ForEach(UIPreferences.opacityLevels, id: \.self) { level in
                Button {
                    preferences.selectOpacity(level)
                } label: {
                    HStack {
                        Text("\(Int(level * 100))%")
                        if preferences.opacity == level {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()
        Button("Refresh now") {
            Task { await store.refresh() }
        }
        Button("Quit Clawstatus") {
            NSApplication.shared.terminate(nil)
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
            .help("Quit Clawstatus")
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
        if case .authentication = store.connectionState { return coral }
        return .secondary
    }

    private func footerText(now: Date) -> String {
        switch store.connectionState {
        case .loading:
            return "Loading usage…"
        case .authentication(let message), .offline(let message):
            return message
        case .live:
            if let unavailable = store.availabilityMessage { return unavailable }
            guard let capturedAt = store.newestCapturedAt else { return "Live" }
            let seconds = max(0, Int(now.timeIntervalSince(capturedAt)))
            return seconds < 2 ? "Updated now" : "Updated \(seconds)s ago"
        }
    }

    private func openTerminal() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(
            at: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct UsageMeter: View {
    let label: String
    let window: UsageWindow
    let now: Date
    let tint: Color
    let showsReset: Bool

    var body: some View {
        VStack(spacing: showsReset ? 7 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.clampedUtilization.rounded()))%")
                    .font(.system(size: showsReset ? 24 : 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: window.clampedUtilization, total: 100)
                .progressViewStyle(.linear)
                .tint(tint)

            if showsReset {
                HStack {
                    Text("Resets")
                    Spacer()
                    Text(resetText)
                        .monospacedDigit()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let usage = "\(label) usage \(Int(window.clampedUtilization.rounded())) percent"
        return showsReset ? "\(usage), resets \(resetText)" : usage
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

private struct ProviderLabel: View {
    let name: String
    let showsReset: Bool

    var body: some View {
        Text(name)
            .font(.system(size: showsReset ? 11 : 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexUsageMeter: View {
    let window: CodexUsageWindow
    let now: Date
    let tint: Color
    let showsReset: Bool

    var body: some View {
        UsageMeter(
            label: window.durationLabel,
            window: UsageWindow(utilization: Double(window.clampedUsedPercent), resetsAt: window.resetsAt),
            now: now,
            tint: tint,
            showsReset: showsReset
        )
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
