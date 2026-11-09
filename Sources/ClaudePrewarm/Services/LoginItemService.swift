import Foundation
import ServiceManagement

enum LoginItemService {
    /// A copy run from a build folder must never register itself, or the
    /// next login would start it next to the real one.
    static var isInstalledCopy: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a message to show the user.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        if enabled && !isInstalledCopy { return nil }
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return nil }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return nil }
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Launch at login could not be changed. \(error.localizedDescription)"
        }
    }

    /// Re-registers when the app was registered from a different path.
    static func refreshIfMoved(enabled: Bool) {
        let key = "loginItemBundlePath"
        let path = Bundle.main.bundlePath
        let defaults = UserDefaults.standard
        defer { defaults.set(path, forKey: key) }
        guard enabled, defaults.string(forKey: key) != path else { return }
        try? SMAppService.mainApp.unregister()
        try? SMAppService.mainApp.register()
    }
}
