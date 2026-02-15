# TODO.md

Project task list. All coding agents (Claude Code, Codex CLI, Gemini CLI, OpenCode) use this file as the single source of truth for pending work.

## Format

Each task uses a checkbox line. Append new tasks at the bottom of the relevant section.

- `- [ ]` = pending
- `- [x]` = done

Optionally tag with priority and category:

```
- [ ] [P0] (category) Task description
```

- **P0** = critical / blocking
- **P1** = high priority
- **P2** = normal
- **P3** = low / nice-to-have

## Pending

- [ ] [P1] (setup) Claude Code custom slash commands 자동 구성 — `.claude/commands/`에 자주 쓰는 커맨드 정의 (예: /commit, /review-pr 등)
- [ ] [P1] (setup) 개발 환경 도구 자동 세팅 — Git hooks, linter, formatter, test runner 등 워크플로우 도구 자동 구성
- [ ] [P1] (setup) MCP 서버 설정 자동 구성 — `.mcp.json` 또는 `.claude/mcp.json`에 유용한 MCP 서버 등록
- [ ] [P1] (setup) Claude skills 자동 구성 — 프로젝트에 맞는 Claude skills 정의 및 등록
- [ ] [P2] (quality) Dockerfile/shell script lint 및 검증 도구 도입 — hadolint(Dockerfile), shellcheck(sh/bash/zsh) 등을 이미지에 설치하고 CI 또는 pre-commit hook으로 적용
- [ ] [P3] (build) Re-enable `tldr --update` in `scripts/start.sh` after root-cause fix for `InvalidArchive` panic

## Done

