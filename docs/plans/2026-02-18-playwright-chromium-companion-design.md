# Playwright Chromium Companion Guarantee Design

**Date:** 2026-02-18
**Task:** `TODO.md` pending P1 - Playwright Chromium 동반 설치 보장

## Goal
`@playwright/cli`가 설치된 이미지에서 Chromium companion browser가 빌드/런타임 모두에서 즉시 사용 가능하도록 보장한다.

## Final Design
1. Build-time guarantee (`Dockerfile`)
- `playwright-cli install` 후 Chromium binary 탐색.
- `INSTALLATION_COMPLETE` marker 확인.
- Chromium binary 실행(`--version`) 검증.

2. Runtime guarantee (`scripts/start.sh`)
- `ensure_playwright_chromium()`를 엔트리포인트에 추가.
- Primary path(`PLAYWRIGHT_BROWSERS_PATH`, 기본 `/ms-playwright`) 우선 검증.
- 누락/손상 시 fallback path(`~/.cache/ms-playwright`) 재검증/복구.
- `flock` 잠금으로 동시 복구 충돌 방지.
- isolated bootstrap dir(`playwright-bootstrap.*`)에서 설치 실행(워크스페이스 오염 방지).
- writable TMPDIR 후보 전략 적용.
- 최종 launch probe(`open about:blank`)까지 통과하지 못하면 fail-closed(non-zero).

3. Verification guarantee (`scripts/smoke-test.sh`)
- `playwright-cli --version` 외에 companion payload + launch probe 체크 추가.
- runtime bootstrap 정책(함수/호출/fallback/lock/isolated bootstrap/fail-closed) 정적+행동 검증 추가.

## Expert Review Iterations
1. Review #1: 기존 상태가 CLI 존재만 검증하고 runtime self-heal이 없음을 확인.
2. Review #2: TMPDIR/경로 전환/검증 강도/오프라인 smoke 깊이 강화 요구.
3. Review #3: fail policy 명확화, isolated install workspace, launch-level validation 필요.
4. Review #4 gate: 구현 전 no-go 기준 확인 후 코드 반영.

## Acceptance Criteria
- build 중 Chromium payload가 실제 실행 가능한 상태로 검증된다.
- startup에서 companion 누락 시 fallback 복구가 동작하며 실패 시 즉시 종료한다.
- smoke-test가 companion/runtime bootstrap 회귀를 잡아낸다.
