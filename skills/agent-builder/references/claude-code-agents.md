# Claude Code Agent Format Reference

Complete reference for `.claude/agents/*.md` agent definition files.

## File Locations

| Scope | Path | Visibility |
|-------|------|------------|
| Project | `.claude/agents/*.md` | Checked into version control, shared with team |
| User | `~/.claude/agents/*.md` | Personal, applies to all projects |

Priority: CLI flag > project-level > user-level > plugin-provided.

## File Structure

Each agent is a single Markdown file with YAML frontmatter:

```markdown
---
# Required fields
name: agent-name
description: When and why the parent agent should delegate to this agent.

# Tool access (optional — inherits all if omitted)
tools: Read, Glob, Grep, Bash
disallowedTools: Write, Edit

# Execution settings (optional)
model: sonnet
permissionMode: default
maxTurns: 25

# Advanced (optional)
skills:
  - skill-name
mcpServers:
  server-name:
    command: node
    args: ["server.js"]
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate.sh"
memory: project
---

System prompt body goes here. This is what the agent sees as its instructions.
```

## All Frontmatter Fields

### Required

| Field | Type | Description |
|---|---|---|
| `name` | string | Unique identifier. Lowercase, hyphens, max 64 chars. Must match filename (without `.md`). |
| `description` | string | **Primary trigger mechanism.** The parent agent reads this to decide when to delegate. Make it comprehensive — include what the agent does AND specific scenarios that should trigger it. |

### Tool Access

| Field | Type | Default | Description |
|---|---|---|---|
| `tools` | comma-separated string | all tools | Allowlist. Only these tools are available. |
| `disallowedTools` | comma-separated string | none | Denylist. These tools are removed from the available set. |

Use `tools` (allowlist) when the agent needs a small, specific set. Use `disallowedTools` (denylist) when the agent needs most tools but should be blocked from a few.

Available tool names: `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, `WebFetch`, `WebSearch`, `Task`, `NotebookEdit`, `AskUserQuestion`.

To restrict which subagents can be spawned: `Task(explorer, implementer)` — only allows spawning agents named `explorer` or `implementer`.

### Execution Settings

| Field | Type | Default | Description |
|---|---|---|---|
| `model` | string | `inherit` | `haiku`, `sonnet`, `opus`, or `inherit` (parent's model). |
| `permissionMode` | string | `default` | How permission prompts are handled. See table below. |
| `maxTurns` | number | ~25 | Max agentic turns before the agent stops. Prevents runaway execution. |

#### Permission Modes

| Mode | File Edits | Bash Commands | Use For |
|------|-----------|---------------|---------|
| `default` | Ask | Ask | Most agents |
| `acceptEdits` | Auto-approve | Ask | Trusted implementers |
| `delegate` | Delegate to team lead | Delegate to team lead | Team members |
| `dontAsk` | Auto-approve | Auto-approve | Fully trusted agents |
| `bypassPermissions` | Skip all | Skip all | Automation only |
| `plan` | Blocked until plan approved | Blocked until plan approved | Architects, planners |

### Advanced

| Field | Type | Description |
|---|---|---|
| `skills` | list of strings | Skills to preload into the agent's context. |
| `mcpServers` | object | MCP server references or inline definitions. Keys are server names. |
| `hooks` | object | Lifecycle hooks: `PreToolUse`, `PostToolUse`, `Stop`. Each hook can run a shell command that validates the operation. Exit code 2 blocks execution with feedback. |
| `memory` | string | Persistent memory scope: `user` (cross-project), `project` (version-controlled), `local` (project-specific, not shared). |

## Full Examples

### Read-Only Security Reviewer

```markdown
---
name: security-reviewer
description: Reviews code changes for security vulnerabilities, injection risks, and credential exposure. Use proactively after changes to authentication, authorization, or input-handling code. Also use when explicitly asked to review code for security.
tools: Read, Glob, Grep, Bash
model: sonnet
permissionMode: default
maxTurns: 30
---

You are a security-focused code reviewer.

When invoked:
1. Run `git diff` to identify changed files
2. Prioritize files handling: authentication, user input, database queries, file operations
3. For each file, check against OWASP Top 10

Report format:
- CRITICAL: Immediate exploitable vulnerabilities
- WARNING: Potential risks needing review
- INFO: Suggestions for hardening

Never suggest changes directly. Report findings only.
Do not modify any files.
```

### Fast Codebase Explorer

```markdown
---
name: explorer
description: Fast codebase search and analysis. Use when needing to find files, search for patterns, or understand code structure without making changes.
tools: Read, Glob, Grep
model: haiku
maxTurns: 15
---

You are a fast codebase explorer. Search efficiently and return concise summaries.

When invoked:
1. Understand the search query
2. Use Glob to find relevant files by pattern
3. Use Grep to search content within files
4. Use Read to examine specific files

Return a focused summary with file paths and line numbers. Do not speculate — only report what you find.
```

### Refactoring Agent with Plan Approval

```markdown
---
name: refactorer
description: Refactors code while preserving behavior. Use when restructuring, renaming, extracting functions, or improving code organization. Always requires plan approval before making changes.
tools: Read, Edit, Write, Bash, Glob, Grep
model: opus
permissionMode: plan
maxTurns: 50
memory: project
---

You are a careful refactoring agent. Preserve existing behavior at all times.

When invoked:
1. Understand the refactoring goal
2. Read all affected files and their tests
3. Create a plan describing each change and why
4. After plan approval, make changes incrementally
5. Run tests after each change to verify no regressions

Constraints:
- Never change behavior, only structure
- Run the full test suite before reporting completion
- If any test fails, revert the last change and report the failure
- Do not add new features or fix unrelated bugs
```

### Team Member with Hooks

```markdown
---
name: backend-dev
description: Implements backend features and API endpoints. Owns files under src/api/ and src/services/. Use as a team member in agent teams for backend work.
tools: Read, Edit, Write, Bash, Glob, Grep
model: sonnet
permissionMode: delegate
maxTurns: 40
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/check-file-ownership.sh"
---

You are a backend developer. You own files under src/api/ and src/services/.

When assigned a task:
1. Read the task description from the task list
2. Understand requirements and identify affected files
3. Implement changes in your owned directories only
4. Run relevant tests with `npm test -- --grep <pattern>`
5. Mark the task as completed

Constraints:
- Only modify files under src/api/ and src/services/
- If a change requires frontend work, create a new task for the frontend teammate
- Run tests before marking any task complete
```

## Writing Effective Descriptions

The `description` field is how the parent agent decides whether to delegate a task. Write it like a job posting:

**Bad:**
```
A code reviewer.
```

**Good:**
```
Reviews code changes for security vulnerabilities, performance issues, and adherence to project conventions. Use proactively after changes to authentication, database queries, or API endpoints. Also use when explicitly asked to review code.
```

Include:
- What the agent does (capabilities)
- When to use it (trigger scenarios)
- When NOT to use it (if ambiguous with other agents)
