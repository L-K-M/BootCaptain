# Claude guidance

Follow [AGENTS.md](AGENTS.md), especially its safety rules for privileged
helpers, host evidence, mutation qualification, signing, and hardware claims.

## Pull request review policy

When working on a pull request, evaluate each review comment on its merits:

- Apply real bugs or improvements.
- Decline requests that weaken a documented invariant, and record why.
- Refute incorrect claims with primary documentation, tests, or concrete code evidence.
- Do not apply a change merely to satisfy an automated reviewer.
- Do not revisit an already resolved point without new evidence.

Human review is mandatory for helper, XPC, mutation, authorization, entitlement,
signing, and release changes. GLM review is an additional signal, not approval.

The number of tokens used to edit files is best minimized, all else being equal. Therefore, when it will not affect the end result, try to surgically edit a file rather than rewrite the entire thing.
