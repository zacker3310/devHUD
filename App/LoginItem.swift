import Foundation
import ServiceManagement

// macOS 13+ login item for the main app. SMAppService pins the bundle at its
// current path, so register the copy in ~/Applications, not the one in
// DerivedData. Users see it under System Settings > General > Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .requiresApproval: return "requires approval in System Settings"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
