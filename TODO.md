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

- [ ] [P2] (setup) 상위 에이전트 실행 체인 구성 — 컨테이너 내부에서 openclaw/nanobot/nanoclaw/picoclaw/tinyclaw 같은 에이전트를 실행하고, 이 에이전트들을 통해 Codex/Claude를 호출·실행하는 워크플로우 및 기본 설정 제공
- [ ] [P3] (build) 이미지 사이즈 최적화 — 불필요한 레이어/캐시 정리, dive 등으로 레이어별 분석 및 경량화
- [ ] [P1] (setup) Playwright Chromium 동반 설치 보장 — `@playwright/cli`만 설치된 상태에서도 즉시 사용 가능하도록 컨테이너 빌드/런타임에서 Chromium 브라우저 바이너리를 함께 설치
## Done

- [x] [P2] (usability) Micro 에디터 Vim/Neovim 스타일 기본 구성 — `configs/micro/settings.json`/`bindings.json` 추가, `start.sh` 누락 플러그인 자동 설치(`detectindent`, `fzf`, `lsp`, `quickfix`, `bookmark`, `manipulator` + 테마), `Dockerfile`/`README`/`smoke-test` 동기화
- [x] [P2] (build) modern CLI + 매뉴얼 개선 — `uv` 추가 설치, `jq/ripgrep/bat/zoxide/shellcheck`를 upstream 바이너리 pin(+sha256 검증)으로 전환, slim의 man exclude 정책을 유지한 채 핵심 CLI man 페이지를 선택 설치하고 `help2man` fallback(재현성 고정) 적용
- [x] [P2] (setup) tmux 플러그인 설치 안정화 — `scripts/start.sh`에서 TPM 설치 시 임시 detached tmux 세션으로 서버 생존을 보장하고 `TMUX_PLUGIN_MANAGER_PATH`를 확실히 주입해 `unknown variable`/`Tmux Plugin Manager not configured` 오류를 방지
- [x] [P2] (usability) 컨테이너별 sandbox home 분리 지원 — `run.sh`에 `--name/-n`, `--home` 옵션을 추가하고 기본 컨테이너는 기존 `~/.agent-sandbox/home`를 유지하면서 커스텀 컨테이너는 `~/.agent-sandbox/<name>/home`를 자동 사용하도록 개선, `-s/-r` 대상 동기화 및 README/AGENTS 문서 반영
- [x] [P2] (usability) Codex 기본 편의 기능 확장 — `configs/codex/config.toml`에 `[features].undo=true`, `[features].multi_agent=true`, `[features].apps=true`, `[agents].max_threads=12` 추가, `start.sh` 기존 홈 안전 병합 로직 확장, smoke-test/README 동기화
- [x] [P2] (build) tealdeer 업스트림 바이너리 고정 설치 — Debian `tealdeer` 1.5.0의 `tldr --update` `InvalidArchive` panic을 제거하기 위해 Dockerfile에서 `tealdeer`를 apt 대신 upstream release(`TEALDEER_VERSION`)로 설치하고 smoke/build 검증에 `tldr` 확인 추가
- [x] [P2] (setup) 에이전트별 기본 설정 템플릿 — `.claude/`, `.codex/`, `.gemini/` 등 에이전트별 권장 설정 파일을 `/etc/skel/`에 포함하고 entrypoint managed sync로 사용자 홈에 동기화
- [x] [P3] (build) CI 파이프라인 정의 — GitHub Actions로 PR마다 빌드·lint·smoke test 자동 실행
- [x] [P3] (build) Re-enable `tldr --update` in `scripts/start.sh` after root-cause fix for `InvalidArchive` panic
- [x] [P2] (build) 도구 업데이트 자동 PR — pinned version ARG 업데이트를 주기적으로 제안하는 워크플로우
- [x] [P2] (usability) 컨테이너 기본 EDITOR를 nvim으로 설정 — `EDITOR`/`VISUAL`/`GIT_EDITOR` 기본값을 `nvim`으로 통일하고 Debian `editor` 대안도 `nvim`으로 지정, 기존 `micro` 기본값은 fallback으로만 유지
- [x] [P2] (usability) Vim/Neovim 기본 개발 환경 구성 — `vim-plug`(vim), `lazy.nvim`(neovim) 기반 플러그인/테마 세트와 베스트 프랙티스 설정을 `configs/`에 추가하고, `start.sh` first-run 자동 배포 및 smoke-test 검증 로직 반영
- [x] [P2] (setup) 컨테이너 기본 에디터 확장 — `vim`/`neovim` 기본 탑재 및 README 도구 요약 반영
- [x] [P2] (setup) 공용 snippet/template 저장소 — 자주 쓰는 프롬프트, 커맨드, 설정 조각을 `~/.agent-sandbox/templates/`에 모아서 에이전트들이 참조할 수 있도록 구성
- [x] [P2] (quality) GitHub Actions workflow lint 도입 — actionlint를 설치하고 `.github/workflows/*.yml` 정적 검증을 CI에 추가
- [x] [P3] (security) 이미지 취약점 스캔 — trivy 또는 grype로 빌드된 이미지의 CVE 스캔 자동화
- [x] [P2] (setup) tmux TPM 플러그인 자동 구성 — `scripts/start.sh` first-run 시 TPM 설치 및 `tmux-resurrect`/`tmux-continuum` 기본 플러그인 자동 활성화
- [x] [P2] (usability) Zimfw 플러그인 확장 — `configs/zimrc`에 `fzf-tab`, `zsh-you-should-use`, `fast-syntax-highlighting` 등 실사용 플러그인 추가 및 로드 순서 검증
- [x] [P2] (setup) GitHub Copilot CLI 방식 정리 — `gh copilot` extension이 GitHub 공식 방식으로 확인됨; standalone CLI는 deprecated. 현행 `start.sh` gh-copilot extension 자동 설치 유지
- [x] [P3] (setup) 선택 설치 플래그 — `lazygit`, `gitui`, `tokei` 등은 기본 설치됨 (pinned ARG로 관리); opt-in 분리는 불필요로 판단
- [x] [P2] (usability) Shell prompt 사용성 개선 — Starship 프롬프트 설정(`configs/starship.toml`)을 튜닝하여 현재 디렉토리, Git 상태, 실행 시간, 에러 코드 등 유용한 정보를 직관적으로 표시하고, 불필요한 모듈은 비활성화하여 깔끔하고 빠른 프롬프트 구성
- [x] [P2] (usability) Codex CLI statusline 커스터마이징 — `configs/codex/config.toml`에 `tui.status_line` 기본값을 추가하고, `start.sh`에서 신규 홈 자동 설치 + 기존 홈에는 `status_line`이 없을 때만 안전하게 병합
- [x] [P1] (setup) Playwright CLI 기반 웹 탐색 최적화 — `@playwright/cli`와 브라우저 런타임을 이미지에 설치하고, 전체 페이지 fetch를 줄이는 전용 스킬(`playwright-efficient-web-research`) 및 문서/검증 흐름 추가
- [x] [P2] (usability) Claude Code statusline 커스터마이징 — Claude Code의 하단 상태줄(statusline) 설정을 구성하여 유용한 컨텍스트 정보(모델명, 토큰 사용량, 프로젝트 정보 등)를 표시하도록 기본 설정 제공
- [x] [P1] (network) Claude Docker 연결 안정화 — `run.sh` DNS override(`--dns`, `AGENT_SANDBOX_DNS_SERVERS`) 추가, `start.sh` DNS 진단 경고 추가, `DISABLE_AUTOUPDATER=1` 기본값 적용, `host.docker.internal` 기본 매핑 및 컨테이너 IPv6 기본 비활성화 적용, IPv6-off 환경과 일치하도록 DNS 선택을 IPv4 우선으로 보정
- [x] [P1] (setup) 공용 `skills/` 폴더 구성 및 자동 로딩 — Anthropic `skills` 전체 벤더링, 컨테이너 시작 시 `~/.claude/skills`, `~/.codex/skills`, `~/.gemini/skills`로 자동 설치 (`skill-creator`는 Codex/Gemini 내장 스킬 충돌 방지를 위해 제외)
- [x] [P1] (setup) zshrc에 alias된 미설치 도구 추가 — dust, procs, btm, xh, mcfly 바이너리 설치
- [x] [P1] (security) 커밋 전 보안 민감 정보 유출 방지 장치 도입 — gitleaks + pre-commit hook으로 자동 검사
- [x] [P1] (setup) pre-commit 프레임워크 자동 구성 — pre-commit 설치 + `.pre-commit-config.yaml` 템플릿 제공
- [x] [P2] (quality) Dockerfile/shell script lint 및 검증 도구 도입 — hadolint, shellcheck 설치 + pre-commit hook 적용
- [x] [P1] (setup) Claude Code custom slash commands 자동 구성 — commit, review, test, debug 커맨드 정의
- [x] [P1] (setup) MCP 서버 설정 자동 구성 — filesystem MCP 서버 등록 (`.claude/.mcp.json`)
- [x] [P1] (setup) Claude skills 자동 구성 — sandbox-setup 스킬 정의
- [x] [P1] (setup) 유용한 스킬 만들기 — sandbox-setup 스킬 (환경 설정, 도구 확인, pre-commit 초기화)
- [x] [P1] (setup) 개발 환경 도구 자동 세팅 — pre-commit, shellcheck, hadolint, gitleaks 자동 구성
- [x] [P2] (setup) direnv 설치 — GitHub release 바이너리 + zshrc hook 추가
- [x] [P2] (build) 이미지 빌드 smoke test — `scripts/smoke-test.sh` 추가, 빌드 시 `--build` 플래그로 자동 실행
- [x] [P1] (automation) GitHub Issues 기반 자동 작업 환경 구축 — allowlist 기반 안전장치 + `.github/workflows/agent-issue-intake.yml`, `.github/workflows/agent-issue-worker.yml`, `.github/workflows/agent-pr-reviewer.yml`
- [x] [P1] (setup) 에이전트에게 사용 가능한 도구 목록 알려주기 — TOOLS.md 컨테이너 내부 배치 (`~/.config/agent-sandbox/TOOLS.md`)
- [x] [P2] (build) 버전 점검/업데이트 스크립트 추가 — `scripts/update-versions.sh`로 Dockerfile ARG, workflow action SHA, Codex 버전의 scan/check/update 지원
- [x] [P2] (setup) 에이전트 보조 도구 설치 — superpowers, beads, bkit 등 코딩 에이전트의 생산성을 높여주는 도구들을 이미지에 설치 (beads: Dockerfile bun global, bkit: start.sh marketplace, speckit: arm64 미지원으로 제외)
- [x] [P1] (automation) 에이전트 권한 프롬프트 최소화 — Codex/Claude/Gemini/Copilot auto-approve wrapper를 기본 활성화하여 사용자 확인 프롬프트 최소화
- [x] [P3] (setup) docker-compose 경로의 Claude MEMORY/AGENT TEAMS env 전달 보강 — `docker-compose.yml`에 Claude 실험/튜닝 env 전달(`CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `ENABLE_TOOL_SEARCH`, `CLAUDE_CODE_ENABLE_TASKS`, `CLAUDE_CODE_EFFORT_LEVEL`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) 추가 및 README 반영
