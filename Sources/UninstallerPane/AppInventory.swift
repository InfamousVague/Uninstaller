import Foundation
import AppKit

/// Enumerates installed `.app` bundles in the standard install
/// locations and returns the metadata needed for the picker:
/// path / bundle id / display name / version / on-disk size.
///
/// Filters out Apple's own system apps (anything whose bundle id
/// starts with `com.apple.`) — the Uninstaller is for *user*-
/// installed apps, never `Safari.app` or `Mail.app`.
enum AppInventory {

    /// Where we look. Order matters only for de-dup (a /Applications
    /// install wins over a ~/Applications copy if both exist; rare).
    static let roots: [URL] = {
        var us: [URL] = [URL(fileURLWithPath: "/Applications")]
        let home = FileManager.default.homeDirectoryForCurrentUser
        us.append(home.appendingPathComponent("Applications"))
        // Setapp etc. ship inside ~/Applications/Setapp; flatten one
        // level so the picker still finds them.
        return us
    }()

    nonisolated static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [InstalledApp] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            // Walk one level deep at the root, plus one extra level
            // for sub-folders like Setapp/, Utilities/, JetBrains
            // Toolbox/, etc. (any nested layout would just be missed
            // upstream by Spotlight too).
            for url in (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? [] {
                if url.pathExtension == "app" {
                    if let app = read(url), !seen.contains(app.bundleID) {
                        seen.insert(app.bundleID)
                        out.append(app)
                    }
                } else {
                    // Look one level deeper for grouped install dirs.
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: url.path, isDirectory: &isDir)
                    guard isDir.boolValue else { continue }
                    for inner in (try? fm.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: nil)) ?? [] {
                        guard inner.pathExtension == "app",
                              let app = read(inner),
                              !seen.contains(app.bundleID) else { continue }
                        seen.insert(app.bundleID)
                        out.append(app)
                    }
                }
            }
        }
        return out
    }

    /// Read just enough metadata from one `.app` bundle to be useful.
    /// Returns nil for Apple-bundled apps and anything missing a
    /// bundle id (broken / dev-build .app trees).
    private nonisolated static func read(_ url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let bid = bundle.bundleIdentifier
        else { return nil }
        // Skip Apple's own apps — the user isn't uninstalling Safari
        // from here, and trying would either silently fail (SIP) or
        // cause real damage.
        if bid.hasPrefix("com.apple.") { return nil }
        let name = (bundle.object(forInfoDictionaryKey:
                       "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName")
                    as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle.object(forInfoDictionaryKey:
                          "CFBundleShortVersionString") as? String
        let size = directorySize(url)
        return InstalledApp(
            bundleURL: url, bundleID: bid,
            displayName: name, version: version, appSize: size)
    }

    /// Sum of all regular-file sizes under `url`. Used for the list
    /// cell's "App bundle: 142 MB" and totals — gives the user a
    /// sense of what they're reclaiming before they uninstall.
    nonisolated static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let e = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) {
            for case let item as URL in e {
                let vals = try? item.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey])
                if vals?.isRegularFile == true {
                    total += Int64(vals?.fileSize ?? 0)
                }
            }
        }
        return total
    }
}
