import Foundation
import BootCaptainCore
import BootCaptainKit

// A dependency-free CLI front end for BootCaptain. The heavy lifting lives in
// BootCaptainKit; this is a thin, scriptable surface (scan / audit / export /
// coverage) that also doubles as the reference driver for the engine.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
let flags = Set(arguments.dropFirst().filter { $0.hasPrefix("--") })

func optionValue(_ name: String) -> String? {
    guard let idx = arguments.firstIndex(of: name), idx + 1 < arguments.count else { return nil }
    return arguments[idx + 1]
}

func now() -> Double { Date().timeIntervalSince1970 }

func runScan(diagnose: Bool) -> ScanResult {
    let ctx = SystemEnvironment.makeContext()
    // Qualify the module: a bare `Scanner` collides with Foundation.Scanner.
    let scanner = BootCaptainKit.Scanner()
    var result = scanner.scan(ctx, now: now())
    if diagnose {
        let items = DiagnosisEngine().diagnose(items: result.items, ctx: ctx)
        result = ScanResult(items: items, coverage: result.coverage, generatedAt: result.generatedAt)
    }
    return result
}

// MARK: rendering

func trustBadge(_ t: TrustClass) -> String {
    switch t {
    case .applePlatform, .appleDistributed: return "[macOS]"
    case .managed: return "[managed]"
    case .developerIDNotarized, .developerIDUnnotarized, .appStore: return "[dev-id]"
    case .adhoc, .unsigned: return "[unsigned]"
    case .brokenOrConflicting: return "[!broken]"
    case .unknown: return "[?]"
    }
}

func healthMark(_ h: HealthState) -> String {
    switch h {
    case .ok: return "ok"
    case .broken: return "BROKEN"
    case .possiblyOrphaned: return "orphan?"
    case .failing: return "FAILING"
    case .unknown: return "-"
    }
}

func printTable(_ result: ScanResult, showEvidence: Bool) {
    let byTier = Dictionary(grouping: result.items, by: { $0.mechanism.tier })
    let order: [Mechanism.Tier] = [.core, .legacy, .advanced]
    let tierTitles: [Mechanism.Tier: String] = [
        .core: "CORE STARTUP / BACKGROUND",
        .legacy: "LEGACY / LINGERING",
        .advanced: "ADVANCED EXECUTION SURFACE",
    ]
    for tier in order {
        guard let items = byTier[tier], !items.isEmpty else { continue }
        print("\n\u{001B}[1m\(tierTitles[tier] ?? "")\u{001B}[0m  (\(items.count))")
        for item in items {
            let name = item.displayName.padding(toLength: 34, withPad: " ", startingAt: 0)
            let mech = item.mechanism.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)
            var line = "  \(name) \(mech) \(trustBadge(item.trust))"
            let health = healthMark(item.health)
            if health != "-" { line += " \(health)" }
            if item.actionClass == .reversibleMutation { line += " ✓disableable" }
            if showEvidence, let d = item.diagnosis {
                line += "  →\(d.state.displayName)"
            }
            print(line)
        }
    }
    print("\n\u{001B}[2m\(result.coverage.bannerSummary)\u{001B}[0m")
}

// MARK: commands

switch command {
case "scan":
    let result = runScan(diagnose: false)
    if flags.contains("--json") {
        let data = try ScanExport().json(result, redact: !flags.contains("--no-redact"))
        print(String(data: data, encoding: .utf8) ?? "")
    } else {
        print("BootCaptain — \(result.items.count) startup items")
        printTable(result, showEvidence: false)
    }

case "audit":
    let result = runScan(diagnose: true)
    if flags.contains("--json") {
        let data = try ScanExport().json(result, redact: !flags.contains("--no-redact"))
        print(String(data: data, encoding: .utf8) ?? "")
    } else {
        print("BootCaptain boot/login evidence audit")
        printTable(result, showEvidence: true)
        let failing = result.items.filter { $0.diagnosis?.state == .failureEvidence }
        if !failing.isEmpty {
            print("\n\u{001B}[1;31mItems with failure evidence:\u{001B}[0m")
            for item in failing {
                print("  • \(item.displayName)")
                for e in item.diagnosis?.evidence ?? [] {
                    print("      - \(e.summary)" + (e.rawObservation.map { " (\($0))" } ?? ""))
                }
            }
        }
    }

case "export":
    let result = runScan(diagnose: flags.contains("--audit"))
    let data = try ScanExport().json(result, redact: !flags.contains("--no-redact"))
    if let out = optionValue("--out") {
        try data.write(to: URL(fileURLWithPath: out))
        FileHandle.standardError.write("Wrote \(data.count) bytes to \(out)\n".data(using: .utf8)!)
    } else {
        print(String(data: data, encoding: .utf8) ?? "")
    }

case "coverage":
    let result = runScan(diagnose: false)
    print("Coverage report (\(result.coverage.collectors.count) collectors):")
    for c in result.coverage.collectors.sorted(by: { $0.collector < $1.collector }) {
        let mark = c.isGap ? "!" : "+"
        var line = "  \(mark) \(c.collector.padding(toLength: 28, withPad: " ", startingAt: 0)) \(c.status.rawValue)"
        if c.itemCount > 0 { line += " (\(c.itemCount))" }
        if let detail = c.detail { line += " — \(detail)" }
        print(line)
    }
    print("\n\(result.coverage.bannerSummary)")

default:
    print("""
    bootcaptain \(BootCaptainCoreInfo.version) — macOS startup manager (CLI)

    USAGE:
      bootcaptain scan               List everything that can run at startup/login
      bootcaptain audit              Scan + correlate boot/login failure evidence
      bootcaptain export [--out F]   Emit the scan as JSON (redacted by default)
      bootcaptain coverage           Show per-collector coverage and gaps

    FLAGS:
      --json         Machine-readable output (scan/audit)
      --no-redact    Do not redact user paths in exports
      --audit        Include diagnosis in `export`

    Coverage depends on the current user's permissions; `coverage` reports known
    gaps. For privacy-protected sources, grant Full Disk Access to the terminal
    that launches this CLI. Do not run under sudo: it changes the user and
    launchd domains being inspected and does not grant Full Disk Access. On
    non-macOS this reports an empty scan by design.
    """)
}
