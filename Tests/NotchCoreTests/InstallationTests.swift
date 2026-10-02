import Foundation
import Testing
@testable import NotchCore

struct InstallationTests {
    @Test func onlyInstalledPathsAreRecognizedAndDevelopmentCopiesStillRun() {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(InstallationLocation.classify(URL(fileURLWithPath: "/Applications/NotchHarbor.app"), home: home) == .applications)
        #expect(InstallationLocation.classify(URL(fileURLWithPath: "/Users/test/Applications/NotchHarbor.app"), home: home) == .applications)
        #expect(InstallationLocation.classify(URL(fileURLWithPath: "/Applications-copy/NotchHarbor.app"), home: home) == .other)
        #expect(InstallationLocation.classify(URL(fileURLWithPath: "/Users/test/Applications/../Downloads/NotchHarbor.app"), home: home) == .other)
        #expect(!InstallationLocation.classify(URL(fileURLWithPath: "/project/dist/NotchHarbor.app"), home: home).mustInstallBeforePermissions)
    }
    @Test func diskImageAndTranslocatedCopiesMustNotStartPermissionServices() {
        #expect(InstallationLocation.classify(URL(fileURLWithPath: "/Volumes/NotchHarbor/NotchHarbor.app")).mustInstallBeforePermissions)
        #expect(InstallationLocation.classify(URL(fileURLWithPath: "/private/var/folders/test/AppTranslocation/random/d/NotchHarbor.app")) == .translocated)
        #expect(InstallationLocation.translocated.mustInstallBeforePermissions)
    }
}
