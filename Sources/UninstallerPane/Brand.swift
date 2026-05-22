import AppKit
import ObjectiveC
import SwiftUI

/// Glyph + resource resolver for the Uninstaller pane. Mirrors the
/// Alfred / Sentry pattern so resources resolve both inside a
/// standalone .app (PNGs flattened into Contents/Resources) AND
/// out of a dylib `dlopen`'d by the launcher (where Bundle.module
/// fatalErrors and Bundle.main is the launcher's bundle, not ours).
enum UninstallerBrand {
    private final class BundleToken {}

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext) {
            return u
        }
        if let img = class_getImageName(BundleToken.self) {
            let dylib = URL(fileURLWithPath: String(cString: img))
            let fw = dylib.deletingLastPathComponent()
            if let b = Bundle(url: fw.appendingPathComponent(
                    "Uninstaller_UninstallerPane.bundle")),
               let u = b.url(forResource: name, withExtension: ext) {
                return u
            }
            let res = fw.deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: res.path) {
                return res
            }
            let same = fw.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: same.path) {
                return same
            }
        }
        return Bundle(for: BundleToken.self)
            .url(forResource: name, withExtension: ext)
    }

    /// Menu-bar template glyph — a trash can with a downward arrow.
    /// Falls back to `trash.fill` if the bundled PNG can't be found.
    static let menuBarIcon: NSImage = {
        let image: NSImage
        if let url = resourceURL("MenuBarIcon", "png"),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(systemSymbolName: "trash.fill",
                            accessibilityDescription: "Uninstaller")
                ?? NSImage()
        }
        let height: CGFloat = 18
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }()

    /// Panel-header glyph (tinted by the accent in ContentView).
    static let trayGlyph: NSImage = {
        let image: NSImage
        if let url = resourceURL("MenuBarIcon", "png"),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(systemSymbolName: "trash.fill",
                            accessibilityDescription: "Uninstaller")
                ?? NSImage()
        }
        image.isTemplate = true
        return image
    }()
}

extension Color {
    /// Uninstaller's brand accent — a warm red that reads as a
    /// "destructive but considered" action. Used for the primary
    /// uninstall button + the panel header tint.
    static let uninstallerAccent = Color(
        red: 0xE5/255.0, green: 0x4B/255.0, blue: 0x4B/255.0)
}
