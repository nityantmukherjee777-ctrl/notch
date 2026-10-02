import Foundation
import Testing
@testable import Notch

@Suite @MainActor struct UpdateServiceTests {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    @Test func missingFeedOrKeyDoesNotEnableUpdates() {
        #expect(UpdateConfiguration(info: [:]) == nil)
        #expect(UpdateConfiguration(info: ["SUPublicEDKey": key]) == nil)
        #expect(UpdateConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml"]) == nil)
    }
    @Test func onlySecureFeedAndValidPublicKeyAreAccepted() {
        let url = "https://github.com/owner/repo/releases/latest/download/appcast.xml"
        #expect(UpdateConfiguration(info: ["SUFeedURL": url, "SUPublicEDKey": key])?.feedURL.absoluteString == url)
        for feed in ["http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https:///", "https://user:pass@example.com/appcast.xml", "https://example.com/appcast.xml#fragment"] {
            #expect(UpdateConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": key]) == nil)
        }
        for invalid in ["", "not a key", Data(repeating: 1, count: 31).base64EncodedString(), Data(repeating: 1, count: 64).base64EncodedString()] {
            #expect(UpdateConfiguration(info: ["SUFeedURL": url, "SUPublicEDKey": invalid]) == nil)
        }
    }
    @Test func unconfiguredStartupIsQuietAndManualCheckIsUnavailable() {
        let service = UpdateService()
        service.start()
        service.start()
        service.checkForUpdates()
        service.setAutomaticChecks(true)
        service.setAutomaticDownloads(true)
        #expect(!service.configured && !service.canCheckForUpdates)
        #expect(!service.automaticallyChecksForUpdates && !service.automaticallyDownloadsUpdates)
        #expect(service.lastUpdateCheckDate == nil)
        #expect(!service.validateMenuItem(service.menuItem()))
    }
}
