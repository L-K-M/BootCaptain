import AppKit
import SwiftUI
import BootCaptainCore

/// Resolves and caches the best icon for a startup item (PLAN.md §5 display).
/// Resolution order: attributed app bundle → bundle identifier → owning .app of
/// the source/executable path → the executable's file icon. Falls back to nil,
/// in which case rows draw a mechanism symbol instead.
@MainActor
final class IconStore {
    static let shared = IconStore()

    private let cache = NSCache<NSString, NSImage>()
    private let missing = NSMutableSet()  // item IDs known to have no app icon

    func icon(for item: StartupItem) -> NSImage? {
        let key = item.id as NSString
        if let hit = cache.object(forKey: key) { return hit }
        if missing.contains(item.id) { return nil }

        if let image = resolve(item) {
            image.size = NSSize(width: 64, height: 64)
            cache.setObject(image, forKey: key)
            return image
        }
        missing.add(item.id)
        return nil
    }

    private func resolve(_ item: StartupItem) -> NSImage? {
        let workspace = NSWorkspace.shared
        let fm = FileManager.default

        // 1. Attribution already found the owning app bundle.
        if let appPath = item.attribution.iconPath, fm.fileExists(atPath: appPath) {
            return workspace.icon(forFile: appPath)
        }
        // 2. Bundle identifier → installed app.
        if let bundleID = item.attribution.bundleIdentifier,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return workspace.icon(forFile: url.path)
        }
        // 3. Owning .app of the source or executable path.
        for path in [item.sourcePath, item.recipe?.executablePath].compactMap({ $0 }) {
            if let appPath = Self.owningAppPath(of: path), fm.fileExists(atPath: appPath) {
                return workspace.icon(forFile: appPath)
            }
        }
        // 4. The classic login item's own path (may itself be an app).
        if let path = item.sourcePath, path.hasSuffix(".app"), fm.fileExists(atPath: path) {
            return workspace.icon(forFile: path)
        }
        // 5. The executable's generic file icon (only if it exists — a missing
        //    executable should keep the mechanism symbol + broken badge).
        if let exec = item.recipe?.executablePath, fm.fileExists(atPath: exec) {
            return workspace.icon(forFile: exec)
        }
        return nil
    }

    /// Walk up to the outermost `.app` component of a path.
    static func owningAppPath(of path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard let idx = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components[0...idx]))
    }
}
