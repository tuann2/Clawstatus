import AppKit
import ClawlineCore
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<HUDView>?
    private var compactObserver: AnyCancellable?
    private var contentObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        showHUD()
    }

    private func showHUD() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let preferences = UIPreferences.shared
        let hostingView = NSHostingView(
            rootView: HUDView(store: .shared, preferences: preferences)
        )
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView
        compactObserver = preferences.$isCompact
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resizeHUD()
                }
            }
        contentObserver = Publishers.CombineLatest(UsageStore.shared.$providers, preferences.$enabledProviders)
            .map { records, enabled in
                HUDContentShape(entries: UsageProvider.supported.map { provider in
                    let record = records[provider]
                    return HUDContentShape.Entry(
                        provider: provider,
                        enabled: enabled.contains(provider),
                        metricCount: record?.snapshot?.metrics.count ?? 0,
                        state: record?.state ?? .disabled
                    )
                })
            }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeHUD()
            }
    }

    private func resizeHUD() {
        guard let panel, let hostingView else { return }
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        var size = hostingView.fittingSize
        if let visibleHeight = panel.screen?.visibleFrame.height {
            size.height = min(size.height, max(220, visibleHeight - 40))
        }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(
            NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true,
            animate: true
        )
    }
}

private struct HUDContentShape: Equatable {
    struct Entry: Equatable {
        let provider: UsageProvider
        let enabled: Bool
        let metricCount: Int
        let state: UsageStore.ProviderState
    }

    let entries: [Entry]
}

@main
struct ClawstatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore.shared
    @StateObject private var preferences = UIPreferences.shared

    var body: some Scene {
        MenuBarExtra {
            HUDView(store: store, preferences: preferences)
        } label: {
            if store.hasEnabledProviders {
                Text(store.menuLabel.isEmpty ? "…" : store.menuLabel)
                    .monospacedDigit()
                    .help("C = Claude remaining usage · X = Codex remaining usage")
            } else {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .help("Clawstatus — providers disabled")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
