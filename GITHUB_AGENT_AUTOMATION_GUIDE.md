# GitHub Agent Automation Guide (Personal/Public Repo)

이 문서는 **본인 1인 운영 + public 저장소** 기준으로,
GitHub Issues/PR 자동화를 안전하게 켜는 절차를 정리합니다.

대상 워크플로우:
- `.github/workflows/agent-issue-intake.yml`
- `.github/workflows/agent-issue-worker.yml`
- `.github/workflows/agent-pr-reviewer.yml`
- `.github/workflows/claude.yml`
- `.github/workflows/claude-code-review.yml`

## 1. 목표와 보안 모델

이 구성은 다음을 기본 전제로 합니다.

- 자동화 트리거는 **허용 사용자 allowlist**에 포함된 계정만 가능
- 이슈 자동 작업은 Claude/Codex 중 선택 가능
- PR 자동 리뷰는 Claude/Codex 중 선택 가능
- 액션은 태그가 아닌 **commit SHA pinning**으로 고정
- 이슈 작업 결과(브랜치/PR 생성), 리뷰 코멘트, artifact 업로드는 기본 활성화

## 2. 사전 준비

필수 도구:
- `gh` (GitHub CLI)
- `base64`
- `codex` (로컬 로그인 완료 상태)

저장소 연결 확인:

```bash
gh auth status
gh repo view
```

## 3. GitHub Secrets 설정

아래 시크릿을 저장소에 등록합니다.

### 3.1 허용 사용자 (필수)

`AGENT_ALLOWED_ACTORS`
- 자동화를 허용할 GitHub 로그인 목록 (쉼표 구분)
- 1인 운영이면 본인 ID만 등록

```bash
gh secret set AGENT_ALLOWED_ACTORS --body "<your-github-login>"
```

예:

```bash
gh secret set AGENT_ALLOWED_ACTORS --body "my-github-id"
```

### 3.2 Claude OAuth 토큰 (Claude 사용 시 필수)

`CLAUDE_CODE_OAUTH_TOKEN`

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "<claude-oauth-token>"
```

### 3.3 Codex 로그인 캐시 (Codex 사용 시 필수)

`CODEX_AUTH_JSON_B64`
- 로컬 `~/.codex/auth.json`을 base64 인코딩해서 저장

```bash
base64 < ~/.codex/auth.json | tr -d '\n' | gh secret set CODEX_AUTH_JSON_B64
```

## 4. (권장) 저장소 보안 설정

### 4.1 기본 브랜치 보호

`main`(또는 기본 브랜치)에 대해 최소 아래를 권장:
- direct push 금지
- PR merge만 허용

워크플로우가 기본 브랜치로 직접 푸시하지 않도록 설계되어 있지만,
브랜치 보호는 필수 안전망입니다.

### 4.2 Actions 권한 정책

Repository Settings > Actions:
- Allow actions: 필요한 액션만 허용(또는 organization 정책 준수)
- Workflow permissions: 기본 `Read repository contents` 권장
  - 이 워크플로우는 job 단위 `permissions`로 필요한 쓰기 권한만 요청

## 5. 실행 방법

## 5.1 이슈 자동 작업

트리거 방법 A (라벨):
- 이슈에 `agent:auto` 라벨 추가
- 선택 라벨: `agent:claude` 또는 `agent:codex` (없으면 기본값 사용)

트리거 방법 B (코멘트):
- 이슈 코멘트로 실행

```text
/agent run
/agent run claude
/agent run codex 버그 재현 후 테스트도 추가해줘
```

### 5.1.1 `@claude` 멘션으로 이슈 자동 해결 → PR 생성

`claude.yml` 워크플로우가 `@claude` 멘션을 감지하여 자동으로 이슈를 해결하고 PR을 생성합니다.

트리거 조건:
- 이슈 제목 또는 본문에 `@claude`를 포함하여 이슈 생성
- 기존 이슈에 `@claude`를 포함한 코멘트 작성

```text
@claude 이 버그 수정해줘
```

동작 방식:
1. Claude가 이슈 내용을 읽고 코드 변경을 수행
2. `agent/issue-<번호>` 브랜치를 생성하고 변경사항을 커밋/푸시
3. 기본 브랜치를 대상으로 PR을 자동 생성 (이슈 자동 닫힘 포함)

참고:
- PR 코멘트에서 `@claude`를 멘션하면 대화형 모드로 동작합니다 (코드 리뷰/질문 응답).
- `claude.yml`도 `AGENT_ALLOWED_ACTORS` allowlist를 검증합니다 (다른 워크플로우와 동일한 보안 모델).

## 5.2 PR 자동 리뷰

트리거 방법 A (라벨):
- PR에 `agent:review` 라벨 추가
- 선택 라벨: `agent:claude` 또는 `agent:codex`

트리거 방법 B (코멘트):

```text
/agent review
/agent review codex 보안 관점으로만 봐줘
```

### 5.2.1 Claude Code Review 워크플로우 자동 실행

`claude-code-review.yml`은 아래 PR 이벤트에서 자동 실행됩니다.

- `opened`
- `synchronize`
- `ready_for_review`
- `reopened`

실행 조건:
- `AGENT_ALLOWED_ACTORS` allowlist에 포함된 actor일 때만 리뷰 실행
- `CLAUDE_CODE_OAUTH_TOKEN`이 설정되어 있어야 함

## 6. 내부 안전장치 요약

이 워크플로우는 아래를 강제합니다.

- allowlist 비어 있으면 실행 거부 (fail-closed)
- `github-actions[bot]` 이벤트 무시
- 작성자/이벤트 발신자/요청자 allowlist 검증
- Claude 전용 워크플로우(`claude.yml`, `claude-code-review.yml`)도 allowlist 검증 적용
- PR 리뷰 경로는 foreign fork PR head를 감지하면 자동 실행을 스킵
- reusable workflow 호출 시 `secrets: inherit` 미사용
- 필요한 시크릿만 명시 전달
- `actions/*`, `anthropics/*` 액션 SHA 고정
- Codex CLI 버전 고정 설치
- AI 실행 전 `git push` 경로 차단(`agent-issue-worker.yml` 경로에 적용)
- job timeout 설정
- 이슈 작업 결과(브랜치/PR), 리뷰 코멘트, artifact 업로드는 항상 활성화

## 7. 점검 체크리스트

아래 순서로 테스트하세요.

1. 시크릿 등록 확인
```bash
gh secret list
```

2. 본인 계정으로 이슈 생성 후 코멘트 실행
```text
/agent run codex README 오탈자 하나만 수정해줘
```

3. Actions 로그에서 확인할 항목
- route 단계에서 allowlist 통과
- worker 단계에서 branch `agent/issue-<번호>` 생성
- 변경사항이 있으면 artifact 업로드 및 PR 생성/재사용 확인

4. PR에서 리뷰 코멘트 실행
```text
/agent review codex
```

## 8. 자주 발생하는 문제

### 8.1 `AGENT_ALLOWED_ACTORS secret is empty`
- 원인: allowlist 미등록
- 해결:
```bash
gh secret set AGENT_ALLOWED_ACTORS --body "<your-github-login>"
```

### 8.2 `CODEX_AUTH_JSON_B64 is required for agent=codex`
- 원인: Codex auth cache 미등록
- 해결: 3.3 절차로 재등록

### 8.3 Claude 실행 실패 (OAuth 토큰)
- 원인: `CLAUDE_CODE_OAUTH_TOKEN` 만료/오입력
- 해결: 토큰 갱신 후 secret 재등록

## 9. 운영 팁 (1인 public 저장소)

- allowlist를 본인 1명으로 유지
- 외부 기여자 이슈/코멘트는 자동 실행 대상에서 제외됨이 정상
- 주기적으로 secret rotation 권장:
  - Claude OAuth 토큰
  - Codex 로그인 캐시 (재로그인 후 갱신)
