import Foundation
import AppKit

/// Executes an `UninstallPlan`. Two paths because macOS gates them
/// behind different TCC services:
///
///   - Residue under `~/Library/...` — user-owned, no TCC: standard
///     `NSWorkspace.recycle` handles them cleanly.
///   - The bundle at `/Applications/<App>.app` — gated by App
///     Management (`kTCCServiceSystemPolicyAppBundles`). In practice
///     `NSWorkspace.recycle` here ends up in a "silently decided"
///     state on machines where any earlier attempt was implicitly
///     denied (no prompt) and never recovers. So we instead drive
///     Finder via an Apple Event ("tell application Finder to
///     delete …"), which uses `kTCCServiceAppleEvents` — a *different*
///     service that prompts fresh on first use. Finder itself has
///     the right permissions to do the move.
///
///   - "Permanent delete" toggle still uses `FileManager.removeItem`;
///     that path is for items the user already accepts they're losing.
enum Trasher {

    nonisolated static func execute(
        plan: UninstallPlan, trash: Bool
    ) async -> UninstallReport {
        let trashable = plan.items.filter { !$0.requiresAdmin }
        let skippedAdmin = plan.items.count - trashable.count
        var trashedCount = 0
        var trashedBytes: Int64 = 0
        var failures: [UninstallReport.Failure] = []

        // Split the trashable set: the .app bundle goes via Finder
        // (AppleEvents TCC), everything else via recycle (no TCC).
        let bundleItems = trashable.filter {
            $0.path.path.hasPrefix("/Applications/")
        }
        let residueItems = trashable.filter {
            !$0.path.path.hasPrefix("/Applications/")
        }

        if trash {
            // 1) Residue first via the standard recycle path. These
            //    are all user-owned so no TCC prompt.
            if !residueItems.isEmpty {
                let urls = residueItems.map(\.path)
                let outcome: ([URL: URL], Error?) =
                    await withCheckedContinuation { cont in
                        NSWorkspace.shared.recycle(urls) { recycled, err in
                            cont.resume(returning: (recycled, err))
                        }
                    }
                let (recycled, batchError) = outcome
                for item in residueItems {
                    if recycled[item.path] != nil {
                        trashedCount += 1
                        trashedBytes += item.size
                    } else {
                        failures.append(.init(
                            path: item.path,
                            error: batchError?.localizedDescription
                                ?? "Couldn't be moved to Trash."))
                    }
                }
            }

            // 2) /Applications/<App>.app via Finder. One AppleScript
            //    per bundle so each one's error surfaces cleanly.
            for item in bundleItems {
                let res = await deleteViaFinder(item.path)
                switch res {
                case .success:
                    trashedCount += 1
                    trashedBytes += item.size
                case .failure(let error):
                    failures.append(.init(
                        path: item.path,
                        error: error.localizedDescription))
                }
            }
        } else {
            let fm = FileManager.default
            for item in trashable {
                do {
                    try fm.removeItem(at: item.path)
                    trashedCount += 1
                    trashedBytes += item.size
                } catch {
                    failures.append(.init(
                        path: item.path,
                        error: error.localizedDescription))
                }
            }
        }

        return UninstallReport(
            appName: plan.app.displayName,
            trashedCount: trashedCount,
            trashedBytes: trashedBytes,
            skippedAdmin: skippedAdmin,
            failures: failures)
    }

    /// `tell application "Finder" to delete (POSIX file "/path" as alias)`.
    /// The Apple Event is what triggers the "Uninstaller would like
    /// to control Finder" prompt the first time — and Finder itself
    /// has the permissions to actually move the bundle to Trash.
    ///
    /// Belt-and-braces: we capture the script's return value, log it
    /// to os_log so a user can read the trail in Console, AND
    /// post-check the original path. If the bundle is still on disk
    /// after the script reports success, we treat it as a failure —
    /// because Finder can silently no-op in some edge cases (e.g.
    /// SIP-protected paths, or a stale TCC grant that 'passes' the
    /// gate but doesn't actually authorise the move).
    nonisolated private static func deleteViaFinder(_ url: URL)
        async -> Result<Void, Error>
    {
        await withCheckedContinuation { cont in
            // NSAppleScript must run on the main thread.
            DispatchQueue.main.async {
                let escaped = url.path
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let source = """
                tell application "Finder"
                    delete (POSIX file "\(escaped)" as alias)
                end tell
                """
                guard let script = NSAppleScript(source: source) else {
                    NSLog("[Uninstaller] couldn't build AppleScript "
                        + "for \(url.path)")
                    cont.resume(returning: .failure(NSError(
                        domain: "Uninstaller.Trasher", code: -1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Couldn't construct Finder AppleScript."])))
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                NSLog("[Uninstaller] Finder delete %@: err=%@ result=%@",
                      url.path,
                      String(describing: error),
                      result.stringValue ?? "<nil>")
                if let error = error {
                    let code = (error["NSAppleScriptErrorNumber"]
                                as? Int) ?? -1
                    let msg = (error["NSAppleScriptErrorBriefMessage"]
                               as? String)
                        ?? (error["NSAppleScriptErrorMessage"]
                            as? String)
                        ?? "Finder couldn't move the app to Trash."
                    cont.resume(returning: .failure(NSError(
                        domain: "Uninstaller.Trasher", code: code,
                        userInfo: [NSLocalizedDescriptionKey:
                            "\(msg) (\(url.lastPathComponent))"])))
                    return
                }
                // Post-check: if the bundle is still on disk Finder
                // silently no-op'd. Surface that as a failure so the
                // user isn't left wondering why their app is still
                // there after a "success" toast.
                if FileManager.default.fileExists(atPath: url.path) {
                    NSLog("[Uninstaller] Finder reported success but "
                        + "%@ is still on disk", url.path)
                    cont.resume(returning: .failure(NSError(
                        domain: "Uninstaller.Trasher", code: -2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Finder reported success but \(url.lastPathComponent) "
                            + "is still on disk. Open System Settings → "
                            + "Privacy & Security → Automation, find this "
                            + "app, and make sure 'Finder' is ticked."])))
                    return
                }
                cont.resume(returning: .success(()))
            }
        }
    }
}
