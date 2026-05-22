import SwiftUI
import AppKit

/// Uninstaller's popover UI: header, search-as-you-type app picker,
/// then the selected app's residue breakdown with a single big
/// "Move to Trash" action. Matches the visual size of the other
/// suite panes (340-wide, ~540 tall).
struct ContentView: View {
    @Environment(UninstallerStore.self) private var store

    var body: some View {
        @Bindable var s = store
        VStack(spacing: 0) {
            header
            Divider()
            if case let .done(report) = s.phase {
                reportView(report)
            } else if let plan = s.plan {
                planView(plan)
            } else {
                pickerView
            }
            footer
        }
        .frame(width: 340, height: 540)
        .onAppear { store.bootstrap() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: UninstallerBrand.trayGlyph)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Color.uninstallerAccent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Uninstaller")
                    .font(.system(size: 13, weight: .semibold))
                Text("Apps + their crumbs, in one click.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.plan != nil {
                Button("Back") { store.dismissReport()
                                 // explicit back: clear selection
                                 store.rescanApps() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    // MARK: Picker (default view)

    private var pickerView: some View {
        @Bindable var s = store
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("Search installed apps…", text: $s.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if store.phase == .scanningApps && store.apps.isEmpty {
                spinner("Scanning /Applications…")
            } else if store.visibleApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.visibleApps) { app in
                            appRow(app)
                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        Button {
            store.select(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let v = app.version, !v.isEmpty {
                            Text(v)
                        }
                        Text("·")
                        Text(byteString(app.appSize))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(store.query.isEmpty
                 ? "No installed apps found."
                 : "No matches for \"\(store.query)\".")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func spinner(_ label: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Plan (selected app)

    private func planView(_ plan: UninstallPlan) -> some View {
        VStack(spacing: 0) {
            // Selected app card
            HStack(spacing: 10) {
                Image(nsImage: plan.app.icon)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.app.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(plan.app.bundleID)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Total reclaimable
            HStack {
                Text("Reclaimable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(byteString(plan.totalSize))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.uninstallerAccent)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Residue list
            if store.phase == .scanningResidue {
                spinner("Looking for leftover files…")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.items) { residueRow($0) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func residueRow(_ r: ResidueItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForKind(r.kind))
                .font(.system(size: 11))
                .foregroundStyle(r.requiresAdmin
                                 ? Color.orange : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.kind.rawValue)
                    .font(.system(size: 11, weight: .medium))
                Text(r.path.path)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(byteString(r.size))
                    .font(.system(size: 10, weight: .medium))
                if r.requiresAdmin {
                    Text("admin")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func iconForKind(_ k: ResidueItem.Kind) -> String {
        switch k {
        case .appBundle:           return "app.fill"
        case .preferences:         return "gearshape"
        case .applicationSupport:  return "folder.fill"
        case .caches:              return "tray.full"
        case .savedState:          return "doc.on.doc"
        case .logs:                return "doc.text"
        case .containers,
             .groupContainers:     return "shippingbox"
        case .httpStorages:        return "network"
        case .webKit:              return "safari"
        case .cookies:             return "circle.dotted"
        case .launchAgentUser,
             .launchAgentSystem:   return "play.circle"
        case .launchDaemon:        return "bolt.circle"
        case .receipt:             return "doc.plaintext"
        case .crashReports:        return "exclamationmark.triangle"
        }
    }

    // MARK: Report (after uninstall)

    private func reportView(_ r: UninstallReport) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: r.ok
                  ? "checkmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(r.ok ? Color.green : .orange)
            Text(r.ok ? "Uninstalled \(r.appName)"
                     : "Uninstalled with warnings")
                .font(.system(size: 14, weight: .semibold))
            Text("\(r.trashedCount) items · "
                 + byteString(r.trashedBytes)
                 + " reclaimed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if r.skippedAdmin > 0 {
                Text("\(r.skippedAdmin) system-owned items skipped "
                     + "(admin required).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if !r.failures.isEmpty {
                Text("\(r.failures.count) item(s) couldn't be removed.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Done") { store.dismissReport() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.uninstallerAccent)
                .padding(.bottom, 12)
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        if let plan = store.plan {
            @Bindable var s = store
            Divider()
            VStack(spacing: 6) {
                if plan.hasAdminOnly {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                        Text("Some system files are skipped — they "
                             + "need admin access to remove.")
                            .multilineTextAlignment(.leading)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Toggle(isOn: $s.trashInsteadOfPermanent) {
                        Text(s.trashInsteadOfPermanent
                             ? "Move to Trash (recoverable)"
                             : "Delete permanently")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Spacer()
                }
                Button {
                    store.uninstallSelected()
                } label: {
                    HStack {
                        if store.phase == .working {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text(store.phase == .working
                             ? "Removing…"
                             : "Uninstall \(plan.app.displayName)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.uninstallerAccent)
                .disabled(store.phase == .working)
            }
            .padding(12)
        }
    }

    // MARK: Format

    private func byteString(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }
}
