import Combine
import Foundation

@MainActor
final class UIPreferences: ObservableObject {
    static let shared = UIPreferences()
    static let opacityLevels = [1.0, 0.85, 0.70, 0.55]

    @Published var isCompact: Bool {
        didSet { defaults.set(isCompact, forKey: Keys.isCompact) }
    }

    @Published var opacity: Double {
        didSet { defaults.set(opacity, forKey: Keys.opacity) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let isCompact = "ui.compact"
        static let opacity = "ui.opacity"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCompact = defaults.bool(forKey: Keys.isCompact)

        let savedOpacity = defaults.object(forKey: Keys.opacity) as? Double
        opacity = Self.opacityLevels.contains(savedOpacity ?? -1) ? savedOpacity! : 1.0
    }

    func toggleCompact() {
        isCompact.toggle()
    }

    func selectOpacity(_ value: Double) {
        guard Self.opacityLevels.contains(value) else { return }
        opacity = value
    }
}
