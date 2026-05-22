# Uninstaller

Native macOS menu-bar uninstaller. Dragging `.app` to the Trash leaves
behind preferences, caches, sandbox containers, login items, and
crash logs. Uninstaller finds all of it for the chosen app and moves
the whole pile to Trash in one click.

Part of the MattsSoftware suite — same shape as Alfred / Port /
Sentry: a SuiteKit pane that runs standalone or merged into the
MattsSoftware launcher.

## What it scans

For every user-installed `.app` in `/Applications` or
`~/Applications`, it probes the standard residue locations under
`~/Library` and reports what it finds:

- `Preferences/<bundle-id>.plist`
- `Application Support/<bundle-id>` and `Application Support/<name>`
- `Caches/<bundle-id>`
- `Saved Application State/<bundle-id>.savedState`
- `Logs/<bundle-id>` and per-app crash reports in `DiagnosticReports/`
- `Containers/<bundle-id>` (sandboxed apps)
- `Group Containers/<team>.<bundle-id>` (shallow scan)
- `HTTPStorages/<bundle-id>`, `WebKit/<bundle-id>`,
  `Cookies/<bundle-id>.binarycookies`
- `LaunchAgents/<bundle-id>*.plist` (login items)

Apple's own apps (`com.apple.*`) are excluded — Uninstaller is for
user-installed stuff, not Safari.

## What it skips

System-side residue under `/Library/LaunchAgents`,
`/Library/LaunchDaemons`, and `/private/var/db/receipts` is surfaced
in the list with an `admin` badge but never touched — removing those
needs privilege escalation, which is out of scope for v1.

## Stack

Swift + SwiftUI in a transient `NSPopover` off an `NSStatusItem`,
`.accessory` activation policy (no Dock icon). Two products:

- `UninstallerPane` (dynamic library) — store, inventory, scanner,
  trasher, UI. The MattsSoftware launcher `dlopen`s this so it can
  host the same code as a merged pane.
- `Uninstaller` (executable) — thin `@main` shim that wires the pane
  into a standalone `NSStatusItem` / `NSPopover`. Defers to the
  launcher via `SuiteGuard.exitIfDeferring("uninstaller")` when merged.

## Building

```sh
swift build                  # dev build
swift run                    # menu-bar item appears
bash scripts/make-app.sh     # Developer-ID signed + notarized .app + .dmg
```
