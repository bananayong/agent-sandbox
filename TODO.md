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

- [ ] [P2] (setup) 에이전트 보조 도구 설치 — speckit, superpowers, beads 등 코딩 에이전트의 생산성을 높여주는 도구들을 이미지에 설치
- [ ] [P2] (setup) 상위 에이전트 실행 체인 구성 — 컨테이너 내부에서 openclaw/nanobot/nanoclaw/picoclaw/tinyclaw 같은 에이전트를 실행하고, 이 에이전트들을 통해 Codex/Claude를 호출·실행하는 워크플로우 및 기본 설정 제공
- [ ] [P2] (build) 이미지 사이즈 최적화 — 불필요한 레이어/캐시 정리, dive 등으로 레이어별 분석 및 경량화
- [ ] [P2] (usability) `run.sh` 상태 확인 명령 추가 — `run.sh --status`로 컨테이너 상태, 리소스 사용량, 마운트 볼륨 확인
- [ ] [P2] (security) 컨테이너 헬스체크 — docker-compose.yml에 healthcheck 정의, 주요 프로세스 상태를 주기적으로 확인
- [ ] [P2] (security) `.env` 파일 지원 — docker-compose.yml에서 env_file 지원 추가, API 키 관리를 환경변수 나열 대신 .env 파일로 간소화
- [ ] [P2] (setup) 에이전트별 기본 설정 템플릿 — `.claude/`, `.codex/`, `.gemini/` 등 에이전트별 권장 설정 파일을 `/etc/skel/`에 포함하여 첫 실행 시 자동 복사
- [ ] [P2] (setup) 공용 snippet/template 저장소 — 자주 쓰는 프롬프트, 커맨드, 설정 조각을 `~/.agent-sandbox/templates/`에 모아서 에이전트들이 참조할 수 있도록 구성
- [ ] [P2] (docs) 아키텍처 다이어그램 — README에 마운트 구조, 네트워크, 진입 흐름을 시각화한 다이어그램 추가
- [ ] [P3] (build) CI 파이프라인 정의 — GitHub Actions로 PR마다 빌드·lint·smoke test 자동 실행
- [ ] [P2] (quality) GitHub Actions workflow lint 도입 — actionlint를 설치하고 `.github/workflows/*.yml` 정적 검증을 CI에 추가
- [ ] [P3] (usability) dry-run 모드 — `run.sh --dry-run`으로 실제 실행 없이 어떤 Docker 명령이 수행될지 미리 출력
- [ ] [P3] (security) 이미지 취약점 스캔 — trivy 또는 grype로 빌드된 이미지의 CVE 스캔 자동화
- [ ] [P3] (docs) 커스터마이징 가이드 — 사용자가 자신만의 도구/설정을 추가하는 방법을 단계별로 정리
- [ ] [P2] (usability) Shell prompt 사용성 개선 — Starship 프롬프트 설정(`configs/starship.toml`)을 튜닝하여 현재 디렉토리, Git 상태, 실행 시간, 에러 코드 등 유용한 정보를 직관적으로 표시하고, 불필요한 모듈은 비활성화하여 깔끔하고 빠른 프롬프트 구성
- [ ] [P2] (usability) Claude Code statusline 커스터마이징 — Claude Code의 하단 상태줄(statusline) 설정을 구성하여 유용한 컨텍스트 정보(모델명, 토큰 사용량, 프로젝트 정보 등)를 표시하도록 기본 설정 제공
- [ ] [P3] (build) Re-enable `tldr --update` in `scripts/start.sh` after root-cause fix for `InvalidArchive` panic
- [ ] [P2] (setup) tmux TPM 플러그인 자동 구성 — `scripts/start.sh` first-run 시 TPM 설치 및 `tmux-resurrect`/`tmux-continuum` 기본 플러그인 자동 활성화
- [ ] [P2] (usability) Zimfw 플러그인 확장 — `configs/zimrc`에 `fzf-tab`, `zsh-you-should-use`, `fast-syntax-highlighting` 등 실사용 플러그인 추가 및 로드 순서 검증
- [ ] [P2] (setup) GitHub Copilot CLI 방식 정리 — `gh-copilot` extension 설치에서 standalone `copilot` CLI 중심으로 전환하고 인증/설정 경로 문서화
- [ ] [P2] (security) `run.sh` 보안 하드닝 프로필 추가 — `--cap-drop=ALL`, `--pids-limit` 등 선택형 hardened 실행 옵션 제공(기본/호환 모드와 분리)
- [ ] [P3] (automation) 다중 에이전트 병렬 작업 헬퍼 — Git worktree 기반으로 에이전트별 분리 작업 디렉토리를 자동 생성/정리하는 스크립트 추가
- [ ] [P1] (quality) `run.sh doctor` 진단 명령 추가 — Docker socket 권한, 네트워크 MTU, 필수 env, 바이너리 존재 여부를 한 번에 점검
- [ ] [P1] (security) 이미지 공급망 검증 강화 — 다운로드 바이너리 SHA256 검증/서명 검증 단계 추가
- [ ] [P2] (build) 버전 매니페스트 자동 생성 — 이미지 빌드 시 설치된 도구 버전 목록(`versions.txt`) 산출
- [ ] [P2] (build) 도구 업데이트 자동 PR — pinned version ARG 업데이트를 주기적으로 제안하는 워크플로우
- [ ] [P2] (security) 네트워크 정책 프로필 — `default/offline/restricted` 실행 모드 선택 지원
- [ ] [P2] (security) read-only 루트파일시스템 옵션 — 선택적으로 `--read-only` + `tmpfs` 런타임 프로필 제공
- [ ] [P2] (usability) `run.sh` 프로필 시스템 — `--profile minimal|full|hardened`로 옵션 묶음 적용
- [ ] [P2] (usability) `run.sh logs`/`exec` 보조 명령 — attach 없이 상태 확인/명령 실행 지원
- [ ] [P2] (setup) agent config migration 도구 — 기존 `~/.agent-sandbox/home` 구조 변경 시 안전한 마이그레이션 스크립트
- [ ] [P2] (ops) sandbox home 백업/복원 명령 — 인증/설정 스냅샷 export/import 지원
- [ ] [P2] (quality) 셸 시작 성능 측정 — zsh startup time 측정 스크립트와 회귀 기준선 도입
- [ ] [P2] (quality) first-run idempotency 테스트 — `start.sh` 재실행 시 설정 덮어쓰기/오동작 없는지 자동 검증
- [ ] [P3] (docs) 트러블슈팅 플레이북 분리 — 소켓 권한, TLS, 프록시, rootless 사례를 시나리오별로 문서화
- [ ] [P3] (setup) 선택 설치 플래그 — 무거운 도구(`lazygit`, `gitui`, `tokei` 등) opt-in 빌드 ARG 제공
- [ ] [P1] (automation) 에이전트 권한 프롬프트 최소화 — Claude/Codex 등에서 반복적으로 permission 확인을 묻지 않도록 안전한 기본 허용 규칙(prefix allowlist, 비파괴 명령 자동 승인)과 가이드 정비

## Done

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
