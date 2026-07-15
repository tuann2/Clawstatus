import Combine
import ClawlineCore
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

    @Published var enabledProviders: Set<UsageProvider> {
        didSet {
            let supported = enabledProviders.intersection(UsageProvider.supported)
            if supported != enabledProviders {
                enabledProviders = supported
                return
            }
            defaults.set(supported.map(\.rawValue).sorted(), forKey: Keys.enabledProviders)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let isCompact = "ui.compact"
        static let opacity = "ui.opacity"
        static let enabledProviders = "providers.enabled"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCompact = defaults.bool(forKey: Keys.isCompact)

        let savedOpacity = defaults.object(forKey: Keys.opacity) as? Double
        opacity = Self.opacityLevels.contains(savedOpacity ?? -1) ? savedOpacity! : 1.0

        if let values = defaults.stringArray(forKey: Keys.enabledProviders) {
            enabledProviders = Set(values.compactMap(UsageProvider.init(rawValue:)))
                .intersection(UsageProvider.supported)
        } else {
            enabledProviders = Set(UsageProvider.supported)
        }
    }

    func toggleCompact() {
        isCompact.toggle()
    }

    func selectOpacity(_ value: Double) {
        guard Self.opacityLevels.contains(value) else { return }
        opacity = value
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        enabledProviders.contains(provider)
    }

    func setEnabled(_ enabled: Bool, for provider: UsageProvider) {
        guard UsageProvider.supported.contains(provider) else { return }
        if enabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
    }

}
