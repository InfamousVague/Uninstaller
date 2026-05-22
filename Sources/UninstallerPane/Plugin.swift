import AppKit
import SwiftUI
import SuiteKit

/// Uninstaller as a SuiteKit pane. Owns the store, vends the picker
/// UI + tray glyph. Scan is bootstrap + on-demand: opening the
/// popover (paneDidOpen) re-scans the apps list so freshly-installed
/// apps show up without a relaunch.
@MainActor
public final class UninstallerPaneProvider: NSObject, SuitePane {
    private let store = UninstallerStore()

    public var suiteABIVersion: Int { SuiteKitABI.current }
    public var paneID: String { "uninstaller" }
    public var paneTitle: String { "UNINSTALLER" }
    public var paneTintHex: String { "#E54B4B" }

    public func paneMenuBarImage() -> NSImage {
        UninstallerBrand.menuBarIcon
    }

    public func paneMakeView() -> NSView {
        NSHostingView(rootView: ContentView().environment(store))
    }

    public func paneStart() {
        store.bootstrap()
    }

    public func paneStop() {}

    public func paneDidOpen() { store.rescanApps() }
}

@_cdecl("suitePaneCreate")
public func suitePaneCreate() -> Unmanaged<AnyObject> {
    MainActor.assumeIsolated {
        Unmanaged.passRetained(UninstallerPaneProvider())
    }
}
