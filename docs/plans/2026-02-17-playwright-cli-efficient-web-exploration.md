# Playwright CLI Efficient Web Exploration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate Playwright CLI into the sandbox and add a dedicated skill that guides coding agents to perform token-efficient web exploration without repeatedly fetching full page content.

**Architecture:** Add Playwright CLI and required browser runtime dependencies at image build time, then provide a shared skill (`skills/playwright-efficient-web-research`) that standardizes session-first, snapshot-ref, selective extraction workflows. Keep MCP as an explicit fallback path for long-running/stateful loops.

**Tech Stack:** Dockerfile (Debian bookworm), Node.js/npm (`@playwright/cli`), Playwright Chromium runtime, Bash smoke checks, shared skills bundle.

---

### Task 1: Baseline and Task Registration

**Files:**
- Modify: `TODO.md`

**Step 1: Add pending task entry**
- Add a new pending task for Playwright CLI + efficient web exploration skill implementation.

**Step 2: Verify task entry exists**
Run: `rg -n "Playwright CLI|웹 탐색" TODO.md`
Expected: new pending line appears in `## Pending`.

**Step 3: Commit checkpoint (optional)**
Run:
```bash
git add TODO.md
git commit -S -m "chore: add playwright cli optimization task"
```

### Task 2: Docker Runtime Integration

**Files:**
- Modify: `Dockerfile`

**Step 1: Add pinned arg for Playwright CLI**
- Introduce `ARG PLAYWRIGHT_CLI_VERSION=<version>` near existing pinned tool args.

**Step 2: Install Playwright CLI globally**
- Add a build step to install `@playwright/cli` globally (`npm install -g @playwright/cli@${PLAYWRIGHT_CLI_VERSION}`).

**Step 3: Install Linux browser dependencies**
- Extend apt package list with Playwright-required runtime dependencies for Chromium.

**Step 4: Install browser binary during build**
- Add build step to run `playwright-cli install` in a temporary bootstrap directory with `PLAYWRIGHT_BROWSERS_PATH` set.

**Step 5: Extend build-time sanity checks**
- Ensure `playwright-cli` is included in command existence checks.

**Step 6: Verify Dockerfile edits**
Run: `rg -n "PLAYWRIGHT_CLI_VERSION|playwright-cli|libnss3|PLAYWRIGHT_BROWSERS_PATH" Dockerfile`
Expected: all markers found.

### Task 3: Smoke Test Coverage

**Files:**
- Modify: `scripts/smoke-test.sh`

**Step 1: Add Playwright CLI binary check**
- Add `playwright-cli --version` in a relevant section.

**Step 2: Keep runtime-safe checks**
- Do not add checks that require network or privileged access in build mode.

**Step 3: Verify smoke script syntax**
Run: `bash -n scripts/smoke-test.sh`
Expected: no output, exit 0.

### Task 4: New Shared Skill for Efficient Web Research

**Files:**
- Create: `skills/playwright-efficient-web-research/SKILL.md`

**Step 1: Add skill metadata and trigger description**
- Trigger on web exploration/research/extraction tasks where token efficiency matters.

**Step 2: Encode workflow constraints**
- Session-first workflow (`-s=<name>`), snapshot refs, targeted `eval`, no full-page dumping by default.
- Use direct `playwright-cli` commands (no wrapper shell scripts).

**Step 3: Add MCP fallback guidance**
- Document when to use MCP (long-running/self-healing/state-heavy loops).

### Task 5: Docs and Existing Skill Alignment

**Files:**
- Modify: `README.md`
- Modify: `skills/webapp-testing/SKILL.md`

**Step 1: Update README section**
- Add a concise section for Playwright CLI usage, benefits, and MCP fallback boundary.

**Step 2: Align existing `webapp-testing` skill**
- Remove or soften Python-only assumption; reference `playwright-cli`-first path and keep Python script path as alternative when appropriate.

**Step 3: Verify references**
Run: `rg -n "playwright-cli|MCP|token" README.md skills/webapp-testing/SKILL.md`
Expected: updated guidance present.

### Task 6: Final Verification and Task Closure

**Files:**
- Modify: `TODO.md`
- Modify: `MEMORY.md`

**Step 1: Lint/syntax checks**
Run:
```bash
bash -n scripts/smoke-test.sh
rg -n "playwright-cli" Dockerfile scripts/smoke-test.sh README.md skills
```
Expected: commands succeed.

**Step 2: Runtime command sanity checks**
Run:
```bash
npx --yes @playwright/cli --help
```
Expected: help output includes core commands.

**Step 3: Move TODO item to done**
- Mark completed task with `[x]` and move to `## Done`.

**Step 4: Record decision in memory**
- Add a dated entry to `MEMORY.md` describing why CLI+Skill is default and MCP is fallback.

**Step 5: Optional commit sequence**
Run:
```bash
git add Dockerfile scripts/smoke-test.sh README.md skills/playwright-efficient-web-research skills/webapp-testing/SKILL.md TODO.md MEMORY.md docs/plans/2026-02-17-playwright-cli-efficient-web-exploration.md
git commit -S -m "feat: add playwright cli workflow and efficient web research skill"
```

## Risks and Mitigations

1. Image size growth from browser binaries.
- Mitigation: install Chromium only, avoid extra channels.

2. Browser launch failures due to missing system libs.
- Mitigation: include Debian runtime deps explicitly and keep smoke command check.

3. Skill overlap/confusion with `webapp-testing`.
- Mitigation: define clear boundaries (`efficient web research` vs local app functional testing).

## Acceptance Criteria

1. `playwright-cli` is installed in the image and visible in smoke checks.
2. New skill is vendored under `skills/` and auto-installed by existing startup flow.
3. README explains CLI-first + MCP fallback boundary.
4. TODO and MEMORY are updated following repository conventions.
