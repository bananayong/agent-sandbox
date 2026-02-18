# External Skills Bundle Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add all requested external skills to the vendored shared bundle so they auto-install for Claude/Codex/Gemini at container startup.

**Architecture:** Keep existing startup install flow unchanged (`install_shared_skills` in `start.sh`) and expand the source bundle under `skills/`. Add a deterministic vendoring script to clone upstream repos at pinned commits and copy selected skill directories into canonical local names. Update metadata/docs/tests to keep behavior verifiable.

**Tech Stack:** Bash, git, existing shared-skills startup policy, smoke-test shell checks.

---

### Task 1: Define source mapping and conflict policy

**Files:**
- Create: `scripts/vendor-external-skills.sh`

**Step 1: Encode requested repositories and skill paths**
- Add explicit mapping rows: `repo | source_path | target_name`.
- Cover URL entries (all intended skills) and `npx skills add ... --skill ...` entries (exact requested target names).

**Step 2: Add deterministic conflict policy**
- Skip hidden/internal helper skills not requested (e.g., repo-private `.agents/...` variants).
- Keep existing Anthropic `skill-creator` untouched (do not overwrite with third-party `skill-creator`).

**Step 3: Validate map entries**
- Fail fast if any source path is missing `SKILL.md`.

### Task 2: Implement repeatable vendoring workflow

**Files:**
- Create: `scripts/vendor-external-skills.sh`

**Step 1: Clone each repo once (shallow)**
- Clone into a temp directory and collect commit SHA.

**Step 2: Copy mapped skill directories**
- Recreate `skills/<target_name>` from mapped source path.
- Preserve each skill's internal files (references, scripts, assets).

**Step 3: Generate metadata block**
- Emit/update external bundle section in `skills/UPSTREAM.txt` with repo/path/commit/timestamp entries.

### Task 3: Run vendoring and sync repository files

**Files:**
- Modify: `skills/*` (new skill directories)
- Modify: `skills/UPSTREAM.txt`

**Step 1: Execute vendoring script**
- Produce all requested skill directories.

**Step 2: Sanity-check outputs**
- Assert every new directory has `SKILL.md`.
- Check key requested names exist (e.g., `ai-sdk`, `workflow`, `before-and-after`, `ui-ux-pro-max`).

### Task 4: Update docs and long-lived records

**Files:**
- Modify: `README.md`
- Modify: `TODO.md`
- Modify: `MEMORY.md`

**Step 1: README update**
- Document additional vendored external skill set and startup auto-install scope.

**Step 2: TODO/MEMORY update**
- Add completed task record and stable decision note.

### Task 5: Strengthen smoke checks and verify

**Files:**
- Modify: `scripts/smoke-test.sh`

**Step 1: Expand required skill checks**
- Validate presence of selected required skills across all newly requested sources.

**Step 2: Run verification commands**
- `bash scripts/vendor-external-skills.sh`
- `SMOKE_TEST_SOURCE=repo bash scripts/smoke-test.sh --build`

**Step 3: Multi-pass review cycle**
- Pass A: mapping completeness vs user list.
- Pass B: diff-based code review for policy regressions.
- Pass C: command-output review for installation/test evidence.
