# Ars Contexta Auto-Install Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically install Ars Contexta in this sandbox, with official Claude plugin wiring and a Codex-compatible bridge.

**Architecture:** Reuse existing `start.sh` first-run installer pattern (timeout + sentinel + non-blocking warnings). Keep Claude on official marketplace/plugin flow, and keep Codex in reference mode by cloning Ars Contexta sources plus a bridge skill that explains limitations.

**Tech Stack:** Dockerfile, bash entrypoint (`scripts/start.sh`), markdown docs (`README.md`, `TODO.md`, `MEMORY.md`), Codex skill format (`SKILL.md`).

---

### Task 1: Add Codex Bridge Skill Seed Path

**Files:**
- Create: `configs/codex/skills/arscontexta-bridge/SKILL.md`
- Modify: `Dockerfile`
- Modify: `scripts/start.sh`

**Step 1: Write the Codex bridge skill file**

Add `arscontexta-bridge` skill with:
- local bundle path (`~/.codex/vendor/arscontexta`)
- usable capabilities (methodology/reference/generator docs)
- explicit unsupported area (`/arscontexta:*` Claude plugin commands)

**Step 2: Copy skill template into image defaults**

Add Docker build copy:
- `COPY configs/codex/skills/ /etc/skel/.codex/skills/`

**Step 3: Seed bridge skill into persisted home**

Use `copy_default` in `start.sh`:
- `/etc/skel/.codex/skills/arscontexta-bridge/SKILL.md` -> `~/.codex/skills/arscontexta-bridge/SKILL.md`

### Task 2: Install Ars Contexta for Claude (Official)

**Files:**
- Modify: `scripts/start.sh`

**Step 1: Add marketplace/plugin health checks**

Add helper functions in `start.sh`:
- `claude_has_arscontexta_marketplace`
- `claude_has_arscontexta_plugin`

**Step 2: Add first-run installer block**

Add installation block with:
- sentinel: `~/.claude/plugins/.arscontexta-installed`
- marketplace add: `claude plugin marketplace add agenticnotetaking/arscontexta`
- plugin install: `claude plugin install --scope user arscontexta@agenticnotetaking`
- timeout + non-blocking warning logs

### Task 3: Install Ars Contexta Reference Bundle for Codex

**Files:**
- Modify: `scripts/start.sh`

**Step 1: Add Codex clone block**

On first run:
- clone repo into `~/.codex/vendor/arscontexta` (`--depth 1`)
- set sentinel `~/.codex/.arscontexta-reference-installed` when clone succeeds
- keep startup resilient (timeout + warning on failure)

### Task 4: Document and Track the Decision

**Files:**
- Modify: `README.md`
- Modify: `TODO.md`
- Modify: `MEMORY.md`

**Step 1: Update runtime documentation**

Add an `Ars Contexta Auto-Install` section describing:
- Claude official plugin install behavior
- Codex reference bridge behavior
- limitation note for Codex command compatibility

**Step 2: Update task tracking and stable memory**

- Add completed task in `TODO.md`
- Add stable baseline decision in `MEMORY.md`

### Task 5: Verify Changes

**Files:**
- Modify: `scripts/start.sh` (validation only)
- Modify: `Dockerfile` (validation only)

**Step 1: Syntax validation**

Run:
- `bash -n scripts/start.sh`

**Step 2: Focused search validation**

Run:
- `rg -n "arscontexta|arscontexta-bridge" scripts/start.sh Dockerfile README.md TODO.md MEMORY.md`

**Step 3: Diff review**

Run:
- `git diff -- scripts/start.sh Dockerfile README.md TODO.md MEMORY.md configs/codex/skills/arscontexta-bridge/SKILL.md docs/plans/2026-02-18-arscontexta-auto-install.md`
