import Foundation

/// Executes an `UninstallPlan` — sends every user-trashable item to
/// the macOS Trash (or, when `trash` is false, deletes outright).
/// Admin-only items are skipped and surfaced in the report so the
/// user knows what's left over and can decide if it matters.
enum Trasher {

    nonisolated static func execute(
        plan: UninstallPlan, trash: Bool
    ) -> UninstallReport {
        let fm = FileManager.default
        var trashedCount = 0
        var trashedBytes: Int64 = 0
        var skippedAdmin = 0
        var failures: [UninstallReport.Failure] = []

        for item in plan.items {
            if item.requiresAdmin {
                skippedAdmin += 1
                continue
            }
            do {
                if trash {
                    var resulting: NSURL?
                    try fm.trashItem(at: item.path,
                                     resultingItemURL: &resulting)
                } else {
                    try fm.removeItem(at: item.path)
                }
                trashedCount += 1
                trashedBytes += item.size
            } catch {
                failures.append(.init(
                    path: item.path,
                    error: error.localizedDescription))
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
