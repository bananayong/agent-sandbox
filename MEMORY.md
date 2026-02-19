# MEMORY.md

Long-lived technical decisions for this repository.
Keep only stable guidance with operational impact.

## Decision Log

### 2026-02-19 — Java Onboarding Resume/Fallback Hardening
- Context: jdtls/OpenJDK first-run onboarding could repeatedly fail on slow links because each startup retried from scratch, and inherited `JENV_ROOT` values could drift to non-sandbox paths.
- Decision: force `JENV_ROOT` to `/home/sandbox/.jenv` during onboarding and switch jdtls/OpenJDK downloads to resumable partial-cache flow (`*.partial`) with cache fallback for jdtls archives.
- Impact: onboarding is deterministic per sandbox home and recovers across repeated startups instead of failing indefinitely on unstable/slow networks.

### 2026-02-19 — jdtls Startup Anti-Stall Policy
- Context: first-run Java onboarding occasionally appeared frozen while downloading jdtls snapshots, blocking shell startup for several minutes.
- Decision: jdtls onboarding now uses cached snapshot archives with integrity check (`tar -tzf`) and guarded `curl` options (`connect/max-time`, low-speed abort) to fail fast on poor links.
- Impact: startup no longer feels hung during jdtls provisioning; repeated retries reuse cache when available.

### 2026-02-19 — Codex Subagent Permission Baseline
- Context: multi-agent(`explorer`/`worker`) sessions intermittently hit permission/trust dead-ends in mounted workspaces.
- Decision: codex managed defaults now include `approval_policy="never"`, `sandbox_mode="danger-full-access"`, and `[projects."/workspace"].trust_level="trusted"`, plus startup-time merge for existing homes.
- Impact: subagent creation/exploration works with fewer permission failures and no manual trust bootstrap.

### 2026-02-19 — Java Onboarding Contract
- Context: Java toolchain availability drifted across persisted homes and image refresh cycles.
- Decision: install `jenv` in image, then run startup onboarding to auto-download Temurin OpenJDK 21, register via `jenv add/global`, and provision `jdtls` in persisted home.
- Impact: reproducible Java runtime + LSP availability without requiring users to bake JDK payloads into image layers.

### 2026-02-19 — Agent Tool Inventory UX
- Context: operators needed a fast, runtime-accurate answer for what codex/claude/gemini can use inside the container.
- Decision: add `agent-tools` command that reports per-agent settings/skills/LSP and common CLI availability.
- Impact: lower setup ambiguity and faster troubleshooting for agent capability questions.

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
