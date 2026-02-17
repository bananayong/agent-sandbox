# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Shared project context is in [AGENTS.md](./AGENTS.md).** This file contains Claude Code-specific additions only.

## Managed Runtime Defaults (`configs/claude/settings.json`)

Settings are applied via the managed `env` block in `settings.json`:

| Key | Value | Description |
|-----|-------|-------------|
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | `0` | Persistent learning across sessions (0 = enable) |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | Multi-agent coordination with shared task lists |
| `ENABLE_TOOL_SEARCH` | `auto:5` | Dynamic MCP tool discovery at 5% context usage |
| `CLAUDE_CODE_ENABLE_TASKS` | `true` | Task management with dependencies |
| `CLAUDE_CODE_EFFORT_LEVEL` | `high` | Maximum reasoning depth for Opus |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `70` | Auto-compact context at 70% usage |

`teammateMode` is set to `"tmux"` — teammates spawn as tmux split panes inside the `main` session.

These values are managed defaults, not host-side runtime feature flags.
