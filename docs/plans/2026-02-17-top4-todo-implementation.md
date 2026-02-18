# Top 4 TODO Implementation Plan (Archived)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> **Status (2026-02-18): Completed.**
> This document is retained as execution history.
> Do not treat the tasks below as pending TODO work.
>
> **Follow-up update (2026-02-18):**
> Codex/Gemini `settings.json` policy was changed from first-run copy to managed sync (same model as Claude).

**Goal:** Historical record of completing the top four TODO items with isolated ownership, explicit verification, and post-completion multi-round review feedback.

**Architecture:** Implement each TODO as a focused change set: agent template defaults in image/startup bootstrap, new PR CI workflow, robust tealdeer update logic, and scheduled auto-PR workflow for pinned version updates. Keep startup behavior idempotent and non-blocking. Preserve existing conventions: managed settings, pinned workflow actions, and beginner-friendly shell comments.

**Tech Stack:** Bash (`scripts/start.sh`, `scripts/smoke-test.sh`), Dockerfile, GitHub Actions workflows, Markdown docs (`README.md`, `TODO.md`).

---

### Task 1: Agent-specific default templates in `/etc/skel` + managed sync

**Files:**
- Create: `configs/codex/settings.json`
- Create: `configs/gemini/settings.json`
- Modify: `Dockerfile`
- Modify: `scripts/start.sh`
- Modify: `scripts/smoke-test.sh`
- Modify: `README.md`

**Step 1: Add explicit per-agent template files**
- Add recommended baseline settings for Codex and Gemini as dedicated templates (instead of deriving from Claude config).

**Step 2: Ensure image copies those templates into `/etc/skel`**
- Replace Dockerfile logic that clones Claude settings into `.codex/.gemini` with direct `COPY` from `configs/codex/settings.json` and `configs/gemini/settings.json`.

**Step 3: Keep startup behavior explicit**
- Use managed sync for Claude/Codex/Gemini settings so image defaults propagate to existing homes.
- Print diffs before overwrite for operator visibility.

**Step 4: Add smoke assertion for agent template install policy**
- Verify `scripts/start.sh` manages `.claude/.codex/.gemini` settings from `/etc/skel`.

**Step 5: Document behavior**
- Update README with the agent template policy and file locations.

**Verification:**
- `bash -n scripts/start.sh scripts/smoke-test.sh`
- `SMOKE_TEST_SOURCE=repo bash scripts/smoke-test.sh --build`
- `rg -n "update_managed /etc/skel/.(claude|codex|gemini)/settings.json" scripts/start.sh`

---

### Task 2: PR CI workflow for build/lint/smoke

**Files:**
- Create: `.github/workflows/pr-build-lint-smoke.yml`
- Modify: `README.md`

**Step 1: Add pull_request workflow scaffold**
- Trigger on PR events (`opened`, `synchronize`, `reopened`, `ready_for_review`).
- Set least-privilege permissions and reasonable timeout.

**Step 2: Add lint stage**
- Run shell syntax + lint checks (`shellcheck`, `hadolint`, `actionlint`) on repository files.

**Step 3: Add build + smoke stage**
- Build Docker image in CI.
- Run smoke test using `scripts/smoke-test.sh --build` in repo mode.

**Step 4: Keep action pinning convention**
- Pin external actions by commit SHA to match repository policy.

**Verification:**
- `actionlint .github/workflows/*.yml`
- `hadolint Dockerfile`
- `shellcheck scripts/*.sh run.sh`

---

### Task 3: Re-enable `tldr --update` with InvalidArchive mitigation

**Files:**
- Modify: `scripts/start.sh`
- Modify: `scripts/smoke-test.sh`
- Modify: `README.md`

**Step 1: Add resilient update helper**
- Implement non-blocking `update_tealdeer_cache` function.
- Retry update with bounded attempts and timeouts.

**Step 2: Handle InvalidArchive root cause path**
- On `InvalidArchive` failure, clear tealdeer cache and retry.
- Preserve startup flow even on repeated failures (warn only).

**Step 3: Re-enable startup invocation**
- Replace disabled TODO block with real helper call in one-time tool setup.

**Step 4: Add smoke policy check**
- Ensure smoke test validates helper definition and invocation are present.

**Verification:**
- `bash -n scripts/start.sh scripts/smoke-test.sh`
- `SMOKE_TEST_SOURCE=repo bash scripts/smoke-test.sh --build`
- `rg -n "update_tealdeer_cache|tldr --update" scripts/start.sh`

---

### Task 4: Scheduled workflow for automated pinned-version update PRs

**Files:**
- Create: `.github/workflows/update-pinned-versions.yml`
- Modify: `README.md`

**Step 1: Add schedule + manual trigger**
- Run weekly and allow manual `workflow_dispatch`.

**Step 2: Run update script in update mode**
- Execute `scripts/update-versions.sh update`.
- Detect git diff and skip PR creation when no change.

**Step 3: Open PR automatically when changes exist**
- Use `peter-evans/create-pull-request` with commit message, branch naming, labels, and body.

**Step 4: Preserve pinning/security conventions**
- Pin all external actions by SHA.

**Verification:**
- `bash scripts/update-versions.sh scan`
- `bash scripts/update-versions.sh update --dry-run`
- `actionlint .github/workflows/*.yml`

---

### Execution Order

1. Task 1 (template foundation)  
2. Task 3 (same startup surface; merge with Task 1 startup edits)  
3. Task 2 (CI guardrail for PRs)  
4. Task 4 (automation that depends on CI/update conventions)

### Review Gates

- Pre-execution plan review by independent reviewer agent.
- Implementation review after each task (spec check then quality check).
- Final 3+ review/feedback rounds after all changes.
