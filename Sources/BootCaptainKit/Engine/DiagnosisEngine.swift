import Foundation
import BootCaptainCore

/// The boot/login evidence audit (PLAN.md §7 flagship). Correlates the unified
/// log, launchctl counters (already on the item state), and crash reports into a
/// per-item `Diagnosis` using the safe-state model. Absence of telemetry never
/// becomes "never attempted".
public struct DiagnosisEngine: Sendable {
    let log: UnifiedLogAdapter
    let reports: DiagnosticReportsAdapter

    public init(
        log: UnifiedLogAdapter = UnifiedLogAdapter(),
        reports: DiagnosticReportsAdapter = DiagnosticReportsAdapter()
    ) {
        self.log = log
        self.reports = reports
    }

    public func diagnose(items: [StartupItem], ctx: ScanContext) -> [StartupItem] {
        // 1. Fetch evidence once.
        let logOutcome = log.fetch(.init(), runner: ctx.runner)
        var crashByProc: [String: [CrashReport]] = [:]
        for home in ctx.userHomes.isEmpty ? ["/var/root"] : ctx.userHomes {
            for report in reports.reports(userHome: home, fileManager: ctx.fileManager) {
                if let name = report.procName {
                    crashByProc[name, default: []].append(report)
                }
            }
        }

        // 2. Pre-index log messages by process for cheap lookup.
        var logByProcess: [String: [LogRecord]] = [:]
        for record in logOutcome.records {
            if let proc = record.process { logByProcess[proc, default: []].append(record) }
        }

        // 3. Diagnose each item.
        return items.map { item in
            var item = item
            item.diagnosis = diagnoseOne(
                item, logByProcess: logByProcess, crashByProc: crashByProc,
                logUsable: logOutcome.querySucceeded, logNote: logOutcome.coverageNote)
            // Re-derive health now that runtime evidence exists.
            if item.diagnosis?.state == .failureEvidence, item.health == .ok {
                item.health = .failing
            }
            return item
        }
    }

    func diagnoseOne(
        _ item: StartupItem, logByProcess: [String: [LogRecord]],
        crashByProc: [String: [CrashReport]], logUsable: Bool, logNote: String
    ) -> Diagnosis {
        var evidence: [EvidenceItem] = []
        var gaps: [String] = []
        if !logUsable { gaps.append(logNote) }

        let procName = item.recipe?.executablePath.map { ($0 as NSString).lastPathComponent }
            ?? item.label

        // Log evidence keyed by process name or label token.
        if let procName {
            for (proc, records) in logByProcess where proc.contains(procName) || procName.contains(proc) {
                for record in records.prefix(5) {
                    guard let message = record.eventMessage else { continue }
                    if let signal = UnifiedLogMatchers.classify(message) {
                        evidence.append(EvidenceItem(
                            origin: .unifiedLog,
                            summary: humanSignal(signal),
                            rawObservation: message,
                            confidence: .medium,
                            timestamp: nil))
                    }
                }
            }
        }

        // Crash reports.
        if let procName, let crashes = crashByProc[procName] ?? crashByProc[item.label ?? ""] {
            for crash in crashes.prefix(3) where crash.isCrash {
                var summary = "Crash reported"
                if let reason = crash.terminationReason { summary += ": \(reason)" }
                evidence.append(EvidenceItem(
                    origin: .crashReport, summary: summary,
                    rawObservation: crash.terminationNamespace,
                    confidence: crash.parentIsLaunchd ? .medium : .low))
            }
        }

        // launchctl counters already on state: nonzero exit / running.
        if item.state.running == .yes {
            evidence.append(EvidenceItem(origin: .processState,
                summary: "Process is running now", confidence: .high))
        }

        let input = SafeStateDeriver.Inputs(
            state: item.state, evidence: evidence,
            hasUsableCoverage: logUsable || !crashByProc.isEmpty,
            coverageGaps: gaps)
        return SafeStateDeriver.derive(input)
    }

    func humanSignal(_ signal: LogMatcher.Signal) -> String {
        switch signal {
        case .spawnFailedMissingExecutable: return "Spawn failed — executable missing"
        case .serviceCouldNotInitialize: return "Service could not initialize"
        case .exitedAbnormalCode: return "Exited with an abnormal code"
        case .throttledRespawn: return "Restart loop (throttled respawn)"
        case .bootstrapDisabled: return "Bootstrap refused — service disabled"
        }
    }
}
