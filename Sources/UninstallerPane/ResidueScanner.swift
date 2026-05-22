import Foundation

/// Finds every "leftover" the OS keeps for a given app — the stuff
/// that survives dragging the bundle to the Trash and is the whole
/// reason this app exists. We probe the standard locations using
/// the bundle id + a couple of name-shaped fallbacks (some apps
/// store under their display name, others under the reverse-domain).
enum ResidueScanner {

    nonisolated static func scan(app: InstalledApp) -> [ResidueItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [ResidueItem] = []

        // The app bundle itself is always the first thing to trash.
        items.append(item(at: app.bundleURL, kind: .appBundle,
                          requiresAdmin: needsAdmin(app.bundleURL)))

        // Per-bundle-id paths under ~/Library. These are the ones we
        // can almost always trash without admin since the user owns
        // them. The list is curated: every entry has bitten me at
        // least once for "uninstalled, still polluting Spotlight".
        let bid = app.bundleID
        let name = app.displayName

        let userLibrary = home.appendingPathComponent("Library")
        let userProbes: [(String, ResidueItem.Kind, [String])] = [
            ("Preferences",                       .preferences,
                ["\(bid).plist"]),
            ("Application Support",               .applicationSupport,
                [bid, name]),
            ("Caches",                            .caches,
                [bid, name]),
            ("Saved Application State",           .savedState,
                ["\(bid).savedState"]),
            ("Logs",                              .logs,
                [bid, name]),
            ("Containers",                        .containers,
                [bid]),
            ("HTTPStorages",                      .httpStorages,
                [bid, "\(bid).binarycookies"]),
            ("WebKit",                            .webKit,
                [bid]),
            ("Cookies",                           .cookies,
                ["\(bid).binarycookies"]),
            ("LaunchAgents",                      .launchAgentUser,
                launchAgentCandidates(bid: bid)),
        ]
        for (subdir, kind, candidates) in userProbes {
            let base = userLibrary.appendingPathComponent(subdir)
            for candidate in candidates {
                let p = base.appendingPathComponent(candidate)
                if let it = tryItem(p, kind: kind, requiresAdmin: false) {
                    items.append(it)
                }
            }
        }

        // Group Containers — these are prefixed with a team id, so
        // we shallow-scan and match anything ending in `.<bundleid>`.
        let gc = userLibrary.appendingPathComponent("Group Containers")
        if let entries = try? fm.contentsOfDirectory(
            at: gc, includingPropertiesForKeys: nil) {
            for entry in entries
                where entry.lastPathComponent.hasSuffix(".\(bid)")
                   || entry.lastPathComponent.hasSuffix(".\(name)") {
                if let it = tryItem(entry, kind: .groupContainers,
                                    requiresAdmin: false) {
                    items.append(it)
                }
            }
        }

        // Crash reports — DiagnosticReports/<name>_<date>_<host>.crash
        // Shallow scan, name-prefix match.
        let dr = userLibrary
            .appendingPathComponent("Logs/DiagnosticReports")
        if let entries = try? fm.contentsOfDirectory(
            at: dr, includingPropertiesForKeys: nil) {
            for entry in entries
                where entry.lastPathComponent.hasPrefix("\(name)_")
                   || entry.lastPathComponent.hasPrefix("\(name)-") {
                if let it = tryItem(entry, kind: .crashReports,
                                    requiresAdmin: false) {
                    items.append(it)
                }
            }
        }

        // System-side launch agents / daemons — surface them so the
        // user knows they exist, but flag as requiresAdmin since we
        // can't touch them without privilege escalation.
        let systemProbes: [(String, ResidueItem.Kind)] = [
            ("/Library/LaunchAgents",   .launchAgentSystem),
            ("/Library/LaunchDaemons",  .launchDaemon),
        ]
        for (path, kind) in systemProbes {
            let dir = URL(fileURLWithPath: path)
            for candidate in launchAgentCandidates(bid: bid) {
                let p = dir.appendingPathComponent(candidate)
                if let it = tryItem(p, kind: kind, requiresAdmin: true) {
                    items.append(it)
                }
            }
        }

        // App receipt (BOM + plist). System-owned, requires admin to
        // delete; reported but skipped at trash time.
        let receipts = URL(fileURLWithPath: "/private/var/db/receipts")
        for ext in ["plist", "bom"] {
            let p = receipts.appendingPathComponent("\(bid).\(ext)")
            if let it = tryItem(p, kind: .receipt, requiresAdmin: true) {
                items.append(it)
            }
        }

        // De-dup any path we appended twice (e.g. apps that store
        // under both their bundle id AND their name in
        // Application Support).
        var seen = Set<String>()
        return items.filter { seen.insert($0.path.path).inserted }
    }

    // MARK: Helpers

    /// `~/Library/LaunchAgents/<bundleid>.plist` is the typical form,
    /// but lots of apps use a helper suffix (`.LoginHelper`, `.agent`)
    /// or drop the trailing `.plist` (rare). We probe a small set of
    /// reasonable shapes — extra misses are cheap.
    private nonisolated static func launchAgentCandidates(bid: String)
        -> [String]
    {
        var v = ["\(bid).plist"]
        for suffix in [".LoginHelper", ".LoginItem", ".Helper",
                       ".helper", ".agent", ".Updater"] {
            v.append("\(bid)\(suffix).plist")
        }
        return v
    }

    /// True if the path is *actually* admin-only — root-owned things
    /// under /Library or /private/var that need sudo to touch.
    ///
    /// `/Applications/<App>.app` is NOT admin-only even though it's
    /// outside the user's home: the bundle is user-owned, and
    /// `NSWorkspace.recycle` handles it via the standard App
    /// Management TCC prompt (which is consent, not privilege
    /// escalation). Earlier versions wrongly flagged it, which
    /// silently dropped the bundle from the trashable list and left
    /// the user thinking "I clicked Uninstall but the app's still
    /// in /Applications".
    private nonisolated static func needsAdmin(_ url: URL) -> Bool {
        let p = url.path
        if p.hasPrefix("/Applications/") { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if p.hasPrefix(home) { return false }
        // Everything else — /Library/LaunchAgents, /Library/Launch-
        // Daemons, /private/var/db/receipts — really does need sudo.
        return true
    }

    /// Stat the path; return nil if it doesn't exist. Sums recursive
    /// size for directories so the UI can show meaningful totals.
    private nonisolated static func tryItem(
        _ path: URL, kind: ResidueItem.Kind, requiresAdmin: Bool
    ) -> ResidueItem? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path.path, isDirectory: &isDir)
        else { return nil }
        return item(at: path, kind: kind, requiresAdmin: requiresAdmin)
    }

    /// Build a ResidueItem with size measured; assumes the path
    /// exists (we only call this after fileExists succeeded).
    private nonisolated static func item(
        at path: URL, kind: ResidueItem.Kind, requiresAdmin: Bool
    ) -> ResidueItem {
        let size: Int64
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path.path,
                                        isDirectory: &isDir)
        if isDir.boolValue {
            size = AppInventory.directorySize(path)
        } else {
            let attrs = try? FileManager.default
                .attributesOfItem(atPath: path.path)
            size = (attrs?[.size] as? Int64) ?? 0
        }
        return ResidueItem(path: path, kind: kind, size: size,
                           requiresAdmin: requiresAdmin)
    }
}
