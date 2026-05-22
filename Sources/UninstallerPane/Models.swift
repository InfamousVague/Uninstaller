import AppKit
import SwiftUI
import Observation

/// One installed app the user could uninstall.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let bundleURL: URL          // /Applications/Foo.app
    public let bundleID: String        // com.example.foo
    public let displayName: String     // "Foo"
    public let version: String?        // "1.4.2"
    public let appSize: Int64          // bytes on disk

    public var id: String { bundleID }

    /// AppKit-loaded icon. Cheap to call; `NSWorkspace` does its own
    /// caching. Sized large enough (64pt) that the UI's scale-up +
    /// clip pass — which crops the antialiased squircle margin — has
    /// crisp source pixels to work with on retina.
    public var icon: NSImage {
        let img = NSWorkspace.shared.icon(forFile: bundleURL.path)
        img.size = NSSize(width: 64, height: 64)
        return img
    }
}

/// One piece of residue tied to an app — preferences, caches, login
/// items, etc. `requiresAdmin` is true for /Library paths the user
/// can't trash without privilege escalation; the UI surfaces those
/// as informational so the user knows they exist.
public struct ResidueItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case appBundle           = "App bundle"
        case preferences         = "Preferences"
        case applicationSupport  = "Application Support"
        case caches              = "Caches"
        case savedState          = "Saved state"
        case logs                = "Logs"
        case containers          = "Sandbox container"
        case groupContainers     = "Group container"
        case httpStorages        = "HTTP storage"
        case webKit              = "WebKit data"
        case cookies             = "Cookies"
        case launchAgentUser     = "Login item (user)"
        case launchAgentSystem   = "Login item (system)"
        case launchDaemon        = "Launch daemon"
        case receipt             = "Install receipt"
        case crashReports        = "Crash reports"
    }

    public let path: URL
    public let kind: Kind
    public let size: Int64
    public let requiresAdmin: Bool

    public var id: String { path.path }
}

/// Everything found for one app: its bundle + every residue path.
public struct UninstallPlan: Sendable {
    public let app: InstalledApp
    public let items: [ResidueItem]

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var trashableItems: [ResidueItem] {
        items.filter { !$0.requiresAdmin }
    }
    public var hasAdminOnly: Bool { items.contains(where: \.requiresAdmin) }
}

/// Outcome of one trash attempt — surfaced in the UI as a toast.
public struct UninstallReport: Sendable, Equatable, Hashable {
    public struct Failure: Sendable, Equatable, Hashable {
        public let path: URL
        public let error: String
    }
    public let appName: String
    public let trashedCount: Int
    public let trashedBytes: Int64
    public let skippedAdmin: Int
    public let failures: [Failure]

    public var ok: Bool { failures.isEmpty }
}

/// State machine for the pane. Single source of truth for the UI.
@MainActor
@Observable
public final class UninstallerStore {

    public enum Phase: Equatable {
        case idle, scanningApps, scanningResidue, working
        case done(UninstallReport)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var apps: [InstalledApp] = []
    public private(set) var selectedID: String? = nil
    public private(set) var plan: UninstallPlan? = nil
    public var query: String = ""
    public var trashInsteadOfPermanent: Bool = true

    public init() {}

    /// Filtered + sorted view used by the list pane.
    public var visibleApps: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? apps
            : apps.filter {
                $0.displayName.lowercased().contains(q)
                || $0.bundleID.lowercased().contains(q)
            }
        return base.sorted {
            $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName) == .orderedAscending
        }
    }

    // MARK: Discovery

    public func bootstrap() {
        guard apps.isEmpty else { return }
        rescanApps()
    }

    public func rescanApps() {
        phase = .scanningApps
        Task.detached(priority: .userInitiated) {
            let found = AppInventory.scan()
            await MainActor.run {
                self.apps = found
                self.phase = .idle
                // Keep current selection if still installed.
                if let sel = self.selectedID,
                   !found.contains(where: { $0.id == sel }) {
                    self.selectedID = nil
                    self.plan = nil
                }
            }
        }
    }

    public func select(_ app: InstalledApp) {
        selectedID = app.id
        plan = nil
        phase = .scanningResidue
        Task.detached(priority: .userInitiated) {
            let items = ResidueScanner.scan(app: app)
            let p = UninstallPlan(app: app, items: items)
            await MainActor.run {
                guard self.selectedID == app.id else { return }
                self.plan = p
                self.phase = .idle
            }
        }
    }

    // MARK: Action

    /// One-click uninstall — trash the bundle + every user-trashable
    /// residue path. System paths (requires admin) are reported but
    /// not touched; the user can clean those manually if they care.
    public func uninstallSelected() {
        guard let plan, phase == .idle else { return }
        phase = .working
        let trashing = trashInsteadOfPermanent
        Task.detached(priority: .userInitiated) {
            let report = await Trasher.execute(
                plan: plan, trash: trashing)
            await MainActor.run {
                self.phase = .done(report)
                self.plan = nil
                self.selectedID = nil
                // Refresh the app list so the trashed bundle drops out.
                self.rescanApps()
            }
        }
    }

    public func dismissReport() {
        if case .done = phase { phase = .idle }
    }
}
