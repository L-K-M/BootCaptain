import Foundation

/// Builds the launch recipe from a launchd job (PLAN.md §4 "Build the launch
/// recipe before applying that rule"). Resolves argv[0], detects the
/// interpreter trap, and marks unresolved exec chains so they fail closed.
public enum RecipeResolver {
    /// Apple interpreters whose signature describes the interpreter, not the
    /// payload. Trust must come from the script argument.
    static let interpreters: Set<String> = [
        "bash", "sh", "zsh", "dash", "ksh", "tcsh", "csh",
        "python", "python2", "python3", "perl", "ruby", "php", "node",
        "osascript", "env",
    ]

    /// Directories searched for a bare (slash-less) argv[0] per launchd's
    /// `_PATH_STDPATH`. Presented as candidate prefixes; the collector confirms
    /// existence on disk.
    public static let pathStdDirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    /// - Parameter bundleRoot: the owning `.app` path, used to resolve
    ///   `BundleProgram` relative paths for SMAppService items.
    public static func resolve(_ job: LaunchdJob, bundleRoot: String? = nil) -> LaunchRecipe {
        var recipe = LaunchRecipe()

        // 1. Determine the executable and argv.
        if let program = job.program {
            recipe.executablePath = program
            recipe.arguments = job.programArguments.isEmpty ? [program] : job.programArguments
        } else if let bundleProgram = job.bundleProgram {
            if let root = bundleRoot {
                recipe.executablePath = (root as NSString)
                    .appendingPathComponent(bundleProgram)
            } else {
                recipe.executablePath = bundleProgram
                recipe.isUnresolved = true   // cannot resolve without the bundle
            }
            recipe.arguments = job.programArguments
        } else if let first = job.programArguments.first {
            recipe.arguments = job.programArguments
            if first.contains("/") {
                recipe.executablePath = first
            } else {
                // Bare command name: PATH lookup happens at spawn; mark as a
                // candidate rather than a resolved absolute path.
                recipe.executablePath = nil
                recipe.isUnresolved = true
            }
        } else {
            // Neither Program nor ProgramArguments: not a runnable recipe.
            recipe.isUnresolved = true
            return recipe
        }

        // 2. Shell inline-code / dynamic wrapper forms cannot be statically
        //    resolved to a payload; fail closed for mutation.
        if let exec = recipe.executablePath {
            let name = (exec as NSString).lastPathComponent
            if Self.interpreters.contains(name) {
                recipe.isInterpreter = true
                recipe.scriptPath = firstScriptArgument(
                    interpreter: name, args: recipe.arguments)
                if recipe.scriptPath == nil { recipe.isUnresolved = true }
            }
        }

        return recipe
    }

    /// Finds the script path in an interpreter invocation, skipping inline-code
    /// flags (`-c`, `-e`) whose payload is not a file we can attribute.
    static func firstScriptArgument(interpreter: String, args: [String]) -> String? {
        guard args.count > 1 else { return nil }
        let inlineFlags: Set<String> = ["-c", "-e", "--eval", "--command"]
        var i = 1
        while i < args.count {
            let a = args[i]
            if inlineFlags.contains(a) { return nil } // inline code, no file
            if a == "env" || a.hasPrefix("-") { i += 1; continue }
            // `osascript -e '...'` handled above; a plain path is the script.
            if a.contains("/") || a.hasSuffix(".sh") || a.hasSuffix(".py")
                || a.hasSuffix(".pl") || a.hasSuffix(".rb") || a.hasSuffix(".scpt") {
                return a
            }
            i += 1
        }
        return nil
    }
}
