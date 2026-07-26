import Foundation
import BootCaptainCore

/// Cheap, local per-item health facts (PLAN.md §7.4). No subprocess; pure
/// filesystem checks so they're fast and safe on the hot path.
public struct StaticHealthChecker: Sendable {
    let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func check(_ item: StartupItem) -> HealthDeriver.Inputs {
        var inputs = HealthDeriver.Inputs()

        // Plist parsed already (the collector marks broken items).
        inputs.plistParsed = item.health == .broken && item.recipe == nil ? .no : .yes

        guard let recipe = item.recipe else { return inputs }
        if recipe.isUnresolved {
            // Can't judge existence of a PATH-resolved bare command statically.
            return inputs
        }
        if let exec = recipe.executablePath {
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: exec, isDirectory: &isDir)
            inputs.executableExists = Tristate(exists && !isDir.boolValue)
            if exists {
                inputs.executableIsRunnable = Tristate(fileManager.isExecutableFile(atPath: exec))
            } else {
                inputs.executableIsRunnable = .no
            }
            // DMG / unmounted volume path.
            if exec.hasPrefix("/Volumes/") {
                let volume = "/Volumes/" + (exec.dropFirst("/Volumes/".count).split(separator: "/").first.map(String.init) ?? "")
                inputs.pointsToMissingVolume = !fileManager.fileExists(atPath: volume)
            }
        }

        // Signature validity from collected signing (if any).
        if let sig = item.signing.first {
            inputs.signatureValid = sig.isValid
        }

        inputs.diagnosis = item.diagnosis?.state
        return inputs
    }
}
