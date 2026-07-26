# Privacy

BootCaptain is designed to process startup and diagnostic information locally.
It has no analytics, telemetry, account system, project-operated backend, or
automatic upload path.

## Data the app may inspect

Depending on macOS version and granted permissions, scans may observe:

- launchd labels, domains, plists, executable paths, and live service state;
- login items, BTM diagnostics, cron entries, extensions, and profiles;
- code-signing identity and package/receipt attribution;
- unified-log excerpts and crash-report metadata used for diagnosis;
- usernames and paths embedded in commands, configuration, or diagnostic text.

This information can reveal installed software, organization management,
account names, document/server paths, command arguments, and other sensitive
host details. Root access is not equivalent to Full Disk Access, and a denied
collector is reported as a coverage gap rather than bypassed.

## Storage and exports

The current prototype does not operate a cloud service. Export is user-initiated
and attempts to redact home-directory paths, but redaction is not a guarantee:
usernames, filenames, volume names, command arguments, and identifiers may still
appear in free-form fields.

Review every export manually before sharing it. Never attach an unsanitized
export, BTM store, crontab, log archive, or crash report to a public issue.

Future journals and privileged state must be root-owned, local, restrictive,
versioned, and limited to the exact data required for recovery. They do not
exist as a qualified production feature yet.

## Network access

BootCaptain currently requires no application network access. GitHub Actions,
Dependabot, and GLM review operate on repository source in GitHub's environment;
they do not receive local scan data unless someone explicitly commits or uploads
it, which repository policy forbids.
