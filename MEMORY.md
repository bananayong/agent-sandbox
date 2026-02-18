# MEMORY.md

Long-lived technical decisions for this repository.
Keep only stable guidance with operational impact.

## Decision Log

### 2026-02-18 — Runtime Safety Defaults
- Context: network-sensitive agent CLIs frequently fail on unstable TLS/DNS paths.
- Decision: enforce runtime defaults (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `DISABLE_ERROR_REPORTING=1`, `DISABLE_TELEMETRY=1`, `DISABLE_AUTOUPDATER=1`, Node TLS compat with IPv4-first) as baseline behavior.
- Impact: lower startup/runtime flakiness and predictable network posture across launch paths.

### 2026-02-18 — Container Network Contract
- Context: local/VPN/WSL environments showed MTU and resolver-induced socket instability.
- Decision: standardize custom bridge MTU(`1280`), IPv6-off, host DNS override support (`--dns` / `AGENT_SANDBOX_DNS_SERVERS`), and `host.docker.internal` mapping where supported.
- Impact: fewer intermittent socket/TLS issues and consistent troubleshooting path.

### 2026-02-18 — Shared Skills Source of Truth
- Context: external skill bundles drifted without a single authoritative manifest.
- Decision: use `skills/external-manifest.txt` as source-of-truth; vendoring, smoke-test, and weekly refresh workflow all bind to this manifest.
- Impact: reproducible bundle updates and lower risk of accidental skill drift.

### 2026-02-18 — Shared Skills Sync Policy
- Context: persisted homes must receive important bundle updates without overwriting user customizations.
- Decision: hash-state managed sync is default (`FORCE_SYNC_SHARED_SKILLS="*"`), with local-edit detection and legacy-home adoption/backup path.
- Impact: safer upgrades for existing users and fewer manual recovery steps.

### 2026-02-18 — Document Skills Distribution Policy
- Context: Anthropic document skills (`pdf/docx/pptx/xlsx`) are excluded from repository vendoring policy.
- Decision: keep those four skills out of `skills/` and install them only through Claude official plugin marketplace flow.
- Impact: policy compliance and clear installation boundary.

### 2026-02-18 — Playwright Reliability Contract
- Context: browser payload breakage or cache path conflicts caused runtime failures.
- Decision: keep build-time Chromium assert + startup self-heal + launch probe as health authority; dedupe only payload directories while keeping fallback root writable.
- Impact: fail-closed recovery behavior with reduced persisted-home footprint.

### 2026-02-18 — Ars Contexta Integration Mode
- Context: Claude and Codex have different plugin/runtime capabilities.
- Decision: Claude uses official plugin install; Codex uses local reference clone + bridge skill (manual methodology mode).
- Impact: both agents can leverage Ars Contexta within their supported execution model.

### 2026-02-18 — Automation Security Baseline
- Context: GitHub automation must remain safe on public repositories.
- Decision: fail-closed allowlist (`AGENT_ALLOWED_ACTORS`), foreign-fork PR skip defaults, SHA-pinned external actions, and explicit secret passing (no broad inherit).
- Impact: reduced abuse/supply-chain risk with auditable automation behavior.

### 2026-02-18 — Known Constraints Baseline
- Context: some tooling tradeoffs remain intentional.
- Decision: keep `broot` disabled in current image path; treat host Docker storage and persisted-home cache pressure as operational constraints managed by guard scripts.
- Impact: fewer unstable bootstrap paths and clearer ops playbook.
