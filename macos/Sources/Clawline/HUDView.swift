import AppKit
import ClawlineCore
import SwiftUI

private func openTerminal() {
    let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    NSWorkspace.shared.openApplication(
        at: terminal,
        configuration: NSWorkspace.OpenConfiguration()
    )
}

struct HUDView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: UIPreferences
    @State private var isShowingProviderSettings = false

    private let coral = Color(red: 1.0, green: 0.47, blue: 0.42)
    private let graphite = Color(red: 0.075, green: 0.082, blue: 0.094)

    var body: some View {
        Group {
            if preferences.isCompact { compactCard } else { fullCard }
        }
        .popover(isPresented: $isShowingProviderSettings, arrowEdge: .bottom) {
            ProviderSettingsPopover(preferences: preferences)
        }
        .background(graphite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .opacity(preferences.opacity)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .simultaneousGesture(TapGesture(count: 2).onEnded { preferences.toggleCompact() })
        .contextMenu { cardMenu }
        .animation(.easeInOut(duration: 0.18), value: preferences.isCompact)
        .animation(.easeInOut(duration: 0.18), value: preferences.enabledProviders)
        .animation(.easeInOut(duration: 0.12), value: preferences.opacity)
        .preferredColorScheme(.dark)
    }

    private var fullCard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                providerContent(compact: false)
                    .padding(14)
            }
            .frame(maxHeight: 410)
            footer
        }
        .frame(width: 330)
    }

    private var compactCard: some View {
        providerContent(compact: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(width: 210)
    }

    @ViewBuilder
    private func providerContent(compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: compact ? 7 : 10) {
                if store.enabledProviders.isEmpty {
                    EmptyProvidersView(compact: compact) {
                        isShowingProviderSettings = true
                    }
                } else {
                    ForEach(store.enabledProviders) { provider in
                        ProviderUsageCard(
                            provider: provider,
                            record: store.record(for: provider),
                            now: context.date,
                            compact: compact,
                            tint: tint(for: provider)
                        )
                    }
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
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(freshnessText(now: context.date))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            settingsButton
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var settingsButton: some View {
        Button {
            isShowingProviderSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Provider settings")
    }

    @ViewBuilder
    private var cardMenu: some View {
        Menu("Providers") {
            ForEach(UsageProvider.supported) { provider in
                Toggle(provider.displayName, isOn: providerBinding(provider))
            }
            Divider()
            Button("Provider settings…") { isShowingProviderSettings = true }
        }

        if !store.providersWithTerminalRecovery.isEmpty {
            Divider()
            ForEach(store.providersWithTerminalRecovery) { provider in
                Button("Open Terminal for \(provider.displayName)") {
                    openTerminal()
                }
            }
        }

        Button {
            preferences.toggleCompact()
        } label: {
            Label(
                preferences.isCompact ? "Full size" : "Compact size",
                systemImage: preferences.isCompact
                    ? "arrow.up.left.and.arrow.down.right"
                    : "arrow.down.right.and.arrow.up.left"
            )
        }

        Menu("Opacity") {
            ForEach(UIPreferences.opacityLevels, id: \.self) { level in
                Button { preferences.selectOpacity(level) } label: {
                    HStack {
                        Text("\(Int(level * 100))%")
                        if preferences.opacity == level { Image(systemName: "checkmark") }
                    }
                }
            }
        }

        Divider()
        Button("Refresh now") { Task { await store.refresh() } }
            .disabled(!store.hasEnabledProviders)
        Button("Quit Clawstatus") { NSApplication.shared.terminate(nil) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(freshnessText(now: context.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            settingsButton
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(store.isRefreshing ? .degrees(180) : .zero)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing || !store.hasEnabledProviders)
            .help("Refresh now")
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Clawstatus")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private func providerBinding(_ provider: UsageProvider) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(provider) },
            set: { preferences.setEnabled($0, for: provider) }
        )
    }

    private func freshnessText(now: Date) -> String {
        guard store.hasEnabledProviders else { return "Providers off" }
        if store.isRefreshing { return "Refreshing…" }
        guard let capturedAt = store.newestCapturedAt else { return "Waiting for usage…" }
        return UsageTimestampFormatter.updatedText(capturedAt: capturedAt, now: now)
    }

    private func tint(for provider: UsageProvider) -> Color {
        switch provider {
        case .claude: coral
        case .codex: .blue
        case .antigravity: .purple
        }
    }
}

private struct ProviderUsageCard: View {
    let provider: UsageProvider
    let record: UsageStore.ProviderRecord
    let now: Date
    let compact: Bool
    let tint: Color

    var body: some View {
        VStack(spacing: compact ? 7 : 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Text(provider.menuSymbol)
                        .font(.system(size: compact ? 9 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }
                .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                Text(provider.displayName)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                ProviderStatusBadge(state: record.state, hasSnapshot: record.snapshot != nil, compact: compact)
            }

            if compact {
                compactSummary
            } else if let snapshot = record.snapshot {
                ForEach(snapshot.metrics) { metric in
                    UsageMetricRow(metric: metric, now: now, tint: tint)
                }
                if let issue = record.issue {
                    recoveryRow(issue)
                }
            } else {
                unavailablePlaceholder
            }
        }
        .padding(compact ? 9 : 12)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var compactSummary: some View {
        if let metric = record.snapshot?.metrics.first {
            HStack(spacing: 8) {
                Text(metric.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                ProgressView(value: metric.clampedUsedPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint)
                Text("\(Int(metric.clampedUsedPercent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        } else {
            unavailablePlaceholder
        }
    }

    private var unavailablePlaceholder: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if case .loading = record.state { ProgressView().controlSize(.small) }
                Text(statusMessage)
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if !compact, let issue = record.issue, issue.recovery != nil {
                Button("Open Terminal") { openTerminal() }
                    .controlSize(.small)
            }
        }
        .frame(minHeight: compact ? 12 : 24)
    }

    @ViewBuilder
    private func recoveryRow(_ issue: UsageStore.ProviderIssue) -> some View {
        HStack(spacing: 8) {
            Text(issue.message)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer()
            if issue.recovery == .openTerminal {
                Button("Open Terminal") { openTerminal() }
                    .controlSize(.mini)
            }
        }
    }

    private var statusMessage: String {
        switch record.state {
        case .loading: "Loading usage…"
        case .unavailable(let issue): issue.message
        case .disabled: "Disabled"
        case .cached: "Using cached usage"
        case .live: "Usage unavailable"
        }
    }
}

private struct UsageMetricRow: View {
    let metric: ProviderUsageMetric
    let now: Date
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(metric.clampedUsedPercent.rounded()))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            ProgressView(value: metric.clampedUsedPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
            HStack {
                Text("Resets")
                Spacer()
                Text(resetText).monospacedDigit()
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label) usage \(Int(metric.clampedUsedPercent.rounded())) percent, resets \(resetText)")
    }

    private var resetText: String {
        guard let reset = metric.resetsAt else { return "Unknown" }
        let seconds = max(0, Int(reset.timeIntervalSince(now)))
        if seconds == 0 { return "Now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 { return reset.formatted(date: .abbreviated, time: .shortened) }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}

private struct ProviderStatusBadge: View {
    let state: UsageStore.ProviderState
    let hasSnapshot: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 5))
            if !compact { Text(label) }
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .help(label)
    }

    private var label: String {
        switch state {
        case .loading: "Loading"
        case .live: "Live"
        case .cached: "Cached"
        case .unavailable: hasSnapshot ? "Cached" : "Unavailable"
        case .disabled: "Off"
        }
    }

    private var icon: String {
        switch state {
        case .loading: "clock.fill"
        case .live: "circle.fill"
        case .cached: "clock.fill"
        case .unavailable: hasSnapshot ? "clock.fill" : "exclamationmark.circle.fill"
        case .disabled: "minus.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .live: .green
        case .unavailable where !hasSnapshot: .orange
        default: .secondary
        }
    }
}

private struct EmptyProvidersView: View {
    let compact: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: compact ? 16 : 24))
                .foregroundStyle(.secondary)
            Text("Enable a provider in Settings")
                .font(.system(size: compact ? 9 : 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !compact {
                Button("Choose providers") { openSettings() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 52 : 110)
    }
}

private struct ProviderSettingsPopover: View {
    @ObservedObject var preferences: UIPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Providers")
                .font(.system(size: 13, weight: .semibold))
            Text("Choose which CLI usage appears and is polled.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(UsageProvider.supported) { provider in
                Toggle("Show \(provider.displayName) usage", isOn: Binding(
                    get: { preferences.isEnabled(provider) },
                    set: { preferences.setEnabled($0, for: provider) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 260)
        .preferredColorScheme(.dark)
    }
}
