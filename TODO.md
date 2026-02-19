# TODO.md

Project task list. All coding agents use this file as the operational source of truth for active work.

## Format
- `- [ ]` = pending
- `- [x]` = done
- Optional tags: `[P0|P1|P2|P3] (category)`

## Pending
- [ ] [P2] (setup) 상위 에이전트 체인 실행 토폴로지 확정 (openclaw/nanobot/nanoclaw/picoclaw/tinyclaw 역할·호출 순서·실행 경계 정의)
- [ ] [P2] (setup) 체인 기본 실행 스크립트/설정 추가 (컨테이너 내부에서 Codex/Claude 호출 경로 포함)
- [ ] [P2] (docs) 체인 사용 가이드 작성 (`README` 또는 전용 운영 문서)

## Done (Recent)
- [x] [P2] (reliability) Java LSP 미러 우선순위 지원 — `AGENT_SANDBOX_JDTLS_BASE_URLS`로 jdtls 다운로드 base URL을 다중 후보로 지정 가능하게 하고, `run.sh`/`docker-compose.yml` 전달 및 README 사용법을 반영
- [x] [P1] (reliability) Java 온보딩 복원력 강화 — `start.sh`에서 `JENV_ROOT`를 sandbox 홈으로 고정하고, jdtls/OpenJDK 다운로드를 resumable partial cache(`*.partial`) 기반으로 전환해 느린 네트워크에서도 재시도 누적으로 복구되도록 개선
- [x] [P2] (usability) zsh Starship Java 표시 개선 — `custom.jenv`를 커피 이모지 기반(`☕`)으로 개편하고 `jenv version-name` + `java -version`을 단일 세그먼트로 노출하도록 조정
- [x] [P1] (reliability) container startup 시 jenv export hook nounset 충돌 복구 — `start.sh`의 `jenv init` 구간에서 `PROMPT_COMMAND` 기본값 보장 및 `set -u` 일시 완화/복구로 `/home/sandbox/.jenv/plugins/export/...: PROMPT_COMMAND: unbound variable` 오류로 인한 부팅 실패 방지
- [x] [P1] (reliability) jdtls 설치 멈춤 완화 — `start.sh`의 jdtls 다운로드를 cache+archive 검증 기반으로 변경하고, `curl` 저속 감지/연결·총 소요 타임아웃을 추가해 startup 장시간 블로킹을 방지
- [x] [P1] (setup) subagents 생성시 접근 권한 이슈 해결 — Codex 기본값에 `approval_policy=never`, `sandbox_mode=danger-full-access`, `/workspace` trust를 추가하고, `start.sh`가 기존 사용자 `~/.codex/config.toml`에도 자동 보강하도록 반영
- [x] [P1] (setup) jenv 설치 + OpenJDK 자동 온보딩 + Java LSP 연동 — `jenv`를 이미지 기본 도구로 포함하고, `start.sh`에서 Temurin OpenJDK 21 다운로드/`jenv add|global`/`jdtls` 설치 wrapper를 자동화, Codex/Claude/Gemini/Micro LSP 매핑과 zsh/starship 표시까지 연동
- [x] [P1] (setup) codex/claude/gemini container tool 목록 제공 — `agent-tools` 명령 추가(에이전트별 settings/skills/LSP/공용 CLI 가용성 출력) 및 `README`/`TOOLS.md` 사용 가이드 반영
- [x] [P1] (quality) 저장소 전체 정합성 점검 및 pruning 완료 — 구현/문서 불일치 보정, dead path 정리, TODO/MEMORY 히스토리 압축
- [x] [P1] (quality) stale prune 로직 제거 — home 잔존 스킬 정리가 완료된 이후 유지 비용을 줄이기 위해 `start.sh`의 stale skill prune/관련 state 정리 분기를 제거하고, `smoke-test.sh` install-policy 체크도 stale-prune 전제 없이 managed sync 정책만 검증하도록 정리
- [x] [P1] (quality) stale skill 정리 정책 단순화 — `LEGACY_PRUNED_SHARED_SKILLS` 강제 제거 목록을 폐기하고, `start.sh` stale prune을 managed state(`*.sha256`) 보유 항목으로 한정해 사용자 커스텀 동명이인 스킬 오삭제 가능성을 제거. `smoke-test.sh`도 해당 가드(`state file required`, legacy 목록 미사용) 검증으로 강화
- [x] [P1] (setup) shared skills 최신화 정책 재정비 — `start.sh`에 hash state 기반 managed sync(로컬 수정 감지, legacy 백업/채택, bundle-change 최적화)를 도입해 기존 persisted home도 안전하게 최신 번들 반영, 외부 스킬 주간 갱신 워크플로우(`.github/workflows/update-external-skills.yml`)와 실험용 헬퍼(`scripts/skills-helper.sh`) 추가
- [x] [P1] (setup) Playwright Chromium 동반 설치 보장 — Dockerfile build-time assert + `start.sh` self-heal + smoke-test companion/bootstrap 검증으로 런타임 보장 강화
- [x] [P1] (quality) Ars Contexta 설치 회복탄력성 보강 — sentinel stale 자동 복구 및 marketplace short-circuit로 startup 안정화
- [x] [P2] (ops) Docker/home 저장공간 가드 도입 — `docker-storage-guard.sh`, `home-storage-guard.sh`와 운영 가이드 반영
- [x] [P2] (usability) Codex 기본 편의 기능 확장 — `undo`, `multi_agent`, `apps`, `max_threads` 기본값 및 안전 병합

## Done Archive
- Full historical completed list: `docs/archive/2026-02-18-todo-before-prune.md`
