import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        showHUD()
    }

    private func showHUD() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let hostingView = NSHostingView(rootView: HUDView(store: .shared))
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
    }
}

@main
struct ClawstatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore.shared

    var body: some Scene {
        MenuBarExtra {
            HUDView(store: store)
        } label: {
            Text(store.menuLabel)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
