# GitHub Agent Automation Guide (Personal/Public Repo)

이 문서는 **본인 1인 운영 + public 저장소** 기준으로,
GitHub Issues/PR 자동화를 안전하게 켜는 절차를 정리합니다.

대상 워크플로우:
- `.github/workflows/agent-issue-intake.yml`
- `.github/workflows/agent-issue-worker.yml`
- `.github/workflows/agent-pr-reviewer.yml`

## 1. 목표와 보안 모델

이 구성은 다음을 기본 전제로 합니다.

- 자동화 트리거는 **허용 사용자 allowlist**에 포함된 계정만 가능
- 이슈 자동 작업은 Claude/Codex 중 선택 가능
- PR 자동 리뷰는 Claude/Codex 중 선택 가능
- 액션은 태그가 아닌 **commit SHA pinning**으로 고정
- 기본값은 **비공개 모드** (자동 PR 공개/상세 리뷰 코멘트 공개 비활성)

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

### 3.4 공개 동작 제어 (선택)

기본값은 보수적(non-public)입니다.

- `AGENT_AUTO_PUBLISH=true`
  - 이슈 작업 결과를 브랜치/PR로 자동 공개
  - 미설정 시 자동 공개하지 않음
- `AGENT_PUBLIC_REVIEW_COMMENT=true`
  - PR 코멘트에 상세 리뷰 본문 공개
  - 미설정 시 요약 안내만 코멘트
- `AGENT_PUBLIC_ARTIFACTS=true`
  - patch/review artifact 업로드
  - 미설정 시 artifact 업로드 비활성 (기본)

```bash
gh secret set AGENT_AUTO_PUBLISH --body "true"
gh secret set AGENT_PUBLIC_REVIEW_COMMENT --body "true"
gh secret set AGENT_PUBLIC_ARTIFACTS --body "true"
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

## 5.2 PR 자동 리뷰

트리거 방법 A (라벨):
- PR에 `agent:review` 라벨 추가
- 선택 라벨: `agent:claude` 또는 `agent:codex`

트리거 방법 B (코멘트):

```text
/agent review
/agent review codex 보안 관점으로만 봐줘
```

## 6. 내부 안전장치 요약

이 워크플로우는 아래를 강제합니다.

- allowlist 비어 있으면 실행 거부 (fail-closed)
- `github-actions[bot]` 이벤트 무시
- 작성자/이벤트 발신자/요청자 allowlist 검증
- reusable workflow 호출 시 `secrets: inherit` 미사용
- 필요한 시크릿만 명시 전달
- `actions/*`, `anthropics/*` 액션 SHA 고정
- Codex CLI 버전 고정 설치
- AI 실행 전 `git push` 경로 차단
- job timeout 설정
- 기본 비공개 모드: 자동 공개/상세 리뷰 코멘트/artifact 업로드는 opt-in secret으로만 활성화

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
- 기본 비공개 모드에서는 patch/review artifact 미업로드
- `AGENT_AUTO_PUBLISH=true`일 때만 PR 생성/재사용

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

### 8.4 자동으로 PR이 생성되지 않음
- 원인: 기본 비공개 모드(`AGENT_AUTO_PUBLISH` 미설정 또는 `false`)
- 해결:
```bash
gh secret set AGENT_AUTO_PUBLISH --body "true"
```

### 8.5 PR 코멘트에 상세 리뷰가 보이지 않음
- 원인: 기본 비공개 모드(`AGENT_PUBLIC_REVIEW_COMMENT` 미설정 또는 `false`)
- 해결:
```bash
gh secret set AGENT_PUBLIC_REVIEW_COMMENT --body "true"
```

### 8.6 artifact가 업로드되지 않음
- 원인: 기본 비공개 모드(`AGENT_PUBLIC_ARTIFACTS` 미설정 또는 `false`)
- 해결:
```bash
gh secret set AGENT_PUBLIC_ARTIFACTS --body "true"
```

## 9. 운영 팁 (1인 public 저장소)

- allowlist를 본인 1명으로 유지
- 외부 기여자 이슈/코멘트는 자동 실행 대상에서 제외됨이 정상
- 주기적으로 secret rotation 권장:
  - Claude OAuth 토큰
  - Codex 로그인 캐시 (재로그인 후 갱신)
