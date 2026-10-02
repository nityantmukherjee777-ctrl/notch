import Foundation

public enum InstallationLocation: Equatable {
    case applications, diskImage, translocated, other

    public static func classify(_ bundleURL: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let path = bundleURL.standardizedFileURL.path
        let components = bundleURL.standardizedFileURL.pathComponents
        if components.contains("AppTranslocation") { return .translocated }
        if path.hasPrefix("/Volumes/") { return .diskImage }
        let userApplications = home.appendingPathComponent("Applications").standardizedFileURL.path + "/"
        if path.hasPrefix("/Applications/") || path.hasPrefix(userApplications) { return .applications }
        return .other
    }

    public var mustInstallBeforePermissions: Bool { self == .diskImage || self == .translocated }
}
