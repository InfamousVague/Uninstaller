import Foundation
import AppKit

/// Executes an `UninstallPlan`. The default path is
/// `NSWorkspace.recycle`, which routes through Finder — so removing
/// `/Applications/<App>.app` triggers the standard App Management
/// TCC prompt (macOS 13+) instead of failing silently like
/// `FileManager.trashItem` does when the caller isn't trusted yet.
/// "Permanent delete" stays on `FileManager.removeItem`; that path
/// is for items the user already accepts they're losing.
enum Trasher {

    nonisolated static func execute(
        plan: UninstallPlan, trash: Bool
    ) async -> UninstallReport {
        let trashable = plan.items.filter { !$0.requiresAdmin }
        let skippedAdmin = plan.items.count - trashable.count
        var trashedCount = 0
        var trashedBytes: Int64 = 0
        var failures: [UninstallReport.Failure] = []

        if trash {
            // Single batched recycle so Finder shows ONE auth prompt
            // (instead of N) for things like /Applications/<App>.app,
            // and the user sees every item land in the Trash together.
            let urls = trashable.map(\.path)
            let outcome: ([URL: URL], Error?) =
                await withCheckedContinuation { cont in
                    NSWorkspace.shared.recycle(urls) { recycled, err in
                        cont.resume(returning: (recycled, err))
                    }
                }
            let (recycled, batchError) = outcome
            for item in trashable {
                if recycled[item.path] != nil {
                    trashedCount += 1
                    trashedBytes += item.size
                } else {
                    let msg = batchError?.localizedDescription
                        ?? "Couldn't be moved to Trash — likely "
                         + "needs your permission to modify this app."
                    failures.append(.init(
                        path: item.path, error: msg))
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
}
