import AppKit
import Combine
import Sparkle

/// Shipping configuration belongs to the signed bundle, not editable preferences.
struct UpdateConfiguration: Equatable {
    let feedURL: URL
    let publicKey: String

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              let key = info["SUPublicEDKey"] as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32 else { return nil }
        feedURL = url
        publicKey = key
    }
}

@MainActor final class UpdateService: NSObject, ObservableObject, NSMenuItemValidation {
    @Published private(set) var configured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var status = "Updates aren’t configured for this build yet."
    private var controller: SPUStandardUpdaterController?
    private var subscriptions: Set<AnyCancellable> = []

    func start() {
        guard controller == nil else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        guard UpdateConfiguration(info: info) != nil else {
            // Local builds must neither contact a placeholder feed nor prompt
            // users repeatedly when release hosting hasn't been set up.
            return
        }
        let candidate = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try candidate.updater.start()
            controller = candidate
            configured = true
            status = "Signed updates are checked in the background."
            candidate.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &subscriptions)
            candidate.updater.publisher(for: \.automaticallyChecksForUpdates)
                .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }.store(in: &subscriptions)
            candidate.updater.publisher(for: \.automaticallyDownloadsUpdates)
                .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }.store(in: &subscriptions)
            candidate.updater.publisher(for: \.lastUpdateCheckDate)
                .sink { [weak self] in self?.lastUpdateCheckDate = $0 }.store(in: &subscriptions)
        } catch {
            status = "Updates couldn’t start. \(error.localizedDescription)"
        }
    }

    func setAutomaticChecks(_ value: Bool) {
        controller?.updater.automaticallyChecksForUpdates = value
    }
    func setAutomaticDownloads(_ value: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = value
    }
    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(sender)
    }
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        return item
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }
}
